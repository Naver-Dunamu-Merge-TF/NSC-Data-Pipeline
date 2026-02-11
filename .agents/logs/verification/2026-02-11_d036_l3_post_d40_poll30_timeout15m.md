# D-036 L3 Verification (Post D-040)

- Date (UTC): 2026-02-11
- Poll interval: 30 seconds
- Timeout: 900 seconds (15 minutes) per run wait loop
- Databricks host: `https://adb-7405617667923145.5.azuredatabricks.net`
- run_id: `l3_d036_postd40_20260211T125746Z`

## Note
- Deployed `databricks.yml` currently has no `sync_dim_rule_scd2` job resource.
- Verification used `e2e_setup` path that syncs rule seed into `gold.dim_rule_scd2`.

## Job sequence and result
1. `bootstrap_catalog` (`job_id=384422610745672`) -> `TERMINATED/SUCCESS`
2. `e2e_setup_mock_data` (`job_id=920043826442932`, scenario=`one_day_normal`) -> `TERMINATED/SUCCESS`
3. `pipeline_a_guardrail` strict (`job_id=122448775339964`) -> `TERMINATED/SUCCESS`
4. `pipeline_b_controls` strict first run (`job_id=164126000479673`) -> `TERMINATED/SUCCESS`
5. `pipeline_c_analytics` (`job_id=1002340892997138`) -> `TERMINATED/SUCCESS`
6. `pipeline_b_controls` strict rerun (same `run_id`) -> `TERMINATED/SUCCESS`

## SQL post-checks
- `gold.dim_rule_scd2` row count: `9`
- `gold.exception_ledger` duplicate groups by 6-key
  - key: `(date_kst, domain, exception_type, run_id, metric, message)`
  - result: `0`

## Outcome
- L3 execution under requested policy (`30s` polling / `15m` timeout) completed successfully.
- No recurrence of `DELTA_MULTIPLE_SOURCE_ROW_MATCHING_TARGET_ROW_IN_MERGE` in this run.

## Evidence logs
- Main: `.agents/logs/verification/L3_d036_postd40_remote_nosync_20260211T125746Z.log`
- Deploy: `.agents/logs/verification/L3_d036_postd40_bundle_deploy_20260211T124921Z.log`
- Validate: `.agents/logs/verification/L3_d036_postd40_bundle_validate_20260211T124915Z.log`
- Failed attempt (invalid sync job id): `.agents/logs/verification/L3_d036_postd40_remote_20260211T125044Z.log`
