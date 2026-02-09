from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from pyspark.sql import SparkSession
from pyspark.sql import functions as F


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Pipeline C (Analytics anonymized mart) in Databricks."
    )
    parser.add_argument("--catalog", default="2dt_final_team4_databricks_test")
    parser.add_argument("--run-mode", default="incremental")
    parser.add_argument("--run-id")
    parser.add_argument("--start-ts")
    parser.add_argument("--end-ts")
    parser.add_argument("--date-kst-start")
    parser.add_argument("--date-kst-end")
    parser.add_argument("--salt")
    parser.add_argument("--secret-scope", default="ledger-analytics-dev")
    parser.add_argument("--secret-key", default="salt_user_key")
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


def main() -> None:
    args = parse_args()
    repo_root = Path(args.repo_root)
    if repo_root.as_posix() not in sys.path:
        sys.path.insert(0, repo_root.as_posix())

    from src.common.contracts import get_contract
    from src.common.job_params import JobParams
    from src.io.gold_io import write_gold_delta
    from src.io.pipeline_state_io import (
        STATE_FAILURE,
        STATE_SUCCESS,
        apply_pipeline_state,
        write_pipeline_state_delta,
    )
    from src.jobs.pipeline_c import build_pipeline_c_fact_rows

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
        pipeline_name="pipeline_c",
    )

    silver_schema = f"{args.catalog}.silver"
    pipeline_state_table = f"{args.catalog}.gold.pipeline_state"
    pipeline_contract = get_contract("gold.pipeline_state")

    try:
        order_events_df = spark.table(f"{silver_schema}.order_events")
        if (
            params.start_ts
            and params.end_ts
            and "event_time" in order_events_df.columns
        ):
            order_events_df = order_events_df.filter(
                (F.col("event_time") >= F.lit(params.start_ts))
                & (F.col("event_time") < F.lit(params.end_ts))
            )
        elif params.target_dates() and "event_date_kst" in order_events_df.columns:
            order_events_df = order_events_df.filter(
                F.col("event_date_kst").isin(*params.target_dates())
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
            run_id=params.run_id,
            salt=args.salt,
            secret_scope=args.secret_scope,
            secret_key=args.secret_key,
        )

        if rows:
            contract = get_contract("gold.fact_payment_anonymized")
            df = _align_to_contract(spark.createDataFrame(rows), contract)
            target_table = f"{args.catalog}.gold.fact_payment_anonymized"
            write_gold_delta(
                df,
                target_table,
                table_name="gold.fact_payment_anonymized",
                mode="overwrite",
            )
            print(
                f"Upserted {len(rows)} rows into {target_table} (run_id={params.run_id})"
            )
        else:
            print("No rows generated for gold.fact_payment_anonymized")

        success_state = apply_pipeline_state(
            pipeline_name="pipeline_c",
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
            "pipeline_c",
        )
        failed_state = apply_pipeline_state(
            pipeline_name="pipeline_c",
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
