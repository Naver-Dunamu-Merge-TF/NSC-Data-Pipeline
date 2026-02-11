# D-036 Verification Evidence

- Date (UTC): 2026-02-11T09:38:44Z
- Scope: Rule SSOT migration (`mock seed` -> `gold.dim_rule_scd2`), runtime loader, A/B CLI, sync job, docs

## L0
- Command: `python -m py_compile $(git diff --name-only -- '*.py')`
- Result: PASS
- Log: `.agents/logs/verification/L0_d036_20260211T093844Z.log`

## L1
- Command: `pytest tests/unit/ -v -x`
- Result: PASS (120 passed)
- Log: `.agents/logs/verification/L1_d036_20260211T093844Z.log`

## L2
- Command: `python -m pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80`
- Result: PASS (132 passed, coverage 82.98%)
- Log: `.agents/logs/verification/L2_d036_20260211T093844Z.log`

## L3
- Attempted commands:
  - `databricks jobs list --output json`
  - `databricks jobs run-now --job-id 0 --output json`
- Result: BLOCKED (workspace auth failure: `Invalid access token`)
- Log: `.agents/logs/verification/L3_d036_attempt_20260211T093844Z.log`

## Notes
- L3 polling(20s interval, 10min timeout) could not proceed because run submission failed before run_id acquisition.
