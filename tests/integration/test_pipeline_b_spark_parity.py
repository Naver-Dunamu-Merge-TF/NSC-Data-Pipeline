from __future__ import annotations

import shutil
from datetime import date, datetime
from decimal import Decimal

import pytest

pyspark = pytest.importorskip("pyspark")
if shutil.which("java") is None:
    pytest.skip("Java is required to run local PySpark tests (install OpenJDK).")

from pyspark.sql import SparkSession  # noqa: E402

from src.common.time_utils import UTC, to_utc  # noqa: E402
from src.io.rule_loader import load_default_rule_seed  # noqa: E402
from src.jobs.pipeline_b_spark import transform_pipeline_b_tables_spark  # noqa: E402
from src.transforms.ledger_controls import (  # noqa: E402
    build_admin_tx_search,
    build_ops_ledger_pairing_quality_daily,
    build_ops_payment_failure_daily,
    build_ops_payment_refund_daily,
    build_recon_snapshot_flow,
    build_supply_balance_daily,
)

RUN_ID = "run-pipeline-b-spark-parity"
TARGET_DATES = [date(2026, 2, 1), date(2026, 2, 2)]
LOCAL_TZ = datetime.now().astimezone().tzinfo


@pytest.fixture(scope="module")
def spark():
    session = (
        SparkSession.builder.master("local[1]")
        .appName("pipeline-b-spark-parity")
        .config("spark.sql.session.timeZone", "UTC")
        .getOrCreate()
    )
    session.conf.set("spark.sql.session.timeZone", "UTC")
    yield session
    session.stop()


def _scenario():
    wallet_snapshots = [
        {
            "snapshot_ts": datetime(2026, 2, 1, 0, 0, tzinfo=UTC),
            "snapshot_date_kst": date(2026, 2, 1),
            "user_id": "u1",
            "balance_total": "100.00",
        },
        {
            "snapshot_ts": datetime(2026, 2, 1, 12, 0, tzinfo=UTC),
            "snapshot_date_kst": date(2026, 2, 1),
            "user_id": "u1",
            "balance_total": "150.00",
        },
        {
            "snapshot_ts": datetime(2026, 2, 1, 0, 30, tzinfo=UTC),
            "snapshot_date_kst": date(2026, 2, 1),
            "user_id": "u2",
            "balance_total": "200.00",
        },
        {
            "snapshot_ts": datetime(2026, 2, 1, 12, 30, tzinfo=UTC),
            "snapshot_date_kst": date(2026, 2, 1),
            "user_id": "u2",
            "balance_total": "220.00",
        },
        {
            "snapshot_ts": datetime(2026, 2, 2, 0, 0, tzinfo=UTC),
            "snapshot_date_kst": date(2026, 2, 2),
            "user_id": "u1",
            "balance_total": "150.00",
        },
        {
            "snapshot_ts": datetime(2026, 2, 2, 12, 0, tzinfo=UTC),
            "snapshot_date_kst": date(2026, 2, 2),
            "user_id": "u1",
            "balance_total": "160.00",
        },
        {
            "snapshot_ts": datetime(2026, 2, 2, 0, 30, tzinfo=UTC),
            "snapshot_date_kst": date(2026, 2, 2),
            "user_id": "u2",
            "balance_total": "220.00",
        },
        {
            "snapshot_ts": datetime(2026, 2, 2, 12, 30, tzinfo=UTC),
            "snapshot_date_kst": date(2026, 2, 2),
            "user_id": "u2",
            "balance_total": "210.00",
        },
    ]

    ledger_entries = [
        {
            "tx_id": "tx_u1_d1",
            "wallet_id": "u1",
            "entry_type": "PAYMENT",
            "amount": "40.00",
            "amount_signed": "40.00",
            "related_id": "po_1",
            "related_type": "ORDER",
            "status": "PAID",
            "event_time": datetime(2026, 2, 1, 1, 0, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 1),
        },
        {
            "tx_id": "tx_u2_d1",
            "wallet_id": "u2",
            "entry_type": "RECEIVE",
            "amount": "10.00",
            "amount_signed": "10.00",
            "related_id": "po_1",
            "related_type": "ORDER",
            "status": "PAID",
            "event_time": datetime(2026, 2, 1, 2, 0, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 1),
        },
        {
            "tx_id": "tx_mint_d1",
            "wallet_id": "treasury",
            "entry_type": "MINT",
            "amount": "300.00",
            "amount_signed": "300.00",
            "related_id": None,
            "related_type": None,
            "status": None,
            "event_time": datetime(2026, 2, 1, 0, 10, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 1),
        },
        {
            "tx_id": "tx_burn_d1",
            "wallet_id": "treasury",
            "entry_type": "BURN",
            "amount": "10.00",
            "amount_signed": "-10.00",
            "related_id": None,
            "related_type": None,
            "status": None,
            "event_time": datetime(2026, 2, 1, 0, 20, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 1),
        },
        {
            "tx_id": "tx_u1_d2",
            "wallet_id": "u1",
            "entry_type": "PAYMENT",
            "amount": "20.00",
            "amount_signed": "20.00",
            "related_id": "po_2",
            "related_type": "ORDER",
            "status": "FAILED",
            "event_time": datetime(2026, 2, 2, 1, 0, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 2),
        },
        {
            "tx_id": "tx_u2_d2",
            "wallet_id": "u2",
            "entry_type": "PAYMENT",
            "amount": "5.00",
            "amount_signed": "-5.00",
            "related_id": "po_2",
            "related_type": "ORDER",
            "status": "PAID",
            "event_time": datetime(2026, 2, 2, 1, 30, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 2),
        },
        {
            "tx_id": "tx_pair_left",
            "wallet_id": "u1",
            "entry_type": "PAYMENT",
            "amount": "15.00",
            "amount_signed": "-15.00",
            "related_id": "po_pair",
            "related_type": "ORDER",
            "status": "PAID",
            "event_time": datetime(2026, 2, 2, 2, 0, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 2),
        },
        {
            "tx_id": "tx_pair_right",
            "wallet_id": "u2",
            "entry_type": "RECEIVE",
            "amount": "15.00",
            "amount_signed": "15.00",
            "related_id": "po_pair",
            "related_type": "ORDER",
            "status": "PAID",
            "event_time": datetime(2026, 2, 2, 2, 0, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 2),
        },
        {
            "tx_id": "tx_charge_d2",
            "wallet_id": "treasury",
            "entry_type": "CHARGE",
            "amount": "50.00",
            "amount_signed": "50.00",
            "related_id": None,
            "related_type": None,
            "status": None,
            "event_time": datetime(2026, 2, 2, 0, 5, tzinfo=UTC),
            "event_date_kst": date(2026, 2, 2),
        },
    ]

    payment_orders = [
        {
            "order_id": "po_1",
            "merchant_name": "Shop A",
            "status": "FAILED",
            "created_at": datetime(2026, 2, 1, 4, 0, tzinfo=UTC),
        },
        {
            "order_id": "po_2",
            "merchant_name": "Shop A",
            "status": "PAID",
            "created_at": datetime(2026, 2, 2, 4, 0, tzinfo=UTC),
        },
        {
            "order_id": "po_3",
            "merchant_name": "Shop B",
            "status": "REFUNDED",
            "created_at": datetime(2026, 2, 2, 5, 0, tzinfo=UTC),
        },
        {
            "order_id": None,
            "merchant_name": None,
            "status": "CANCELLED",
            "created_at": datetime(2026, 2, 1, 6, 0, tzinfo=UTC),
        },
    ]

    dq_status = [
        {
            "date_kst": date(2026, 2, 1),
            "dq_tag": "EVENT_DROP_SUSPECTED",
        },
        {
            "date_kst": date(2026, 2, 1),
            "dq_tag": "SOURCE_STALE",
        },
        {
            "date_kst": date(2026, 2, 2),
            "dq_tag": "EVENT_DROP_SUSPECTED",
        },
    ]

    return wallet_snapshots, ledger_entries, payment_orders, dq_status


def _canonical_value(value):
    if isinstance(value, datetime):
        normalized = (
            value if value.tzinfo is not None else value.replace(tzinfo=LOCAL_TZ or UTC)
        )
        return to_utc(normalized).isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return value
    return value


def _sort_key(row: dict, keys: tuple[str, ...]) -> tuple[str, ...]:
    return tuple("" if row.get(key) is None else str(row.get(key)) for key in keys)


def _canonical_rows(rows: list[dict], *, sort_keys: tuple[str, ...]) -> list[dict]:
    normalized = [
        {column: _canonical_value(value) for column, value in row.items()}
        for row in rows
    ]
    return sorted(normalized, key=lambda row: _sort_key(row, sort_keys))


def _run_legacy(
    *,
    wallet_snapshots: list[dict],
    ledger_entries: list[dict],
    payment_orders: list[dict],
    dq_status: list[dict],
):
    rules = load_default_rule_seed()
    dq_tags_by_date: dict[date, list[str]] = {}
    for row in dq_status:
        if row.get("date_kst") and row.get("dq_tag"):
            dq_tags_by_date.setdefault(row["date_kst"], []).append(str(row["dq_tag"]))

    recon_rows: list[dict] = []
    supply_rows: list[dict] = []
    ops_failure_rows: list[dict] = []
    ops_refund_rows: list[dict] = []
    pairing_rows: list[dict] = []
    admin_rows: list[dict] = []
    exception_rows: list[dict] = []

    for target_date in TARGET_DATES:
        dq_tags = dq_tags_by_date.get(target_date)
        recon_output = build_recon_snapshot_flow(
            wallet_snapshots,
            ledger_entries,
            target_date=target_date,
            run_id=RUN_ID,
            rules=rules,
            dq_tags=dq_tags,
        )
        recon_rows.extend(recon_output.rows)
        exception_rows.extend(recon_output.exceptions)

        supply_output = build_supply_balance_daily(
            wallet_snapshots,
            ledger_entries,
            target_date=target_date,
            run_id=RUN_ID,
            rules=rules,
            dq_tags=dq_tags,
        )
        supply_rows.append(supply_output.row)
        exception_rows.extend(supply_output.exceptions)

        ops_failure_rows.extend(
            build_ops_payment_failure_daily(
                payment_orders,
                target_date=target_date,
                run_id=RUN_ID,
            )
        )
        ops_refund_rows.extend(
            build_ops_payment_refund_daily(
                payment_orders,
                target_date=target_date,
                run_id=RUN_ID,
            )
        )
        pairing_rows.append(
            build_ops_ledger_pairing_quality_daily(
                ledger_entries,
                target_date=target_date,
                run_id=RUN_ID,
                payment_orders=payment_orders,
            )
        )
        admin_rows.extend(
            build_admin_tx_search(
                ledger_entries,
                target_date=target_date,
                run_id=RUN_ID,
            )
        )

    return {
        "recon_rows": recon_rows,
        "supply_rows": supply_rows,
        "ops_failure_rows": ops_failure_rows,
        "ops_refund_rows": ops_refund_rows,
        "pairing_rows": pairing_rows,
        "admin_rows": admin_rows,
        "exception_rows": exception_rows,
        "rules": rules,
    }


def test_pipeline_b_spark_parity_two_day_mixed(spark) -> None:
    wallet_snapshots, ledger_entries, payment_orders, dq_status = _scenario()

    legacy = _run_legacy(
        wallet_snapshots=wallet_snapshots,
        ledger_entries=ledger_entries,
        payment_orders=payment_orders,
        dq_status=dq_status,
    )
    spark_output = transform_pipeline_b_tables_spark(
        wallet_snapshot_df=spark.createDataFrame(wallet_snapshots),
        ledger_entries_df=spark.createDataFrame(ledger_entries),
        payment_orders_df=spark.createDataFrame(payment_orders),
        dq_status_df=spark.createDataFrame(dq_status),
        target_dates=TARGET_DATES,
        run_id=RUN_ID,
        rules=legacy["rules"],
        run_recon=True,
        run_supply_ops=True,
    )

    assert spark_output.recon_df is not None
    assert spark_output.supply_df is not None
    assert spark_output.ops_failure_df is not None
    assert spark_output.ops_refund_df is not None
    assert spark_output.pairing_quality_df is not None
    assert spark_output.admin_tx_search_df is not None
    assert spark_output.exception_df is not None

    assert _canonical_rows(
        [row.asDict(recursive=True) for row in spark_output.recon_df.collect()],
        sort_keys=("date_kst", "user_id"),
    ) == _canonical_rows(
        legacy["recon_rows"],
        sort_keys=("date_kst", "user_id"),
    )
    assert _canonical_rows(
        [row.asDict(recursive=True) for row in spark_output.supply_df.collect()],
        sort_keys=("date_kst",),
    ) == _canonical_rows(
        legacy["supply_rows"],
        sort_keys=("date_kst",),
    )
    assert _canonical_rows(
        [row.asDict(recursive=True) for row in spark_output.ops_failure_df.collect()],
        sort_keys=("date_kst", "merchant_name"),
    ) == _canonical_rows(
        legacy["ops_failure_rows"],
        sort_keys=("date_kst", "merchant_name"),
    )
    assert _canonical_rows(
        [row.asDict(recursive=True) for row in spark_output.ops_refund_df.collect()],
        sort_keys=("date_kst", "merchant_name"),
    ) == _canonical_rows(
        legacy["ops_refund_rows"],
        sort_keys=("date_kst", "merchant_name"),
    )
    assert _canonical_rows(
        [
            row.asDict(recursive=True)
            for row in spark_output.pairing_quality_df.collect()
        ],
        sort_keys=("date_kst",),
    ) == _canonical_rows(
        legacy["pairing_rows"],
        sort_keys=("date_kst",),
    )
    assert _canonical_rows(
        [
            row.asDict(recursive=True)
            for row in spark_output.admin_tx_search_df.collect()
        ],
        sort_keys=("event_date_kst", "tx_id"),
    ) == _canonical_rows(
        legacy["admin_rows"],
        sort_keys=("event_date_kst", "tx_id"),
    )

    spark_exceptions = []
    for row in spark_output.exception_df.collect():
        payload = row.asDict(recursive=True)
        payload.pop("generated_at", None)
        spark_exceptions.append(payload)
    legacy_exceptions = []
    for row in legacy["exception_rows"]:
        payload = dict(row)
        payload.pop("generated_at", None)
        legacy_exceptions.append(payload)

    assert _canonical_rows(
        spark_exceptions,
        sort_keys=("date_kst", "exception_type", "metric", "message", "run_id"),
    ) == _canonical_rows(
        legacy_exceptions,
        sort_keys=("date_kst", "exception_type", "metric", "message", "run_id"),
    )

    merge_key_set = {
        (
            row["date_kst"],
            row["domain"],
            row["exception_type"],
            row["run_id"],
            row["metric"],
            row["message"],
        )
        for row in spark_exceptions
    }
    assert len(merge_key_set) == len(spark_exceptions)
