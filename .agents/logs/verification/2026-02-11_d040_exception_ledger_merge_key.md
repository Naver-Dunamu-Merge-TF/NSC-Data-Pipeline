# D-040 Verification Evidence (Exception Ledger Merge Key Expansion)

- Date (UTC): 2026-02-11
- Change scope:
  - `gold.exception_ledger` merge key expanded to `(date_kst, domain, exception_type, run_id, metric, message)`
  - Tests/docs aligned for same-`run_id` rerun idempotency in Pipeline B

## L0
- Command:
  - `python -m py_compile src/common/table_metadata.py`
  - `python -m py_compile tests/unit/test_table_metadata.py`
  - `python -m py_compile tests/integration/test_backfill_idempotency.py`
- Result: PASS
- Log: `.agents/logs/verification/L0_d040_20260211T114614Z.log`

## L1
- Command: `pytest tests/unit/ -v -x`
- Result: PASS (`123 passed, 1 skipped`)
- Log: `.agents/logs/verification/L1_d040_20260211T114619Z.log`

## L2
- First attempt with system `pytest` failed because coverage plugin options were unavailable.
- Re-run with project venv pytest:
  - Command: `.venv/bin/pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80`
  - Result: PASS (`137 passed`, coverage `82.99%`)
- Logs:
  - Fail (plugin missing): `.agents/logs/verification/L2_d040_20260211T114626Z.log`
  - Pass (venv): `.agents/logs/verification/L2_d040_venv_20260211T114705Z.log`

## L3
Execution policy applied on all attempts:
- Poll interval: 20 seconds
- Timeout: 600 seconds per run wait loop
- Auth mode: `DATABRICKS_AUTH_TYPE=azure-cli`

### Attempt notes
1. Setup-inclusive attempts:
   - `.agents/logs/verification/L3_d040_remote_20260211T114907Z.log` (CLI payload format fix needed)
   - `.agents/logs/verification/L3_d040_remote_retry_20260211T114930Z.log` (run_id capture bug fix needed)
   - `.agents/logs/verification/L3_d040_remote_retry2_20260211T114956Z.log` (run_id capture bug fix needed)
   - `.agents/logs/verification/L3_d040_remote_retry3_20260211T115022Z.log` (`e2e_setup` stayed `QUEUED` and timed out at 600s)
2. Pipeline B only validation:
   - `.agents/logs/verification/L3_d040_pipeline_b_only_20260211T120106Z.log`
   - Result: Pipeline B first + rerun reached `TERMINATED/SUCCESS` with same `run_id`
3. Full validation without setup (A -> B -> B rerun, same run_id):
   - `.agents/logs/verification/L3_d040_A_B_rerun_20260211T121525Z.log`
   - Result: PASS
     - Pipeline A: `TERMINATED/SUCCESS`
     - Pipeline B first: `TERMINATED/SUCCESS`
     - Pipeline B rerun (same `run_id`): `TERMINATED/SUCCESS`
     - `pipeline_b_recon`: `TERMINATED/SUCCESS`
4. Post-run duplicate key safety check (SQL API):
   - Query scope: `run_id=l3_d040_ab_20260211T121525`
   - Group key: `(date_kst, domain, exception_type, run_id, metric, message)`
   - Result: `dup_key_groups=0`
   - Log: `.agents/logs/verification/L3_d040_sql_dupcheck_20260211T123523Z.log`

## Conclusion
- D40 target acceptance was satisfied in L3 by successful same-`run_id` Pipeline B rerun under 20s polling / 10-minute timeout policy.
- No `DELTA_MULTIPLE_SOURCE_ROW_MATCHING_TARGET_ROW_IN_MERGE` recurrence was observed in the successful L3 rerun path.
