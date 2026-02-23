from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_binding_window_script_contains_kv_scope_recreate_flow() -> None:
    content = _read("scripts/phase7/sec003_sec004_binding_window.sh")
    assert 'scope_backend_type: "AZURE_KEYVAULT"' in content
    assert "databricks secrets delete-scope" in content
    assert "databricks grants update" in content


def test_l3_verify_script_has_fixed_polling_and_timeout() -> None:
    content = _read("scripts/phase7/verify_sec003_sec004_l3.sh")
    assert "POLL_SECONDS=20" in content
    assert "TIMEOUT_SECONDS=600" in content
    assert "RETRY_MAX=" in content
    assert "run_with_retry" in content
    assert "record_escalation" in content
    assert "databricks jobs get-run" in content
