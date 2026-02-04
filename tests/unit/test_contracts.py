from __future__ import annotations

import pytest

from src.common.contracts import (
    ContractValidationError,
    get_contract,
    missing_required_columns,
    validate_required_columns,
)


def test_missing_required_columns() -> None:
    contract = get_contract("silver.wallet_snapshot")
    missing = missing_required_columns(["snapshot_ts", "user_id"], contract)
    assert "balance_total" in missing
    assert "snapshot_date_kst" in missing


def test_validate_required_columns_raises() -> None:
    contract = get_contract("silver.ledger_entries")
    with pytest.raises(ContractValidationError):
        validate_required_columns(["tx_id"], contract)


def test_cast_map_contains_types() -> None:
    contract = get_contract("silver.ledger_entries")
    cast_map = contract.cast_map
    assert cast_map["amount_signed"] == "decimal(38,2)"
    assert cast_map["event_time"] == "timestamp"
