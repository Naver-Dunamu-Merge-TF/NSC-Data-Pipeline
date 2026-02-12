from __future__ import annotations

import shutil
from collections import Counter
from datetime import date, datetime
from decimal import Decimal

import pytest

pyspark = pytest.importorskip("pyspark")
if shutil.which("java") is None:
    pytest.skip("Java is required to run local PySpark tests (install OpenJDK).")

from pyspark.sql import SparkSession  # noqa: E402

from src.common.rules import select_rule  # noqa: E402
from src.common.time_utils import UTC, to_utc  # noqa: E402
from src.io.bronze_io import prepare_bronze_records  # noqa: E402
from src.io.rule_loader import load_default_rule_seed  # noqa: E402
from src.jobs.pipeline_silver_spark import transform_silver_tables_spark  # noqa: E402
from src.transforms import analytics, silver_controls  # noqa: E402

BASE_TS = datetime(2026, 2, 11, 0, 0, tzinfo=UTC)
SCENARIO_GLOB = "one_day_normal/*.jsonl"
RUN_ID = "run-pipeline-silver-parity"
LOCAL_TZ = datetime.now().astimezone().tzinfo


@pytest.fixture(scope="module")
def spark():
    session = (
        SparkSession.builder.master("local[1]")
        .appName("pipeline-silver-spark-parity")
        .config("spark.sql.session.timeZone", "UTC")
        .getOrCreate()
    )
    session.conf.set("spark.sql.session.timeZone", "UTC")
    yield session
    session.stop()


def _load(table_name: str) -> list[dict]:
    return prepare_bronze_records(
        table_name,
        file_glob=SCENARIO_GLOB,
        ingested_at=BASE_TS,
        source_extracted_at=BASE_TS,
        batch_id="batch-silver-spark-parity",
        source_system="mock",
    )


def _canonical_value(value):
    if isinstance(value, datetime):
        normalized = (
            value if value.tzinfo is not None else value.replace(tzinfo=LOCAL_TZ or UTC)
        )
        return to_utc(normalized).isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    return value


def _canonical_rows(rows: list[dict], *, sort_keys: tuple[str, ...]) -> list[dict]:
    canonical = [
        {column: _canonical_value(value) for column, value in row.items()}
        for row in rows
    ]
    return sorted(canonical, key=lambda row: tuple(row[key] for key in sort_keys))


def _run_legacy(
    *,
    wallet_raw: list[dict],
    ledger_raw: list[dict],
    payment_orders_raw: list[dict],
    orders_raw: list[dict],
    order_items_raw: list[dict],
    products_raw: list[dict],
):
    rules = load_default_rule_seed()
    bad_rate_rule = select_rule(rules, domain="silver", metric="bad_records_rate")
    entry_type_rule = select_rule(rules, domain="silver", metric="entry_type_allowed")
    status_rule = select_rule(rules, domain="silver", metric="payment_status_allowed")

    status_lookup = silver_controls.build_status_lookup(payment_orders_raw)
    wallet_result = silver_controls.transform_wallet_snapshot_records(
        wallet_raw,
        run_id=RUN_ID,
        rule_id=bad_rate_rule.rule_id if bad_rate_rule else None,
    )
    ledger_result = silver_controls.transform_ledger_entries_records(
        ledger_raw,
        run_id=RUN_ID,
        rule_id=entry_type_rule.rule_id if entry_type_rule else None,
        allowed_entry_types=silver_controls.resolve_allowed_values(entry_type_rule),
        allowed_statuses=silver_controls.resolve_allowed_values(status_rule),
        status_lookup=status_lookup,
    )
    order_events_result = analytics.transform_order_events_records(
        orders_raw,
        payment_orders_raw,
        run_id=RUN_ID,
    )
    order_items_result = analytics.transform_order_items_records(
        order_items_raw,
        run_id=RUN_ID,
    )
    products_result = analytics.transform_products_records(
        products_raw,
        run_id=RUN_ID,
    )
    return {
        "rules": rules,
        "bad_rate_rule": bad_rate_rule,
        "entry_type_rule": entry_type_rule,
        "status_rule": status_rule,
        "wallet_result": wallet_result,
        "ledger_result": ledger_result,
        "order_events_result": order_events_result,
        "order_items_result": order_items_result,
        "products_result": products_result,
    }


def _run_spark(
    spark,
    *,
    wallet_raw: list[dict],
    ledger_raw: list[dict],
    payment_orders_raw: list[dict],
    orders_raw: list[dict],
    order_items_raw: list[dict],
    products_raw: list[dict],
):
    rules = load_default_rule_seed()
    bad_rate_rule = select_rule(rules, domain="silver", metric="bad_records_rate")
    entry_type_rule = select_rule(rules, domain="silver", metric="entry_type_allowed")
    status_rule = select_rule(rules, domain="silver", metric="payment_status_allowed")

    return transform_silver_tables_spark(
        wallet_df=spark.createDataFrame(wallet_raw),
        ledger_df=spark.createDataFrame(ledger_raw),
        payment_orders_df=spark.createDataFrame(payment_orders_raw),
        orders_df=spark.createDataFrame(orders_raw),
        order_items_df=spark.createDataFrame(order_items_raw),
        products_df=spark.createDataFrame(products_raw),
        run_id=RUN_ID,
        bad_rate_rule_id=bad_rate_rule.rule_id if bad_rate_rule else None,
        entry_type_rule_id=entry_type_rule.rule_id if entry_type_rule else None,
        allowed_entry_types=silver_controls.resolve_allowed_values(entry_type_rule),
        allowed_statuses=silver_controls.resolve_allowed_values(status_rule),
    )


def test_pipeline_silver_spark_parity_one_day_normal(spark) -> None:
    wallet_raw = _load("user_wallets_raw")
    ledger_raw = _load("transaction_ledger_raw")
    payment_orders_raw = _load("payment_orders_raw")
    orders_raw = _load("orders_raw")
    order_items_raw = _load("order_items_raw")
    products_raw = _load("products_raw")

    legacy = _run_legacy(
        wallet_raw=wallet_raw,
        ledger_raw=ledger_raw,
        payment_orders_raw=payment_orders_raw,
        orders_raw=orders_raw,
        order_items_raw=order_items_raw,
        products_raw=products_raw,
    )
    spark_output = _run_spark(
        spark,
        wallet_raw=wallet_raw,
        ledger_raw=ledger_raw,
        payment_orders_raw=payment_orders_raw,
        orders_raw=orders_raw,
        order_items_raw=order_items_raw,
        products_raw=products_raw,
    )

    assert _canonical_rows(
        [
            row.asDict(recursive=True)
            for row in spark_output.wallet_snapshot_df.collect()
        ],
        sort_keys=("snapshot_ts", "user_id"),
    ) == _canonical_rows(
        legacy["wallet_result"].records,
        sort_keys=("snapshot_ts", "user_id"),
    )
    assert _canonical_rows(
        [
            row.asDict(recursive=True)
            for row in spark_output.ledger_entries_df.collect()
        ],
        sort_keys=("tx_id", "wallet_id"),
    ) == _canonical_rows(
        legacy["ledger_result"].records,
        sort_keys=("tx_id", "wallet_id"),
    )
    assert _canonical_rows(
        [row.asDict(recursive=True) for row in spark_output.order_events_df.collect()],
        sort_keys=("order_ref", "order_source"),
    ) == _canonical_rows(
        legacy["order_events_result"].records,
        sort_keys=("order_ref", "order_source"),
    )
    assert _canonical_rows(
        [row.asDict(recursive=True) for row in spark_output.order_items_df.collect()],
        sort_keys=("item_id",),
    ) == _canonical_rows(
        legacy["order_items_result"].records,
        sort_keys=("item_id",),
    )
    assert _canonical_rows(
        [row.asDict(recursive=True) for row in spark_output.products_df.collect()],
        sort_keys=("product_id",),
    ) == _canonical_rows(
        legacy["products_result"].records,
        sort_keys=("product_id",),
    )

    assert spark_output.wallet_valid_count == len(legacy["wallet_result"].records)
    assert spark_output.wallet_bad_count == len(legacy["wallet_result"].bad_records)
    assert spark_output.ledger_valid_count == len(legacy["ledger_result"].records)
    assert spark_output.ledger_bad_count == len(legacy["ledger_result"].bad_records)


def test_pipeline_silver_spark_parity_bad_reason_counts(spark) -> None:
    wallet_raw = _load("user_wallets_raw")
    ledger_raw = _load("transaction_ledger_raw")
    payment_orders_raw = _load("payment_orders_raw")
    orders_raw = _load("orders_raw")
    order_items_raw = _load("order_items_raw")
    products_raw = _load("products_raw")

    wallet_raw.append(
        {
            "user_id": "",
            "balance": "1000",
            "frozen_amount": "0",
            "updated_at": BASE_TS,
            "ingested_at": BASE_TS,
            "source_extracted_at": BASE_TS,
            "batch_id": "batch-bad-wallet",
            "source_system": "mock",
        }
    )
    ledger_raw.append(
        {
            "tx_id": "bad-ledger-entry-1",
            "wallet_id": "u_bad",
            "type": "UNKNOWN_TYPE",
            "amount": "100",
            "related_id": None,
            "created_at": BASE_TS,
            "ingested_at": BASE_TS,
            "source_extracted_at": BASE_TS,
            "batch_id": "batch-bad-ledger",
            "source_system": "mock",
        }
    )

    legacy = _run_legacy(
        wallet_raw=wallet_raw,
        ledger_raw=ledger_raw,
        payment_orders_raw=payment_orders_raw,
        orders_raw=orders_raw,
        order_items_raw=order_items_raw,
        products_raw=products_raw,
    )
    spark_output = _run_spark(
        spark,
        wallet_raw=wallet_raw,
        ledger_raw=ledger_raw,
        payment_orders_raw=payment_orders_raw,
        orders_raw=orders_raw,
        order_items_raw=order_items_raw,
        products_raw=products_raw,
    )

    legacy_bad = []
    legacy_bad.extend(legacy["wallet_result"].bad_records)
    legacy_bad.extend(legacy["ledger_result"].bad_records)
    legacy_bad.extend(legacy["order_events_result"].bad_records)
    legacy_bad.extend(legacy["order_items_result"].bad_records)
    legacy_bad.extend(legacy["products_result"].bad_records)
    legacy_counter = Counter((row["source_table"], row["reason"]) for row in legacy_bad)

    spark_counter = Counter(
        (row["source_table"], row["reason"])
        for row in spark_output.bad_records_df.select(
            "source_table", "reason"
        ).collect()
    )
    assert spark_counter == legacy_counter
