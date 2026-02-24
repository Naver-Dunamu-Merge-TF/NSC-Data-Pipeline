from __future__ import annotations

from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_bundle() -> dict:
    return yaml.safe_load((REPO_ROOT / "databricks.yml").read_text(encoding="utf-8"))


def _parameter_names(job: dict) -> list[str]:
    return [param["name"] for param in job["parameters"]]


def _parameter_defaults(job: dict) -> dict[str, str]:
    return {param["name"]: str(param.get("default", "")) for param in job["parameters"]}


TARGET_JOB_EXPECTATIONS = {
    "pipeline_a_guardrail": {
        "schedule": "0 0/10 * * * ?",
        "environment_key": "pipeline_a_serverless",
        "parameter_names": [
            "run_mode",
            "start_ts",
            "end_ts",
            "date_kst_start",
            "date_kst_end",
            "run_id",
            "rule_load_mode",
            "rule_table",
            "rule_seed_path",
        ],
        "task_keys": ["run_pipeline_a"],
    },
    "pipeline_silver_materialization": {
        "schedule": "0 0 0 * * ?",
        "environment_key": "pipeline_silver_serverless",
        "parameter_names": [
            "run_mode",
            "start_ts",
            "end_ts",
            "date_kst_start",
            "date_kst_end",
            "run_id",
            "rule_load_mode",
            "rule_table",
            "rule_seed_path",
        ],
        "task_keys": ["run_pipeline_silver"],
    },
    "pipeline_b_controls": {
        "schedule": "0 20 0 * * ?",
        "environment_key": "pipeline_b_serverless",
        "parameter_names": [
            "run_mode",
            "start_ts",
            "end_ts",
            "date_kst_start",
            "date_kst_end",
            "run_id",
            "rule_load_mode",
            "rule_table",
            "rule_seed_path",
        ],
        "task_keys": [
            "pipeline_b_recon",
            "pipeline_b_supply_ops",
            "pipeline_b_finalize_success",
            "pipeline_b_finalize_failure",
        ],
    },
    "pipeline_c_analytics": {
        "schedule": "0 35 0 * * ?",
        "environment_key": "pipeline_c_serverless",
        "parameter_names": [
            "run_mode",
            "start_ts",
            "end_ts",
            "date_kst_start",
            "date_kst_end",
            "run_id",
        ],
        "task_keys": ["run_pipeline_c"],
    },
}


def test_target_pipeline_jobs_use_serverless_compute_contract() -> None:
    bundle = _load_bundle()
    jobs = bundle["resources"]["jobs"]

    for job_key, expected in TARGET_JOB_EXPECTATIONS.items():
        job = jobs[job_key]

        assert job["performance_target"] == "STANDARD"
        assert "job_clusters" not in job

        environments = job["environments"]
        assert len(environments) == 1
        assert environments[0]["environment_key"] == expected["environment_key"]
        assert environments[0]["spec"]["environment_version"] == "2"

        tasks = job["tasks"]
        assert [task["task_key"] for task in tasks] == expected["task_keys"]
        for task in tasks:
            assert "job_cluster_key" not in task
            assert task["environment_key"] == expected["environment_key"]


def test_target_pipeline_jobs_preserve_run_context_and_task_controls() -> None:
    bundle = _load_bundle()
    jobs = bundle["resources"]["jobs"]

    for job_key, expected in TARGET_JOB_EXPECTATIONS.items():
        job = jobs[job_key]

        assert job["run_as"] == {"service_principal_name": "${var.run_as_principal}"}
        assert job["timeout_seconds"] == 3600
        assert job["schedule"]["quartz_cron_expression"] == expected["schedule"]
        assert job["schedule"]["timezone_id"] == "Asia/Seoul"
        assert _parameter_names(job) == expected["parameter_names"]

        defaults = _parameter_defaults(job)
        if "rule_load_mode" in defaults:
            assert defaults["rule_load_mode"] == "${var.rule_load_mode}"
            assert defaults["rule_table"] == "${var.rule_table}"
            assert defaults["rule_seed_path"] == "${var.rule_seed_path}"

        for task in job["tasks"]:
            assert task["retry_on_timeout"] is True
            assert task["max_retries"] == 2
            assert task["min_retry_interval_millis"] == 300000

        if job_key == "pipeline_b_controls":
            tasks = {task["task_key"]: task for task in job["tasks"]}
            assert tasks["pipeline_b_finalize_success"]["depends_on"] == [
                {"task_key": "pipeline_b_recon"},
                {"task_key": "pipeline_b_supply_ops"},
            ]
            assert tasks["pipeline_b_finalize_failure"]["depends_on"] == [
                {"task_key": "pipeline_b_recon"},
                {"task_key": "pipeline_b_supply_ops"},
            ]
            assert (
                tasks["pipeline_b_finalize_failure"]["run_if"] == "AT_LEAST_ONE_FAILED"
            )


def test_all_bundle_jobs_use_serverless_compute_contract() -> None:
    bundle = _load_bundle()
    jobs = bundle["resources"]["jobs"]

    for job_key, job in jobs.items():
        assert job["performance_target"] == "STANDARD", job_key
        assert "job_clusters" not in job, job_key
        assert "environments" in job, job_key
        assert len(job["environments"]) == 1, job_key
        assert job["environments"][0]["spec"]["environment_version"] == "2", job_key

        for task in job["tasks"]:
            assert "job_cluster_key" not in task, f"{job_key}:{task['task_key']}"
            assert "environment_key" in task, f"{job_key}:{task['task_key']}"
