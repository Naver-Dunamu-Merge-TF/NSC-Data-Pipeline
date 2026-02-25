"""SEC-003 probe: validate UC/table privileges + external location R/W on serverless."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone

from pyspark.sql import SparkSession

SCHEMA_PROBE_TABLES: dict[str, str] = {
    "bronze": "user_wallets_raw",
    "silver": "wallet_snapshot",
    "gold": "pipeline_state",
}


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _sanitize_suffix(raw: str) -> str:
    normalized = re.sub(r"[^0-9A-Za-z_]", "_", raw.strip())
    normalized = re.sub(r"_+", "_", normalized).strip("_")
    if not normalized:
        return "probe"
    return normalized[:48]


def build_probe_location(base_path: str, run_id: str) -> str:
    # Keep probe at root-level file path to avoid nested Delta log directory checks.
    suffix = _sanitize_suffix(run_id)
    return f"{base_path.rstrip('/')}/_sec003_probe_{suffix}.txt"


def _emit(step: str, **payload: object) -> None:
    event = {"ts_utc": _utc_now(), "step": step, **payload}
    print(json.dumps(event, sort_keys=True), flush=True)


def _assert_uc_table_access(spark: SparkSession, catalog: str) -> None:
    spark.sql(f"USE CATALOG `{catalog}`")
    for schema_name, table_name in SCHEMA_PROBE_TABLES.items():
        table_fqn = f"`{catalog}`.`{schema_name}`.`{table_name}`"
        spark.sql(f"USE SCHEMA `{schema_name}`")
        spark.sql(f"SELECT * FROM {table_fqn} LIMIT 1")
        # DELETE with false predicate validates MODIFY privilege without changing data.
        spark.sql(f"DELETE FROM {table_fqn} WHERE 1 = 0")
        _emit(
            "uc_schema_table_ok",
            catalog=catalog,
            schema=schema_name,
            table=table_name,
        )


def _assert_external_location_rw(
    spark: SparkSession,
    catalog: str,
    external_location: str,
    base_path: str,
    run_id: str,
) -> None:
    probe_location = build_probe_location(base_path=base_path, run_id=run_id)
    marker = f"sec003::{run_id}"

    # Validate that external location metadata is queryable.
    spark.sql(f"DESCRIBE EXTERNAL LOCATION `{external_location}`")

    try:
        from pyspark.dbutils import DBUtils

        dbutils = DBUtils(spark)
        dbutils.fs.put(probe_location, marker, overwrite=True)
        # Runtime compatibility: some serverless runtimes don't accept keyword args.
        observed = dbutils.fs.head(probe_location, max(64, len(marker) + 16))
        if marker not in observed:
            raise RuntimeError("External location probe content mismatch")
        dbutils.fs.rm(probe_location, recurse=False)
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(f"External location probe failed: {exc}") from exc

    _emit(
        "external_location_rw_ok",
        external_location=external_location,
        probe_location=probe_location,
        marker_size=len(marker),
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="SEC-003 probe (UC ACL + external location read/write)."
    )
    parser.add_argument("--run-id", default="")
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--external-location", required=True)
    parser.add_argument("--base-path", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    run_id = (
        args.run_id or f"sec003_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    )
    _emit(
        "start",
        run_id=run_id,
        catalog=args.catalog,
        external_location=args.external_location,
        base_path=args.base_path,
    )

    spark = SparkSession.builder.getOrCreate()
    try:
        _assert_uc_table_access(spark=spark, catalog=args.catalog)
        _assert_external_location_rw(
            spark=spark,
            catalog=args.catalog,
            external_location=args.external_location,
            base_path=args.base_path,
            run_id=run_id,
        )
    except Exception as exc:  # noqa: BLE001
        _emit(
            "failure",
            run_id=run_id,
            error_type=type(exc).__name__,
            error=str(exc),
        )
        return 1

    _emit("success", run_id=run_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
