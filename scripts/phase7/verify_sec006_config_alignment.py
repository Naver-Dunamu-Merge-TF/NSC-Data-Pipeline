"""SEC-006 deterministic config alignment checker."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml

_MISSING = "<MISSING>"

EXPECTED_SPECS: dict[str, tuple[str, tuple[str, ...]]] = {
    "workspace_host": ("dev", ("databricks", "workspace_host")),
    "workspace_id": ("dev", ("databricks", "workspace_id")),
    "catalog": ("dev", ("databricks", "catalog")),
    "external_location": ("dev", ("storage", "external_location")),
    "base_path": ("dev", ("storage", "base_path")),
    "secret_scope": ("dev", ("analytics", "secret_scope")),
    "secret_key": ("common", ("analytics", "secret_key")),
}


@dataclass(frozen=True)
class AlignmentReport:
    checked_count: int
    mismatch_count: int
    mismatches: list[dict[str, str]]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify SEC-006 key alignment between config files and expected baseline."
    )
    parser.add_argument("--config-dev", required=True)
    parser.add_argument("--config-common", required=True)
    parser.add_argument("--expected", required=True)
    return parser.parse_args(argv)


def _load_yaml(path: Path) -> dict:
    payload = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(payload, dict):
        raise ValueError(f"YAML root must be a mapping: {path}")
    return payload


def parse_expected_env(path: Path) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Invalid expected env line: {raw_line}")
        key, value = line.split("=", 1)
        key = key.strip()
        if not key:
            raise ValueError(f"Invalid expected key: {raw_line}")
        parsed[key] = value.strip()
    return parsed


def _read_nested(payload: dict, path: tuple[str, ...]) -> str:
    current: object = payload
    for key in path:
        if not isinstance(current, dict) or key not in current:
            return _MISSING
        current = current[key]
    if current is None:
        return "null"
    return str(current)


def compare_alignment(
    *,
    dev_config_path: Path,
    common_config_path: Path,
    expected_env_path: Path,
) -> AlignmentReport:
    dev_cfg = _load_yaml(dev_config_path)
    common_cfg = _load_yaml(common_config_path)
    expected = parse_expected_env(expected_env_path)

    expected_keys = set(expected)
    required_keys = set(EXPECTED_SPECS)
    missing_keys = sorted(required_keys - expected_keys)
    if missing_keys:
        raise ValueError(f"Missing expected keys: {', '.join(missing_keys)}")

    mismatches: list[dict[str, str]] = []
    for key, (source_name, dotted_path) in EXPECTED_SPECS.items():
        source_cfg = dev_cfg if source_name == "dev" else common_cfg
        actual = _read_nested(source_cfg, dotted_path)
        expected_value = expected[key]
        if actual != expected_value:
            mismatches.append(
                {
                    "key": key,
                    "expected": expected_value,
                    "actual": actual,
                    "source": f"{source_name}:{'.'.join(dotted_path)}",
                }
            )

    return AlignmentReport(
        checked_count=len(EXPECTED_SPECS),
        mismatch_count=len(mismatches),
        mismatches=mismatches,
    )


def _print_report(report: AlignmentReport) -> None:
    print("SEC006_CONFIG_ALIGNMENT_REPORT")
    print(f"checked_count={report.checked_count}")
    print(f"mismatch_count={report.mismatch_count}")
    print(f"status={'PASS' if report.mismatch_count == 0 else 'FAIL'}")
    for mismatch in report.mismatches:
        print(
            "mismatch:"
            f" key={mismatch['key']}"
            f" expected={mismatch['expected']}"
            f" actual={mismatch['actual']}"
            f" source={mismatch['source']}"
        )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    report = compare_alignment(
        dev_config_path=Path(args.config_dev),
        common_config_path=Path(args.config_common),
        expected_env_path=Path(args.expected),
    )
    _print_report(report)
    return 0 if report.mismatch_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
