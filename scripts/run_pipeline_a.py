from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

from pyspark.sql import SparkSession, functions as F


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Pipeline A (Guardrail DQ) in Databricks."
    )
    parser.add_argument("--catalog", default="2dt_final_team4_databricks_test")
    parser.add_argument("--run-mode", default="incremental")
    parser.add_argument("--start-ts", required=True)
    parser.add_argument("--end-ts", required=True)
    parser.add_argument("--run-id")
    parser.add_argument(
        "--repo-root",
        default=os.environ.get("PIPELINE_ROOT", "/dbfs/tmp/data-pipeline"),
    )
    return parser.parse_args()


def _parse_ts(value: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)


def _align_to_contract(df, contract):
    for column, data_type in contract.cast_map.items():
        if column in df.columns:
            df = df.withColumn(column, F.col(column).cast(data_type))
        else:
            df = df.withColumn(column, F.lit(None).cast(data_type))
    return df.select(*contract.column_names)


def main() -> None:
    args = parse_args()
    repo_root = Path(args.repo_root)
    if repo_root.as_posix() not in sys.path:
        sys.path.insert(0, repo_root.as_posix())

    from src.common.contracts import get_contract
    from src.common.run_tracking import generate_run_id
    from src.io.rule_loader import load_rule_seed
    from src.transforms.dq_guardrail import DQTableConfig, build_dq_status

    spark = SparkSession.builder.getOrCreate()

    run_id = args.run_id or generate_run_id("pipeline_a")
    start_ts = _parse_ts(args.start_ts)
    end_ts = _parse_ts(args.end_ts)

    rules_path = repo_root / "mock_data" / "fixtures" / "dim_rule_scd2.json"
    rules = load_rule_seed(rules_path)

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
            run_id=run_id,
            rules=rules,
            previous_zero_windows=0,
        )
        dq_rows.append(output.dq_status)
        exception_rows.extend(output.exceptions)

    dq_contract = get_contract("silver.dq_status")
    ex_contract = get_contract("gold.exception_ledger")

    dq_df = _align_to_contract(spark.createDataFrame(dq_rows), dq_contract)
    ex_df = _align_to_contract(spark.createDataFrame(exception_rows), ex_contract)

    dq_df.write.format("delta").mode("append").partitionBy("date_kst").saveAsTable(
        f"{catalog}.silver.dq_status"
    )
    ex_df.write.format("delta").mode("append").partitionBy("date_kst").saveAsTable(
        f"{catalog}.gold.exception_ledger"
    )


if __name__ == "__main__":
    main()
