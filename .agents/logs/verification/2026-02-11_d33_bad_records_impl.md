# Verification Evidence - D-033 bad_records persistence

- Date (UTC): 2026-02-11
- Operator: Codex (GPT-5)
- Repo: /home/salee/dev/Data-pipeline
- Scope: D-033 1차 구현 (`silver.bad_records` 영속화 + persist-before-fail-fast)

## L0 - Syntax
- Command:
  - `python -m py_compile src/common/contracts.py src/common/table_metadata.py src/transforms/silver_controls.py src/transforms/analytics.py scripts/e2e/setup_e2e_env.py tests/unit/test_silver_controls.py tests/unit/test_analytics_transforms.py tests/unit/test_contracts.py tests/unit/test_table_metadata.py tests/integration/test_bad_records_persistence_policy.py`
- Result: PASS (exit code 0)

## L1 - Unit tests
- Command:
  - `pytest tests/unit/ -v -x`
- Result: PASS
- Summary: `101 passed in 0.20s`

## L2 - Unit + Integration + Coverage
- Initial attempt:
  - `pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80`
  - Result: FAIL (`pytest-cov` option 인식 불가 환경)
- Resolved command:
  - `python -m pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80`
- Result: PASS
- Summary:
  - `111 passed in 7.85s`
  - Coverage: `TOTAL 82.84%` (gate 80% 충족)

## L3 - Databricks Dev E2E
- Attempted command (success scenario):
  - `databricks bundle run e2e_setup_mock_data -t dev --params scenario=one_day_normal,run_id=l3_d33_success_20260211T083306Z`
- Result: BLOCKED
- Error:
  - `Invalid access token ... (403 Forbidden)`
  - Endpoint: `https://adb-7405617667923145.5.azuredatabricks.net/api/2.0/preview/scim/v2/Me`
- Note:
  - Databricks 인증 복구 후 아래 시나리오 2건 재실행 필요
    1. success: `scenario=one_day_normal`
    2. fail-fast: `scenario=bad_records_rate_exceed`


## L3 - Databricks Dev E2E (Re-run after auth + deploy)

Execution policy requested by user:
- Poll interval: 20 seconds
- Timeout: 10 minutes (600 seconds)

Pre-step:
- `databricks bundle deploy -t dev` to ensure latest local D-033 code is in workspace.

### Scenario 1 (Success)
- Job: `e2e_setup_mock_data` (job_id: `920043826442932`)
- Scenario: `one_day_normal`
- run_id(job param): `l3_d33_success_postdeploy_20260211T085429Z`
- Databricks run_id: `991694518312097`
- Result: `TERMINATED / SUCCESS`
- Run URL: `https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/920043826442932/run/991694518312097`

### Scenario 2 (Fail-fast)
- Job: `e2e_setup_mock_data` (job_id: `920043826442932`)
- Scenario: `bad_records_rate_exceed`
- run_id(job param): `l3_d33_fail_postdeploy_20260211T085924Z`
- Databricks run_id: `561125235992166`
- Result: `INTERNAL_ERROR / FAILED` (expected)
- Run URL: `https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/920043826442932/run/561125235992166`
- Task error: `RuntimeError: bad_records_rate 0.0196 exceeded threshold 0.01 (rule_id=silver_bad_records_default)`

### Persist-before-fail evidence
- Failing task run_id: `424053008657436`
- Error trace shows failure raised in `persist_bad_records_and_enforce_fail_fast(...)` path after `_set_status("silver_bad_records_written", ...)` call site.
- DBFS status probe:
  - `databricks fs cat dbfs:/tmp/data-pipeline/e2e/setup_status.json`
  - Observed payload: `{"rows": 1, "stage": "silver_bad_records_written", "table": "hive_metastore.silver.bad_records", ...}`
  - Interpretation: quarantine write completed before fail-fast exception.
