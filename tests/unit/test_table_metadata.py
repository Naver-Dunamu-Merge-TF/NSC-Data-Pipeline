from __future__ import annotations

from src.common.table_metadata import SILVER_MERGE_KEYS, SILVER_PARTITION_COLUMNS


def test_silver_merge_keys_contains_expected_tables() -> None:
    assert SILVER_MERGE_KEYS["silver.wallet_snapshot"] == (
        "snapshot_ts",
        "user_id",
    )
    assert SILVER_MERGE_KEYS["silver.ledger_entries"] == ("tx_id", "wallet_id")
    assert SILVER_MERGE_KEYS["silver.order_events"] == (
        "order_ref",
        "order_source",
    )
    assert SILVER_MERGE_KEYS["silver.order_items"] == ("item_id",)
    assert SILVER_MERGE_KEYS["silver.products"] == ("product_id",)


def test_silver_partition_columns() -> None:
    assert SILVER_PARTITION_COLUMNS["silver.wallet_snapshot"] == (
        "snapshot_date_kst",
    )
    assert SILVER_PARTITION_COLUMNS["silver.ledger_entries"] == (
        "event_date_kst",
    )
    assert SILVER_PARTITION_COLUMNS["silver.order_events"] == ("event_date_kst",)
    assert SILVER_PARTITION_COLUMNS["silver.order_items"] == ()
    assert SILVER_PARTITION_COLUMNS["silver.products"] == ()
