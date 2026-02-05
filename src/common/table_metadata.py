from __future__ import annotations

SILVER_MERGE_KEYS: dict[str, tuple[str, ...]] = {
    "silver.wallet_snapshot": ("snapshot_ts", "user_id"),
    "silver.ledger_entries": ("tx_id", "wallet_id"),
    "silver.order_events": ("order_ref", "order_source"),
    "silver.order_items": ("item_id",),
    "silver.products": ("product_id",),
}

SILVER_PARTITION_COLUMNS: dict[str, tuple[str, ...]] = {
    "silver.wallet_snapshot": ("snapshot_date_kst",),
    "silver.ledger_entries": ("event_date_kst",),
    "silver.order_events": ("event_date_kst",),
    "silver.order_items": (),
    "silver.products": (),
}
