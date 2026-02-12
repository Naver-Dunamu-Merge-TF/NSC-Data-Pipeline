from __future__ import annotations

import argparse
import inspect
import os
import sys
from datetime import date, datetime
from hashlib import sha1
from pathlib import Path

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

# Bootstrap: ensure repo root is on sys.path for src.* imports.
_SCRIPT_PATH = (
    globals().get("__file__") or inspect.getframeinfo(inspect.currentframe()).filename
)
_REPO_ROOT = Path(_SCRIPT_PATH).resolve().parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from src.common.config_loader import find_repo_root, get_config_value  # noqa: E402
from src.io.spark_safety import safe_collect  # noqa: E402

TASK_ALL = "all"
TASK_RECON = "recon"
TASK_SUPPLY_OPS = "supply_ops"
TASK_FINALIZE_SUCCESS = "finalize_success"
TASK_FINALIZE_FAILURE = "finalize_failure"
ENGINE_MODE_LEGACY = "legacy"
ENGINE_MODE_SPARK = "spark"
MAX_PIPELINE_STATE_ROWS = 1
MAX_DQ_STATUS_ROWS = 100_000
MAX_WALLET_SNAPSHOT_ROWS = 2_000_000
MAX_LEDGER_ENTRIES_ROWS = 5_000_000
MAX_PAYMENT_ORDERS_ROWS = 2_000_000

VALID_TASKS = {
    TASK_ALL,
    TASK_RECON,
    TASK_SUPPLY_OPS,
    TASK_FINALIZE_SUCCESS,
    TASK_FINALIZE_FAILURE,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Pipeline B (Ledger/Admin controls) in Databricks."
    )
    parser.add_argument("--catalog", default=get_config_value("databricks.catalog"))
    parser.add_argument(
        "--task",
        default=TASK_ALL,
        choices=sorted(VALID_TASKS),
        help="Select which Pipeline B task to run (useful for multi-task workflows).",
    )
    parser.add_argument("--run-mode", default="")
    parser.add_argument("--start-ts")
    parser.add_argument("--end-ts")
    parser.add_argument("--date-kst-start")
    parser.add_argument("--date-kst-end")
    parser.add_argument("--run-id")
    parser.add_argument(
        "--engine-mode",
        default=ENGINE_MODE_LEGACY,
        choices=(ENGINE_MODE_LEGACY, ENGINE_MODE_SPARK),
    )
    parser.add_argument(
        "--rule-load-mode",
        default="fallback",
        choices=("strict", "fallback"),
        help="Rule load mode: strict(table only) or fallback(table->seed).",
    )
    parser.add_argument(
        "--rule-table",
        default="gold.dim_rule_scd2",
        help="Rule table name (gold.dim_rule_scd2 or fully-qualified catalog.schema.table).",
    )
    parser.add_argument(
        "--rule-seed-path",
        default="mock_data/fixtures/dim_rule_scd2.json",
        help="Fallback rule seed path.",
    )
    parser.add_argument(
        "--repo-root",
        default=str(find_repo_root()),
    )
    parser.add_argument(
        "--skip-upstream-readiness-check",
        action="store_true",
        help="Skip fail-closed upstream readiness check for emergency/manual runs.",
    )
    return parser.parse_args()


def _contract_schema(contract):
    """Build a Spark StructType from a TableContract."""
    from pyspark.sql.types import StructType

    _type_map = {"bigint": "long", "int": "integer"}
    schema = StructType()
    for col in contract.columns:
        spark_type = _type_map.get(col.data_type, col.data_type)
        schema.add(col.name, spark_type, nullable=True)
    return schema


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
    rows = safe_collect(
        spark.table(table_fqn).filter(F.col("pipeline_name") == F.lit(pipeline_name)),
        max_rows=MAX_PIPELINE_STATE_ROWS,
        context=f"pipeline_state:{pipeline_name}",
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
    df = _align_to_contract(
        spark.createDataFrame(rows, schema=_contract_schema(contract)), contract
    )
    write_gold_delta(
        df,
        f"{catalog}.gold.{short_name}",
        table_name=table_name,
        mode="overwrite",
    )


def _load_dq_tags_by_date(spark, dq_table: str) -> dict[date, list[str]]:
    dq_tags_by_date: dict[date, list[str]] = {}
    if not spark.catalog.tableExists(dq_table):
        return dq_tags_by_date
    for row in safe_collect(
        spark.table(dq_table),
        max_rows=MAX_DQ_STATUS_ROWS,
        context="pipeline_b:dq_status",
    ):
        payload = row.asDict(recursive=True)
        row_date = _normalize_date(payload.get("date_kst"))
        dq_tag = payload.get("dq_tag")
        if row_date is None or not dq_tag:
            continue
        dq_tags_by_date.setdefault(row_date, []).append(str(dq_tag))
    return dq_tags_by_date


def _write_pipeline_state(
    spark,
    *,
    catalog: str,
    pipeline_name: str,
    run_id: str,
    status: str,
    last_processed_end,
) -> None:
    from src.common.contracts import get_contract
    from src.io.pipeline_state_io import (
        STATE_FAILURE,
        STATE_SUCCESS,
        apply_pipeline_state,
        write_pipeline_state_delta,
    )

    table_fqn = f"{catalog}.gold.pipeline_state"
    contract = get_contract("gold.pipeline_state")

    if status == STATE_SUCCESS:
        state = apply_pipeline_state(
            pipeline_name=pipeline_name,
            run_id=run_id,
            status=STATE_SUCCESS,
            last_processed_end=last_processed_end,
        )
    elif status == STATE_FAILURE:
        current_state = _load_current_state(spark, table_fqn, pipeline_name)
        state = apply_pipeline_state(
            pipeline_name=pipeline_name,
            run_id=run_id,
            status=STATE_FAILURE,
            current_state=current_state,
        )
    else:
        raise ValueError(f"Unsupported pipeline_state status: {status!r}")

    state_df = _align_to_contract(
        spark.createDataFrame(
            [state.as_dict()],
            schema=_contract_schema(contract),
        ),
        contract,
    )
    write_pipeline_state_delta(state_df, table_fqn)


def _resolve_run_id(*, pipeline_name: str, args: argparse.Namespace) -> str:
    raw = str(args.run_id).strip() if args.run_id is not None else ""
    if raw:
        return raw

    # Databricks jobs expose run context in different ways depending on
    # runtime/launcher. Prefer environment-provided IDs when available.
    for key in (
        "DATABRICKS_JOB_RUN_ID",
        "DB_JOB_RUN_ID",
        "DATABRICKS_RUN_ID",
        "DB_RUN_ID",
        "JOB_RUN_ID",
        "RUN_ID",
    ):
        value = os.environ.get(key)
        if value:
            return f"{pipeline_name}_{value}"

    # Fallback: stable per window so multi-task workflows share the same run_id
    # even when job parameters omit it.
    seed = "|".join(
        (
            pipeline_name,
            str(getattr(args, "run_mode", "") or ""),
            str(getattr(args, "start_ts", "") or ""),
            str(getattr(args, "end_ts", "") or ""),
            str(getattr(args, "date_kst_start", "") or ""),
            str(getattr(args, "date_kst_end", "") or ""),
        )
    )
    digest = sha1(seed.encode("utf-8")).hexdigest()[:12]
    return f"{pipeline_name}_{digest}"


def _resolve_seed_path(repo_root: Path, seed_path: str) -> Path:
    path = Path(seed_path)
    if path.is_absolute():
        return path
    return repo_root / path


def main() -> None:
    args = parse_args()
    repo_root = Path(args.repo_root)
    if repo_root.as_posix() not in sys.path:
        sys.path.insert(0, repo_root.as_posix())

    from src.common.job_params import JobParams
    from src.common.window_defaults import inject_default_daily_backfill
    from src.io.pipeline_state_io import STATE_FAILURE, STATE_SUCCESS
    from src.io.rule_loader import load_runtime_rules
    from src.io.upstream_readiness import assert_pipeline_ready
    from src.transforms.ledger_controls import (
        build_admin_tx_search,
        build_ops_ledger_pairing_quality_daily,
        build_ops_payment_failure_daily,
        build_ops_payment_refund_daily,
        build_recon_snapshot_flow,
        build_supply_balance_daily,
    )

    spark = SparkSession.builder.getOrCreate()
    engine_mode = getattr(args, "engine_mode", ENGINE_MODE_LEGACY)
    if engine_mode == ENGINE_MODE_SPARK:
        raise NotImplementedError(
            "pipeline_b spark engine path is not implemented yet; use --engine-mode legacy"
        )
    if engine_mode != ENGINE_MODE_LEGACY:
        raise ValueError(f"Unsupported engine mode: {engine_mode!r}")

    params_payload = inject_default_daily_backfill(
        {
            "run_mode": args.run_mode,
            "start_ts": args.start_ts,
            "end_ts": args.end_ts,
            "date_kst_start": args.date_kst_start,
            "date_kst_end": args.date_kst_end,
            "run_id": args.run_id,
        }
    )
    args.run_mode = params_payload.get("run_mode")
    args.start_ts = params_payload.get("start_ts")
    args.end_ts = params_payload.get("end_ts")
    args.date_kst_start = params_payload.get("date_kst_start")
    args.date_kst_end = params_payload.get("date_kst_end")
    resolved_run_id = _resolve_run_id(pipeline_name="pipeline_b", args=args)
    params = JobParams.from_mapping(
        {
            "run_mode": params_payload.get("run_mode"),
            "start_ts": params_payload.get("start_ts"),
            "end_ts": params_payload.get("end_ts"),
            "date_kst_start": params_payload.get("date_kst_start"),
            "date_kst_end": params_payload.get("date_kst_end"),
            "run_id": resolved_run_id,
        },
        pipeline_name="pipeline_b",
    )

    task = str(args.task).strip().lower()
    if task not in VALID_TASKS:
        raise ValueError(f"Unknown pipeline_b task: {args.task!r}")

    # Finalize tasks only touch pipeline_state to avoid write races when
    # Pipeline B is split into multiple Databricks Workflow tasks.
    if task in {TASK_FINALIZE_SUCCESS, TASK_FINALIZE_FAILURE}:
        if task == TASK_FINALIZE_SUCCESS:
            _write_pipeline_state(
                spark,
                catalog=args.catalog,
                pipeline_name="pipeline_b",
                run_id=params.run_id,
                status=STATE_SUCCESS,
                last_processed_end=params.processed_end_utc(),
            )
            return
        _write_pipeline_state(
            spark,
            catalog=args.catalog,
            pipeline_name="pipeline_b",
            run_id=params.run_id,
            status=STATE_FAILURE,
            last_processed_end=None,
        )
        return

    try:
        if not args.skip_upstream_readiness_check:
            assert_pipeline_ready(
                spark,
                catalog=args.catalog,
                upstream_pipeline_name="pipeline_silver",
                required_processed_end=params.processed_end_utc(),
            )

        rules = load_runtime_rules(
            spark,
            catalog=args.catalog,
            mode=args.rule_load_mode,
            seed_path=_resolve_seed_path(repo_root, args.rule_seed_path),
            table_name=args.rule_table,
        )
        target_dates = params.target_dates()
        if not target_dates:
            raise ValueError("No target dates resolved for pipeline_b run")

        silver_schema = f"{args.catalog}.silver"
        bronze_schema = f"{args.catalog}.bronze"

        wallet_snapshots = [
            row.asDict(recursive=True)
            for row in safe_collect(
                spark.table(f"{silver_schema}.wallet_snapshot"),
                max_rows=MAX_WALLET_SNAPSHOT_ROWS,
                context="pipeline_b:wallet_snapshot",
            )
        ]
        ledger_entries = [
            row.asDict(recursive=True)
            for row in safe_collect(
                spark.table(f"{silver_schema}.ledger_entries"),
                max_rows=MAX_LEDGER_ENTRIES_ROWS,
                context="pipeline_b:ledger_entries",
            )
        ]
        payment_orders: list[dict] = []
        if task in {TASK_ALL, TASK_SUPPLY_OPS}:
            payment_orders = [
                row.asDict(recursive=True)
                for row in safe_collect(
                    spark.table(f"{bronze_schema}.payment_orders_raw"),
                    max_rows=MAX_PAYMENT_ORDERS_ROWS,
                    context="pipeline_b:payment_orders_raw",
                )
            ]

        dq_tags_by_date = _load_dq_tags_by_date(spark, f"{silver_schema}.dq_status")

        recon_rows: list[dict] = []
        supply_rows: list[dict] = []
        ops_failure_rows: list[dict] = []
        ops_refund_rows: list[dict] = []
        pairing_rows: list[dict] = []
        admin_rows: list[dict] = []
        exception_rows: list[dict] = []

        for target_date in target_dates:
            dq_tags = dq_tags_by_date.get(target_date)
            if task in {TASK_ALL, TASK_RECON}:
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

            if task in {TASK_ALL, TASK_SUPPLY_OPS}:
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

        if task == TASK_ALL:
            _write_pipeline_state(
                spark,
                catalog=args.catalog,
                pipeline_name="pipeline_b",
                run_id=params.run_id,
                status=STATE_SUCCESS,
                last_processed_end=params.processed_end_utc(),
            )
    except Exception:
        if task == TASK_ALL:
            _write_pipeline_state(
                spark,
                catalog=args.catalog,
                pipeline_name="pipeline_b",
                run_id=params.run_id,
                status=STATE_FAILURE,
                last_processed_end=None,
            )
        raise


if __name__ == "__main__":
    main()
