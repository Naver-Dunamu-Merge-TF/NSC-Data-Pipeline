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
    assert "--pipelines" in content
    assert "--fail-fast-deterministic" in content
    assert 'FAIL_FAST_DETERMINISTIC="off"' in content
    assert "--output-json" in content
    assert "databricks jobs list-runs" in content
    assert "databricks jobs get-run" in content
    assert "databricks jobs get-run-output" in content
    assert "databricks jobs cancel-run" in content
    assert "pipeline_a_guardrail" in content
    assert "pipeline_silver_materialization" in content
    assert "pipeline_b_controls" in content
    assert "pipeline_c_analytics" in content


def test_sec005_verifier_acl_script_has_expected_contract() -> None:
    content = _read("scripts/phase7/sec005_apply_verifier_acl.sh")
    assert "--target <dev|prod-secure>" in content
    assert "--catalog <catalog-name>" in content
    assert "--principal <principal>" in content
    assert "--dry-run" in content
    assert "--apply" in content
    assert "20260223_sec005_verifier_acl_assertions.json" in content
    assert "USE_CATALOG" in content
    assert "USE_SCHEMA SELECT MODIFY" in content


def test_runtime_serverless_assertion_script_checks_core_four_jobs() -> None:
    content = _read("scripts/phase7/verify_all_pipeline_serverless_runtime.sh")
    assert "--target <dev|prod-secure>" in content
    assert "--output-json <path>" in content
    assert "performance_target_present" in content
    assert "has_job_clusters" in content
    assert "has_task_job_cluster_key" in content
    assert "run_as_present" in content
    assert "pipeline_a_guardrail" in content
    assert "pipeline_silver_materialization" in content
    assert "pipeline_b_controls" in content
    assert "pipeline_c_analytics" in content


def test_schedule_toggle_script_manages_pause_and_resume() -> None:
    content = _read("scripts/phase7/toggle_core_pipeline_schedules.sh")
    assert "--pause" in content
    assert "--resume" in content
    assert "20260223_all_pipeline_serverless_schedule_states.json" in content
    assert "databricks jobs reset" in content


def test_pipeline_a_serverless_cadence_script_has_threshold_inputs() -> None:
    content = _read("scripts/phase7/verify_pipeline_a_serverless_cadence.sh")
    assert "--window-hours" in content
    assert "--min-samples" in content
    assert "--max-total-seconds" in content
    assert "--max-queue-seconds" in content
    assert "--output-json" in content
    assert "20260223_pipeline_a_serverless_cadence.json" in content


def test_sec005_rule_preflight_script_validates_acl_and_rule_integrity() -> None:
    content = _read("scripts/phase7/verify_sec005_rule_preflight.sh")
    assert "--target <dev|prod-secure>" in content
    assert "--catalog <catalog-name>" in content
    assert "--run-as-principal <sp-app-id>" in content
    assert "--output-json <path>" in content
    assert "USE_CATALOG" in content
    assert "USE_SCHEMA" in content
    assert "SELECT" in content
    assert "MODIFY" in content
    assert "gold.dim_rule_scd2" in content
    assert "gold.pipeline_state" in content
    assert "rule_table_exists" in content
    assert "rule_current_uniqueness_ok" in content
    assert "pipeline_state_exists" in content
    assert "sp_acl_ok" in content


def test_sec005_smoke_recovery_runner_has_staged_execution_contract() -> None:
    content = _read("scripts/phase7/run_sec005_smoke_recovery.sh")
    assert "--target <dev|prod-secure>" in content
    assert "--date-kst <YYYY-MM-DD>" in content
    assert "--run-id <logical-run-id>" in content
    assert "--run-as-principal <sp-app-id>" in content
    assert "toggle_core_pipeline_schedules.sh" in content
    assert "--pause" in content
    assert "--resume" in content
    assert "verify_sec005_rule_preflight.sh" in content
    assert "databricks bundle run sync_dim_rule_scd2" in content
    assert "pipeline_a_guardrail" in content
    assert "pipeline_silver_materialization" in content
    assert "pipeline_b_controls" in content
    assert "pipeline_c_analytics" in content
    assert "--pipelines pipeline_a_guardrail,pipeline_silver_materialization" in content
    assert "--pipelines pipeline_b_controls,pipeline_c_analytics" in content
    assert "--fail-fast-deterministic on" in content
