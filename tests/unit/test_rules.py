from __future__ import annotations

from datetime import datetime
from pathlib import Path

import pytest

from src.common.rules import DEFAULT_EFFECTIVE_START, RuleDefinition
from src.io.rule_loader import load_rule_seed


def test_rule_from_dict_defaults() -> None:
    payload = {
        "rule_id": "rule_test",
        "domain": "dq",
        "metric": "freshness_sec",
        "threshold": 300,
    }
    rule = RuleDefinition.from_dict(payload)
    assert rule.rule_id == "rule_test"
    assert rule.domain == "dq"
    assert rule.metric == "freshness_sec"
    assert rule.effective_start_ts == DEFAULT_EFFECTIVE_START
    assert rule.is_current is True


def test_rule_from_dict_parses_iso_timestamp() -> None:
    payload = {
        "rule_id": "rule_time",
        "effective_start_ts": "2026-02-04T00:00:00Z",
    }
    rule = RuleDefinition.from_dict(payload)
    assert isinstance(rule.effective_start_ts, datetime)
    assert rule.effective_start_ts.tzinfo is not None


def test_rule_from_dict_requires_rule_id() -> None:
    with pytest.raises(ValueError):
        RuleDefinition.from_dict({})


def test_load_rule_seed() -> None:
    seed_path = Path("mock_data/fixtures/dim_rule_scd2.json")
    rules = load_rule_seed(seed_path)
    rule_ids = {rule.rule_id for rule in rules}
    assert "dq_freshness_default" in rule_ids
    assert "silver_bad_records_default" in rule_ids
