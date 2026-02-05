from __future__ import annotations

import pytest

from src.io.silver_io import (
    build_silver_write_config,
    normalize_table_name,
    silver_merge_keys,
    silver_partition_columns,
)


def test_normalize_table_name_accepts_short_name() -> None:
    assert normalize_table_name("wallet_snapshot") == "silver.wallet_snapshot"


def test_silver_partition_columns() -> None:
    assert silver_partition_columns("silver.wallet_snapshot") == (
        "snapshot_date_kst",
    )
    assert silver_partition_columns("ledger_entries") == ("event_date_kst",)


def test_silver_merge_keys() -> None:
    assert silver_merge_keys("wallet_snapshot") == ("snapshot_ts", "user_id")
    assert silver_merge_keys("silver.ledger_entries") == ("tx_id", "wallet_id")


def test_silver_write_config() -> None:
    config = build_silver_write_config("silver.wallet_snapshot")
    assert config.partition_columns == ("snapshot_date_kst",)
    assert config.merge_keys == ("snapshot_ts", "user_id")


def test_silver_partition_columns_unknown_table() -> None:
    with pytest.raises(KeyError):
        silver_partition_columns("silver.unknown_table")
