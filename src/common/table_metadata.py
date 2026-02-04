from __future__ import annotations

SILVER_MERGE_KEYS: dict[str, tuple[str, ...]] = {
    "silver.wallet_snapshot": ("snapshot_ts", "user_id"),
    "silver.ledger_entries": ("tx_id", "wallet_id"),
}

SILVER_PARTITION_COLUMNS: dict[str, tuple[str, ...]] = {
    "silver.wallet_snapshot": ("snapshot_date_kst",),
    "silver.ledger_entries": ("event_date_kst",),
}
