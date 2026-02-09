from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from src.common.time_utils import UTC
from src.io.rule_loader import load_default_rule_seed
from src.transforms.analytics import build_fact_payment_anonymized
from src.transforms.ledger_controls import (
    build_recon_snapshot_flow,
    build_supply_balance_daily,
)


def _merge_rows(rows, new_rows, keys):
    index = {tuple(row[key] for key in keys): row for row in rows}
    for row in new_rows:
        index[tuple(row[key] for key in keys)] = row
    return list(index.values())


def _normalize_run_id(rows, run_id: str = "run"):
    normalized = []
    for row in rows:
        payload = dict(row)
        payload["run_id"] = run_id
        normalized.append(payload)
    return normalized


def _sorted(rows, keys):
    return sorted(rows, key=lambda row: tuple(row[key] for key in keys))


def test_pipeline_b_two_day_backfill_idempotency() -> None:
    wallet_snapshots = [
        {
            "snapshot_ts": datetime(2026, 2, 1, 0, 0, tzinfo=UTC),
            "user_id": "u1",
            "balance_total": Decimal("100"),
        },
        {
            "snapshot_ts": datetime(2026, 2, 1, 12, 0, tzinfo=UTC),
            "user_id": "u1",
            "balance_total": Decimal("120"),
        },
        {
            "snapshot_ts": datetime(2026, 2, 2, 0, 0, tzinfo=UTC),
            "user_id": "u1",
            "balance_total": Decimal("120"),
        },
        {
            "snapshot_ts": datetime(2026, 2, 2, 12, 0, tzinfo=UTC),
            "user_id": "u1",
            "balance_total": Decimal("140"),
        },
    ]
    ledger_entries = [
        {
            "wallet_id": "u1",
            "amount_signed": Decimal("20"),
            "entry_type": "MINT",
            "amount": Decimal("20"),
            "event_time": datetime(2026, 2, 1, 2, 0, tzinfo=UTC),
        },
        {
            "wallet_id": "u1",
            "amount_signed": Decimal("20"),
            "entry_type": "MINT",
            "amount": Decimal("20"),
            "event_time": datetime(2026, 2, 2, 2, 0, tzinfo=UTC),
        },
    ]
    rules = load_default_rule_seed()
    target_dates = [date(2026, 2, 1), date(2026, 2, 2)]

    recon_run1 = []
    recon_run2 = []
    supply_run1 = []
    supply_run2 = []

    for target_date in target_dates:
        recon_output_1 = build_recon_snapshot_flow(
            wallet_snapshots,
            ledger_entries,
            target_date=target_date,
            run_id="run-backfill-1",
            rules=rules,
        )
        recon_output_2 = build_recon_snapshot_flow(
            wallet_snapshots,
            ledger_entries,
            target_date=target_date,
            run_id="run-backfill-2",
            rules=rules,
        )
        recon_run1 = _merge_rows(
            recon_run1, recon_output_1.rows, ("date_kst", "user_id")
        )
        recon_run2 = _merge_rows(
            recon_run2, recon_output_2.rows, ("date_kst", "user_id")
        )

        supply_output_1 = build_supply_balance_daily(
            wallet_snapshots,
            ledger_entries,
            target_date=target_date,
            run_id="run-backfill-1",
            rules=rules,
        )
        supply_output_2 = build_supply_balance_daily(
            wallet_snapshots,
            ledger_entries,
            target_date=target_date,
            run_id="run-backfill-2",
            rules=rules,
        )
        supply_run1 = _merge_rows(supply_run1, [supply_output_1.row], ("date_kst",))
        supply_run2 = _merge_rows(supply_run2, [supply_output_2.row], ("date_kst",))

    assert _sorted(_normalize_run_id(recon_run1), ("date_kst", "user_id")) == _sorted(
        _normalize_run_id(recon_run2), ("date_kst", "user_id")
    )
    assert _sorted(_normalize_run_id(supply_run1), ("date_kst",)) == _sorted(
        _normalize_run_id(supply_run2), ("date_kst",)
    )


def test_pipeline_c_backfill_partition_result_converges() -> None:
    order_events = [
        {
            "order_ref": "o1",
            "order_source": "PAYMENT_ORDERS",
            "user_id": "u1",
            "merchant_name": "M1",
            "amount": "100.00",
            "status": "PAID",
            "event_date_kst": date(2026, 2, 1),
        },
        {
            "order_ref": "o2",
            "order_source": "PAYMENT_ORDERS",
            "user_id": "u1",
            "merchant_name": "M1",
            "amount": "200.00",
            "status": "PAID",
            "event_date_kst": date(2026, 2, 2),
        },
    ]
    order_items = [
        {
            "item_id": 1,
            "order_ref": "o1",
            "product_id": 10,
            "quantity": 1,
            "price_at_purchase": "100.00",
        },
        {
            "item_id": 2,
            "order_ref": "o2",
            "product_id": 20,
            "quantity": 1,
            "price_at_purchase": "200.00",
        },
    ]
    products = [
        {"product_id": 10, "category": "A"},
        {"product_id": 20, "category": "B"},
    ]

    rows_run1 = build_fact_payment_anonymized(
        order_events,
        order_items,
        products,
        run_id="run-c-1",
        salt="salt",
    )
    rows_run2 = build_fact_payment_anonymized(
        order_events,
        order_items,
        products,
        run_id="run-c-2",
        salt="salt",
    )

    assert _sorted(
        _normalize_run_id(rows_run1),
        ("date_kst", "user_key", "merchant_name", "amount", "status", "category"),
    ) == _sorted(
        _normalize_run_id(rows_run2),
        ("date_kst", "user_key", "merchant_name", "amount", "status", "category"),
    )
