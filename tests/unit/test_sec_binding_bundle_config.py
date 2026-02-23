from __future__ import annotations

from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_bundle() -> dict:
    return yaml.safe_load((REPO_ROOT / "databricks.yml").read_text(encoding="utf-8"))


def test_sec_binding_job_exists_and_uses_serverless_environment() -> None:
    bundle = _load_bundle()
    job = bundle["resources"]["jobs"]["sec_access_secret_binding_window"]

    assert job["performance_target"] == "STANDARD"
    assert "job_clusters" not in job
    assert job["timeout_seconds"] == 1200

    environments = job["environments"]
    assert len(environments) == 1
    assert environments[0]["environment_key"] == "sec_binding_default"


def test_sec_binding_job_parameters_and_tasks_are_wired() -> None:
    bundle = _load_bundle()
    job = bundle["resources"]["jobs"]["sec_access_secret_binding_window"]

    param_names = [param["name"] for param in job["parameters"]]
    assert param_names == [
        "run_id",
        "catalog",
        "external_location",
        "base_path",
        "secret_scope",
        "secret_key",
    ]

    tasks = {task["task_key"]: task for task in job["tasks"]}
    assert set(tasks.keys()) == {"sec003_probe", "sec004_probe"}

    sec003 = tasks["sec003_probe"]
    assert sec003["environment_key"] == "sec_binding_default"
    assert (
        sec003["spark_python_task"]["python_file"]
        == "scripts/phase7/sec003_uc_external_location_probe.py"
    )

    sec004 = tasks["sec004_probe"]
    assert sec004["environment_key"] == "sec_binding_default"
    assert (
        sec004["spark_python_task"]["python_file"]
        == "scripts/phase7/sec004_secret_scope_probe.py"
    )
    assert sec004["depends_on"] == [{"task_key": "sec003_probe"}]
