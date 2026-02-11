from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from pyspark.sql import SparkSession
from pyspark.sql import functions as F


def _default_repo_root() -> Path:
    """Best-effort repo root resolution for Databricks Jobs/Bundles."""
    candidates: list[Path] = []

    file_name = globals().get("__file__") or _default_repo_root.__code__.co_filename
    if file_name:
        candidates.append(Path(file_name))

    if sys.argv and sys.argv[0]:
        candidates.append(Path(sys.argv[0]))

    candidates.append(Path.cwd())

    env_root = os.environ.get("PIPELINE_ROOT")
    if env_root:
        candidates.append(Path(env_root))

    for base in candidates:
        for probe in (base, base.parent, *base.parents):
            if (probe / "src").is_dir() and (probe / "mock_data").is_dir():
                return probe

    return Path(env_root or "/dbfs/tmp/data-pipeline")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Pipeline A (Guardrail DQ) in Databricks."
    )
    parser.add_argument("--catalog", default="2dt_final_team4_databricks_test")
    parser.add_argument("--run-mode", default="incremental")
    parser.add_argument("--start-ts")
    parser.add_argument("--end-ts")
    parser.add_argument("--date-kst-start")
    parser.add_argument("--date-kst-end")
    parser.add_argument("--run-id")
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
        default=str(_default_repo_root()),
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

    from src.common.contracts import get_contract, validate_required_columns
    from src.common.job_params import JobParams
    from src.io.pipeline_state_io import (
        STATE_FAILURE,
        STATE_SUCCESS,
        apply_pipeline_state,
        parse_zero_window_counts,
        serialize_zero_window_counts,
        write_pipeline_state_delta,
    )
    from src.io.rule_loader import load_runtime_rules
    from src.transforms.dq_guardrail import DQTableConfig, build_dq_status

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
        pipeline_name="pipeline_a",
    )

    rules = load_runtime_rules(
        spark,
        catalog=args.catalog,
        mode=args.rule_load_mode,
        seed_path=_resolve_seed_path(repo_root, args.rule_seed_path),
        table_name=args.rule_table,
    )

    catalog = args.catalog
    bronze_schema = f"{catalog}.bronze"

    sources = [
        {
            "table": "transaction_ledger_raw",
            "dup_keys": ("tx_id",),
            "dup_metric": "dup_rate_tx_id",
            "freshness_fields": ("ingested_at", "created_at"),
        },
        {
            "table": "user_wallets_raw",
            "dup_keys": ("user_id",),
            "dup_metric": "dup_rate_user_id",
            "freshness_fields": ("ingested_at", "updated_at"),
        },
        {
            "table": "payment_orders_raw",
            "dup_keys": ("order_id",),
            "dup_metric": "dup_rate_order_id",
            "freshness_fields": ("ingested_at", "created_at"),
        },
    ]

    dq_rows: list[dict] = []
    exception_rows: list[dict] = []
    pipeline_state_table = f"{args.catalog}.gold.pipeline_state"
    pipeline_contract = get_contract("gold.pipeline_state")
    initial_state = _load_current_state(
        spark,
        pipeline_state_table,
        "pipeline_a",
    )
    zero_window_counts = parse_zero_window_counts(
        initial_state.dq_zero_window_counts if initial_state else None
    )

    try:
        for start_ts, end_ts in params.windows_utc():
            for source in sources:
                table_fqn = f"{bronze_schema}.{source['table']}"
                df = spark.table(table_fqn)
                if "created_at" in df.columns:
                    df = df.filter(
                        (F.col("created_at") >= F.lit(start_ts))
                        & (F.col("created_at") < F.lit(end_ts))
                    )
                elif "ingested_at" in df.columns:
                    df = df.filter(
                        (F.col("ingested_at") >= F.lit(start_ts))
                        & (F.col("ingested_at") < F.lit(end_ts))
                    )

                records = [row.asDict(recursive=True) for row in df.collect()]
                config = DQTableConfig(
                    source_table=f"bronze.{source['table']}",
                    window_start_ts=start_ts,
                    window_end_ts=end_ts,
                    dup_key_fields=source["dup_keys"],
                    dup_rule_metric=source["dup_metric"],
                    freshness_fields=source["freshness_fields"],
                )
                output = build_dq_status(
                    records,
                    config=config,
                    run_id=params.run_id,
                    rules=rules,
                    previous_zero_windows=zero_window_counts.get(
                        config.source_table, 0
                    ),
                )
                zero_window_counts[config.source_table] = output.zero_window_count
                dq_rows.append(output.dq_status)
                exception_rows.extend(output.exceptions)

        dq_contract = get_contract("silver.dq_status")
        ex_contract = get_contract("gold.exception_ledger")
        validate_required_columns(dq_rows[0].keys(), dq_contract)
        dq_df = _align_to_contract(
            spark.createDataFrame(dq_rows, schema=_contract_schema(dq_contract)),
            dq_contract,
        )
        dq_df.write.format("delta").mode("append").partitionBy("date_kst").saveAsTable(
            f"{catalog}.silver.dq_status"
        )

        if exception_rows:
            ex_df = _align_to_contract(
                spark.createDataFrame(
                    exception_rows, schema=_contract_schema(ex_contract)
                ),
                ex_contract,
            )
            ex_df.write.format("delta").mode("append").partitionBy(
                "date_kst"
            ).saveAsTable(f"{catalog}.gold.exception_ledger")

        success_state = apply_pipeline_state(
            pipeline_name="pipeline_a",
            run_id=params.run_id,
            status=STATE_SUCCESS,
            last_processed_end=params.processed_end_utc(),
            dq_zero_window_counts=serialize_zero_window_counts(zero_window_counts),
        )
        state_df = _align_to_contract(
            spark.createDataFrame(
                [success_state.as_dict()],
                schema=_contract_schema(pipeline_contract),
            ),
            pipeline_contract,
        )
        write_pipeline_state_delta(state_df, pipeline_state_table)
    except Exception:
        failed_state = apply_pipeline_state(
            pipeline_name="pipeline_a",
            run_id=params.run_id,
            status=STATE_FAILURE,
            current_state=initial_state,
        )
        state_df = _align_to_contract(
            spark.createDataFrame(
                [failed_state.as_dict()],
                schema=_contract_schema(pipeline_contract),
            ),
            pipeline_contract,
        )
        write_pipeline_state_delta(state_df, pipeline_state_table)
        raise


if __name__ == "__main__":
    main()
