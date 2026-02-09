from __future__ import annotations

import argparse
import os
import sys
from datetime import date, datetime
from pathlib import Path

from pyspark.sql import SparkSession
from pyspark.sql import functions as F


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Pipeline B (Ledger/Admin controls) in Databricks."
    )
    parser.add_argument("--catalog", default="2dt_final_team4_databricks_test")
    parser.add_argument("--run-mode", default="incremental")
    parser.add_argument("--start-ts")
    parser.add_argument("--end-ts")
    parser.add_argument("--date-kst-start")
    parser.add_argument("--date-kst-end")
    parser.add_argument("--run-id")
    parser.add_argument(
        "--repo-root",
        default=os.environ.get("PIPELINE_ROOT", "/dbfs/tmp/data-pipeline"),
    )
    return parser.parse_args()


def _align_to_contract(df, contract):
    for column, data_type in contract.cast_map.items():
        if column in df.columns:
            df = df.withColumn(column, F.col(column).cast(data_type))
        else:
            df = df.withColumn(column, F.lit(None).cast(data_type))
    return df.select(*contract.column_names)


def _normalize_date(value) -> date | None:
    if value is None:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, str):
        return date.fromisoformat(value)
    return None


def _load_current_state(spark, table_fqn: str, pipeline_name: str):
    from src.io.pipeline_state_io import parse_pipeline_state_record

    if not spark.catalog.tableExists(table_fqn):
        return None
    rows = (
        spark.table(table_fqn)
        .filter(F.col("pipeline_name") == F.lit(pipeline_name))
        .limit(1)
        .collect()
    )
    if not rows:
        return None
    return parse_pipeline_state_record(rows[0].asDict(recursive=True))


def _write_gold_rows(
    spark,
    *,
    catalog: str,
    table_name: str,
    rows: list[dict],
) -> None:
    if not rows:
        return
    from src.common.contracts import get_contract, validate_required_columns
    from src.io.gold_io import write_gold_delta

    contract = get_contract(table_name)
    validate_required_columns(rows[0].keys(), contract)
    short_name = table_name.split(".", maxsplit=1)[1]
    df = _align_to_contract(spark.createDataFrame(rows), contract)
    write_gold_delta(
        df,
        f"{catalog}.gold.{short_name}",
        table_name=table_name,
        mode="overwrite",
    )


def main() -> None:
    args = parse_args()
    repo_root = Path(args.repo_root)
    if repo_root.as_posix() not in sys.path:
        sys.path.insert(0, repo_root.as_posix())

    from src.common.contracts import get_contract
    from src.common.job_params import JobParams
    from src.io.pipeline_state_io import (
        STATE_FAILURE,
        STATE_SUCCESS,
        apply_pipeline_state,
        write_pipeline_state_delta,
    )
    from src.io.rule_loader import load_rule_seed
    from src.transforms.ledger_controls import (
        build_admin_tx_search,
        build_ops_ledger_pairing_quality_daily,
        build_ops_payment_failure_daily,
        build_ops_payment_refund_daily,
        build_recon_snapshot_flow,
        build_supply_balance_daily,
    )

    spark = SparkSession.builder.getOrCreate()
    params = JobParams.from_mapping(
        {
            "run_mode": args.run_mode,
            "start_ts": args.start_ts,
            "end_ts": args.end_ts,
            "date_kst_start": args.date_kst_start,
            "date_kst_end": args.date_kst_end,
            "run_id": args.run_id,
        },
        pipeline_name="pipeline_b",
    )

    rules_path = repo_root / "mock_data" / "fixtures" / "dim_rule_scd2.json"
    rules = load_rule_seed(rules_path)
    target_dates = params.target_dates()
    if not target_dates:
        raise ValueError("No target dates resolved for pipeline_b run")

    silver_schema = f"{args.catalog}.silver"
    bronze_schema = f"{args.catalog}.bronze"

    wallet_snapshots = [
        row.asDict(recursive=True)
        for row in spark.table(f"{silver_schema}.wallet_snapshot").collect()
    ]
    ledger_entries = [
        row.asDict(recursive=True)
        for row in spark.table(f"{silver_schema}.ledger_entries").collect()
    ]
    payment_orders = [
        row.asDict(recursive=True)
        for row in spark.table(f"{bronze_schema}.payment_orders_raw").collect()
    ]

    dq_tags_by_date: dict[date, list[str]] = {}
    dq_table = f"{silver_schema}.dq_status"
    if spark.catalog.tableExists(dq_table):
        for row in spark.table(dq_table).collect():
            payload = row.asDict(recursive=True)
            row_date = _normalize_date(payload.get("date_kst"))
            dq_tag = payload.get("dq_tag")
            if row_date is None or not dq_tag:
                continue
            dq_tags_by_date.setdefault(row_date, []).append(str(dq_tag))

    recon_rows: list[dict] = []
    supply_rows: list[dict] = []
    ops_failure_rows: list[dict] = []
    ops_refund_rows: list[dict] = []
    pairing_rows: list[dict] = []
    admin_rows: list[dict] = []
    exception_rows: list[dict] = []

    pipeline_state_table = f"{args.catalog}.gold.pipeline_state"
    pipeline_contract = get_contract("gold.pipeline_state")

    try:
        for target_date in target_dates:
            dq_tags = dq_tags_by_date.get(target_date)
            recon_output = build_recon_snapshot_flow(
                wallet_snapshots,
                ledger_entries,
                target_date=target_date,
                run_id=params.run_id,
                rules=rules,
                dq_tags=dq_tags,
            )
            recon_rows.extend(recon_output.rows)
            exception_rows.extend(recon_output.exceptions)

            supply_output = build_supply_balance_daily(
                wallet_snapshots,
                ledger_entries,
                target_date=target_date,
                run_id=params.run_id,
                rules=rules,
                dq_tags=dq_tags,
            )
            supply_rows.append(supply_output.row)
            exception_rows.extend(supply_output.exceptions)

            ops_failure_rows.extend(
                build_ops_payment_failure_daily(
                    payment_orders,
                    target_date=target_date,
                    run_id=params.run_id,
                )
            )
            ops_refund_rows.extend(
                build_ops_payment_refund_daily(
                    payment_orders,
                    target_date=target_date,
                    run_id=params.run_id,
                )
            )
            pairing_rows.append(
                build_ops_ledger_pairing_quality_daily(
                    ledger_entries,
                    target_date=target_date,
                    run_id=params.run_id,
                    payment_orders=payment_orders,
                )
            )
            admin_rows.extend(
                build_admin_tx_search(
                    ledger_entries,
                    target_date=target_date,
                    run_id=params.run_id,
                )
            )

        _write_gold_rows(
            spark,
            catalog=args.catalog,
            table_name="gold.recon_daily_snapshot_flow",
            rows=recon_rows,
        )
        _write_gold_rows(
            spark,
            catalog=args.catalog,
            table_name="gold.ledger_supply_balance_daily",
            rows=supply_rows,
        )
        _write_gold_rows(
            spark,
            catalog=args.catalog,
            table_name="gold.ops_payment_failure_daily",
            rows=ops_failure_rows,
        )
        _write_gold_rows(
            spark,
            catalog=args.catalog,
            table_name="gold.ops_payment_refund_daily",
            rows=ops_refund_rows,
        )
        _write_gold_rows(
            spark,
            catalog=args.catalog,
            table_name="gold.ops_ledger_pairing_quality_daily",
            rows=pairing_rows,
        )
        _write_gold_rows(
            spark,
            catalog=args.catalog,
            table_name="gold.admin_tx_search",
            rows=admin_rows,
        )
        _write_gold_rows(
            spark,
            catalog=args.catalog,
            table_name="gold.exception_ledger",
            rows=exception_rows,
        )

        success_state = apply_pipeline_state(
            pipeline_name="pipeline_b",
            run_id=params.run_id,
            status=STATE_SUCCESS,
            last_processed_end=params.processed_end_utc(),
        )
        state_df = _align_to_contract(
            spark.createDataFrame([success_state.as_dict()]),
            pipeline_contract,
        )
        write_pipeline_state_delta(state_df, pipeline_state_table)
    except Exception:
        current_state = _load_current_state(
            spark,
            pipeline_state_table,
            "pipeline_b",
        )
        failed_state = apply_pipeline_state(
            pipeline_name="pipeline_b",
            run_id=params.run_id,
            status=STATE_FAILURE,
            current_state=current_state,
        )
        state_df = _align_to_contract(
            spark.createDataFrame([failed_state.as_dict()]),
            pipeline_contract,
        )
        write_pipeline_state_delta(state_df, pipeline_state_table)
        raise


if __name__ == "__main__":
    main()
