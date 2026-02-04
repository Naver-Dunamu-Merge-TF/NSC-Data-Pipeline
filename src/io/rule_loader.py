from __future__ import annotations

import json
from pathlib import Path

from src.common.rules import RuleDefinition


def load_rule_seed(path: str | Path) -> list[RuleDefinition]:
    seed_path = Path(path)
    if not seed_path.exists():
        raise FileNotFoundError(f"Rule seed not found: {seed_path}")

    payload = json.loads(seed_path.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError("Rule seed must be a list of rule definitions")

    return [_parse_rule(item) for item in payload]


def _parse_rule(item: dict) -> RuleDefinition:
    if not isinstance(item, dict):
        raise ValueError("Each rule definition must be a JSON object")
    return RuleDefinition.from_dict(item)


def load_default_rule_seed() -> list[RuleDefinition]:
    default_path = Path("mock_data/fixtures/dim_rule_scd2.json")
    return load_rule_seed(default_path)
