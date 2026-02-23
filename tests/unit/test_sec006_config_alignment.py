from __future__ import annotations

from pathlib import Path

import pytest
import yaml

import scripts.phase7.verify_sec006_config_alignment as sec006


def _write_yaml(path: Path, payload: dict) -> None:
    path.write_text(yaml.safe_dump(payload, sort_keys=False), encoding="utf-8")


def _write_expected(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def test_parse_expected_env_supports_comments_and_blank_lines(tmp_path: Path) -> None:
    expected_path = tmp_path / "expected.env"
    _write_expected(
        expected_path,
        [
            "# baseline",
            "workspace_host=https://example",
            "",
            "workspace_id=1234",
            "catalog=my_cat",
        ],
    )

    parsed = sec006.parse_expected_env(expected_path)

    assert parsed == {
        "workspace_host": "https://example",
        "workspace_id": "1234",
        "catalog": "my_cat",
    }


def test_compare_returns_zero_mismatches_when_aligned(tmp_path: Path) -> None:
    dev_path = tmp_path / "dev.yaml"
    common_path = tmp_path / "common.yaml"
    expected_path = tmp_path / "expected.env"

    _write_yaml(
        dev_path,
        {
            "databricks": {
                "workspace_host": "https://example",
                "workspace_id": "1234",
                "catalog": "my_cat",
            },
            "storage": {
                "external_location": "ext_loc",
                "base_path": "abfss://container@acct.dfs.core.windows.net",
            },
            "analytics": {"secret_scope": "ledger-analytics-dev"},
        },
    )
    _write_yaml(
        common_path,
        {
            "analytics": {"secret_key": "salt_user_key"},
        },
    )
    _write_expected(
        expected_path,
        [
            "workspace_host=https://example",
            "workspace_id=1234",
            "catalog=my_cat",
            "external_location=ext_loc",
            "base_path=abfss://container@acct.dfs.core.windows.net",
            "secret_scope=ledger-analytics-dev",
            "secret_key=salt_user_key",
        ],
    )

    report = sec006.compare_alignment(
        dev_config_path=dev_path,
        common_config_path=common_path,
        expected_env_path=expected_path,
    )

    assert report.checked_count == 7
    assert report.mismatch_count == 0
    assert report.mismatches == []


def test_compare_detects_mismatch_and_main_returns_non_zero(tmp_path: Path) -> None:
    dev_path = tmp_path / "dev.yaml"
    common_path = tmp_path / "common.yaml"
    expected_path = tmp_path / "expected.env"

    _write_yaml(
        dev_path,
        {
            "databricks": {
                "workspace_host": "https://example",
                "workspace_id": "1234",
                "catalog": "wrong_catalog",
            },
            "storage": {
                "external_location": "ext_loc",
                "base_path": "abfss://container@acct.dfs.core.windows.net",
            },
            "analytics": {"secret_scope": "ledger-analytics-dev"},
        },
    )
    _write_yaml(common_path, {"analytics": {"secret_key": "salt_user_key"}})
    _write_expected(
        expected_path,
        [
            "workspace_host=https://example",
            "workspace_id=1234",
            "catalog=my_cat",
            "external_location=ext_loc",
            "base_path=abfss://container@acct.dfs.core.windows.net",
            "secret_scope=ledger-analytics-dev",
            "secret_key=salt_user_key",
        ],
    )

    exit_code = sec006.main(
        [
            "--config-dev",
            str(dev_path),
            "--config-common",
            str(common_path),
            "--expected",
            str(expected_path),
        ]
    )
    report = sec006.compare_alignment(
        dev_config_path=dev_path,
        common_config_path=common_path,
        expected_env_path=expected_path,
    )

    assert exit_code == 1
    assert report.checked_count == 7
    assert report.mismatch_count == 1
    assert report.mismatches[0]["key"] == "catalog"
    assert report.mismatches[0]["actual"] == "wrong_catalog"
    assert report.mismatches[0]["expected"] == "my_cat"


def test_compare_fails_when_required_expected_key_is_missing(tmp_path: Path) -> None:
    dev_path = tmp_path / "dev.yaml"
    common_path = tmp_path / "common.yaml"
    expected_path = tmp_path / "expected.env"

    _write_yaml(
        dev_path,
        {
            "databricks": {
                "workspace_host": "https://example",
                "workspace_id": "1234",
                "catalog": "my_cat",
            },
            "storage": {
                "external_location": "ext_loc",
                "base_path": "abfss://container@acct.dfs.core.windows.net",
            },
            "analytics": {"secret_scope": "ledger-analytics-dev"},
        },
    )
    _write_yaml(common_path, {"analytics": {"secret_key": "salt_user_key"}})
    _write_expected(
        expected_path,
        [
            "workspace_host=https://example",
            "workspace_id=1234",
            "catalog=my_cat",
        ],
    )

    with pytest.raises(ValueError, match="Missing expected keys"):
        sec006.compare_alignment(
            dev_config_path=dev_path,
            common_config_path=common_path,
            expected_env_path=expected_path,
        )
