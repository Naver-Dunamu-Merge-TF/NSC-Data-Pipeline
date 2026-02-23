"""SEC-004 probe: validate secret scope read + runtime secret loader path."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone

from pyspark.sql import SparkSession

from src.io.secret_loader import resolve_user_key_salt


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def compute_secret_fingerprint(secret_value: str) -> tuple[str, int]:
    encoded = secret_value.encode("utf-8")
    digest = hashlib.sha256(encoded).hexdigest()
    return digest, len(secret_value)


def _emit(step: str, **payload: object) -> None:
    event = {"ts_utc": _utc_now(), "step": step, **payload}
    print(json.dumps(event, sort_keys=True), flush=True)


def _get_dbutils(spark: SparkSession):
    from pyspark.dbutils import DBUtils

    return DBUtils(spark)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="SEC-004 probe (KV-backed secret scope + resolver validation)."
    )
    parser.add_argument("--run-id", default="")
    parser.add_argument("--secret-scope", required=True)
    parser.add_argument("--secret-key", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    run_id = (
        args.run_id or f"sec004_{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}"
    )
    _emit(
        "start",
        run_id=run_id,
        secret_scope=args.secret_scope,
        secret_key=args.secret_key,
    )

    spark = SparkSession.builder.getOrCreate()
    dbutils = _get_dbutils(spark)

    try:
        secret_value = dbutils.secrets.get(scope=args.secret_scope, key=args.secret_key)
        secret_sha256, secret_length = compute_secret_fingerprint(secret_value)

        resolved_salt = resolve_user_key_salt(
            secret_scope=args.secret_scope,
            secret_key=args.secret_key,
            dbutils=dbutils,
            allow_local_fallback=False,
        )
        resolved_sha256, resolved_length = compute_secret_fingerprint(resolved_salt)

        if secret_sha256 != resolved_sha256:
            raise RuntimeError("Resolver salt fingerprint mismatch")

        _emit(
            "secret_scope_read_ok",
            run_id=run_id,
            secret_scope=args.secret_scope,
            secret_key=args.secret_key,
            secret_length=secret_length,
            secret_sha256=secret_sha256,
            resolved_length=resolved_length,
            resolver_verified=True,
        )
    except Exception as exc:  # noqa: BLE001
        _emit(
            "failure",
            run_id=run_id,
            secret_scope=args.secret_scope,
            secret_key=args.secret_key,
            error_type=type(exc).__name__,
            error=str(exc),
        )
        return 1

    _emit("success", run_id=run_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
