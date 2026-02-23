from __future__ import annotations

from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def _load_bundle() -> dict:
    return yaml.safe_load((REPO_ROOT / "databricks.yml").read_text(encoding="utf-8"))


def test_bundle_declares_run_as_variable_and_targets() -> None:
    bundle = _load_bundle()
    variables = bundle["variables"]
    assert "run_as_principal" in variables
    assert "description" in variables["run_as_principal"]

    dev_vars = bundle["targets"]["dev"]["variables"]
    prod_vars = bundle["targets"]["prod"]["variables"]
    assert "run_as_principal" in dev_vars
    assert "run_as_principal" in prod_vars


def test_bundle_pipeline_jobs_use_run_as_service_principal() -> None:
    bundle = _load_bundle()
    jobs = bundle["resources"]["jobs"]
    for job_key in [
        "pipeline_a_guardrail",
        "pipeline_silver_materialization",
        "pipeline_b_controls",
        "pipeline_c_analytics",
    ]:
        run_as = jobs[job_key]["run_as"]
        assert run_as == {"service_principal_name": "${var.run_as_principal}"}


def test_sec005_run_as_acl_script_has_apply_and_assertion_flow() -> None:
    content = _read("scripts/phase7/sec005_run_as_acl_apply.sh")
    assert "--target <dev|prod-secure>" in content
    assert "--dry-run" in content
    assert "--apply" in content
    assert "20260223_sec005_acl_assertions.json" in content
    assert "databricks jobs reset" in content
    assert "databricks grants update" in content
    assert "run_as_ok" in content
    assert "use_catalog_ok" in content
    assert "use_schema_ok" in content
    assert "select_ok" in content
    assert "modify_ok" in content


def test_sec005_smoke_l3_script_has_polling_and_timeout_controls() -> None:
    content = _read("scripts/phase7/verify_sec005_smoke_l3.sh")
    assert "POLL_SECONDS_DEFAULT=20" in content
    assert "TIMEOUT_SECONDS_DEFAULT=600" in content
    assert "--poll-seconds" in content
    assert "--timeout-seconds" in content
    assert "databricks jobs list-runs" in content
    assert "databricks jobs get-run" in content
    assert "pipeline_a_guardrail" in content
    assert "pipeline_silver_materialization" in content
    assert "pipeline_b_controls" in content
    assert "pipeline_c_analytics" in content
