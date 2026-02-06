from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

from pyspark.sql import SparkSession, functions as F


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Pipeline C (Analytics anonymized mart) in Databricks."
    )
    parser.add_argument("--catalog", default="2dt_final_team4_databricks_test")
    parser.add_argument("--run-id")
    parser.add_argument("--start-ts")
    parser.add_argument("--end-ts")
    parser.add_argument("--salt")
    parser.add_argument("--secret-scope", default="ledger-analytics-dev")
    parser.add_argument("--secret-key", default="salt_user_key")
    parser.add_argument(
        "--repo-root",
        default=os.environ.get("PIPELINE_ROOT", "/dbfs/tmp/data-pipeline"),
    )
    return parser.parse_args()


def _parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
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
    from src.io.gold_io import write_gold_delta
    from src.jobs.pipeline_c import build_pipeline_c_fact_rows

    spark = SparkSession.builder.getOrCreate()
    run_id = args.run_id or generate_run_id("pipeline_c")

    silver_schema = f"{args.catalog}.silver"
    order_events_df = spark.table(f"{silver_schema}.order_events")
    start_ts = _parse_ts(args.start_ts)
    end_ts = _parse_ts(args.end_ts)
    if start_ts and end_ts and "event_time" in order_events_df.columns:
        order_events_df = order_events_df.filter(
            (F.col("event_time") >= F.lit(start_ts))
            & (F.col("event_time") < F.lit(end_ts))
        )

    order_events = [row.asDict(recursive=True) for row in order_events_df.collect()]
    order_items = [
        row.asDict(recursive=True)
        for row in spark.table(f"{silver_schema}.order_items").collect()
    ]
    products = [
        row.asDict(recursive=True)
        for row in spark.table(f"{silver_schema}.products").collect()
    ]

    rows = build_pipeline_c_fact_rows(
        order_events,
        order_items,
        products,
        run_id=run_id,
        salt=args.salt,
        secret_scope=args.secret_scope,
        secret_key=args.secret_key,
    )

    if not rows:
        print("No rows generated for gold.fact_payment_anonymized")
        return

    contract = get_contract("gold.fact_payment_anonymized")
    df = _align_to_contract(spark.createDataFrame(rows), contract)
    target_table = f"{args.catalog}.gold.fact_payment_anonymized"
    write_gold_delta(
        df,
        target_table,
        table_name="gold.fact_payment_anonymized",
        mode="overwrite",
    )
    print(f"Upserted {len(rows)} rows into {target_table} (run_id={run_id})")


if __name__ == "__main__":
    main()
