# G1 SEC-006 + SEC-005 Execution Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for per-task implementation, review, and fix loops. Use `superpowers:executing-plans` to execute tasks in order.

**Goal:** Close G1 execution hardening scope for `SEC-006` (config alignment) and `SEC-005` (service principal `run_as` + least-privilege ACL + A/B/C smoke success) with reproducible evidence.

**Architecture:** Execute `SEC-006 -> SEC-005` in sequence to avoid invalid smoke runs caused by config drift. Every task is executed by a fresh subagent, reviewed by a separate reviewer subagent, then fixed by an implementer subagent until acceptance criteria pass. Evidence is written to `.agents/logs/verification/` and roadmap status is updated only after verification passes.

**Tech Stack:** Databricks Asset Bundles (`databricks.yml`), Azure/Databricks CLI, Python/PySpark pipelines, pytest, Markdown evidence logs.

---

## Mandatory Subagent Loop (Implement -> Review -> Fix)

1. Implementation subagent performs only the current task scope.
2. Review subagent checks SSOT alignment (`.specs/`, roadmap DoD, verification level).
3. If findings exist, fix subagent applies minimal corrections.
4. Reviewer re-checks; loop repeats until no blocking findings.
5. Parent agent records final command outputs and evidence links.

Review checklist for every loop:
- DoD match with `.roadmap/implementation_roadmap.md` (`SEC-006`, `SEC-005`)
- Decision hygiene (`.specs/decision_open_items.md`, especially D-018)
- Verification compliance (L1 for `SEC-006`, L3 smoke for `SEC-005`; idempotency is deferred to G1 close signoff)
- Evidence file completeness (timestamp, executor, command, result, next action)

---

### Task 1: Freeze Baseline And Inputs

**Files:**
- Read: `.roadmap/implementation_roadmap.md`
- Read: `.specs/cloud/cloud_migration_rebuild_plan.md`
- Read: `.specs/decision_open_items.md`
- Create: `.agents/logs/verification/20260223_sec005_sec006_kickoff.md`

**Step 1: Capture current observed state**

Run:
```bash
mkdir -p .agents/logs/verification
bash scripts/phase7/audit_cloud_state.sh | tee .agents/logs/verification/20260223_sec005_sec006_kickoff.log
```
Expected: Current host/workspace/catalog/external location/secret scope observations are printed.

**Step 2: Record blockers and assumptions**

Write kickoff note with:
- `SEC-004` dependency status
- target service principal identity for `run_as`
- whether ACL subject mapping is already approved

Expected: one markdown file with explicit `Known`, `Unknown`, `Blocked` sections.

**Step 3: Commit**

```bash
git add .agents/logs/verification/20260223_sec005_sec006_kickoff.md
git commit -m "docs: add sec005 sec006 kickoff baseline"
```

---

### Task 2: Implement SEC-006 Config Alignment

**Files:**
- Modify: `configs/dev.yaml`
- Modify: `configs/common.yaml`
- Create: `scripts/phase7/verify_sec006_config_alignment.py`
- Create: `.agents/logs/verification/20260223_sec006_expected_values.env`
- Create: `.agents/logs/verification/20260223_sec006_config_alignment.md`

**Step 1: Build deterministic baseline + pre-check (before fix)**

Run:
```bash
cat > .agents/logs/verification/20260223_sec006_expected_values.env <<'EOF'
workspace_host=https://adb-7405610275478542.2.azuredatabricks.net
workspace_id=7405610275478542
catalog=nsc_dbw_dev_7405610275478542
external_location=team4_adls_test
base_path=abfss://2dt-final-team4-adls-test@nscstdevw4mlu8.dfs.core.windows.net
secret_scope=ledger-analytics-dev
secret_key=salt_user_key
EOF

python scripts/phase7/verify_sec006_config_alignment.py \
  --config-dev configs/dev.yaml \
  --config-common configs/common.yaml \
  --expected .agents/logs/verification/20260223_sec006_expected_values.env \
  | tee .agents/logs/verification/20260223_sec006_config_alignment_precheck.log || true
```
Expected: command may fail pre-fix when drift exists (allowed at this pre-check step only).

**Step 2: Apply minimal config fixes**

Update only these keys:
- `databricks.workspace_host`
- `databricks.workspace_id`
- `databricks.catalog`
- `storage.external_location`
- `storage.base_path`
- `analytics.secret_scope`
- `analytics.secret_key` (in `configs/common.yaml`, if drift exists)

Expected: config values match observed baseline approved for current cycle.

**Step 3: Re-run deterministic check (after fix)**

Run:
```bash
python scripts/phase7/verify_sec006_config_alignment.py \
  --config-dev configs/dev.yaml \
  --config-common configs/common.yaml \
  --expected .agents/logs/verification/20260223_sec006_expected_values.env \
  | tee .agents/logs/verification/20260223_sec006_config_alignment_postcheck.log
```
Expected: exit code `0` and mismatch count `0`.

**Step 4: Commit**

```bash
git add configs/dev.yaml configs/common.yaml scripts/phase7/verify_sec006_config_alignment.py \
  .agents/logs/verification/20260223_sec006_expected_values.env \
  .agents/logs/verification/20260223_sec006_config_alignment.md
git commit -m "chore: align dev config for sec006"
```

---

### Task 3: Verify SEC-006 (L1)

**Files:**
- Update: `.agents/logs/verification/20260223_sec006_config_alignment.md`

**Step 1: Run unit gate using project venv**

Run:
```bash
.venv/bin/python -m pytest tests/unit/ -v -x
```
Expected: PASS.

**Step 2: Record verification evidence**

Log:
- command
- start/end UTC
- pass/fail
- failing test details (if any)

Expected: evidence file updated with L1 result and next action.

**Step 3: Commit**

```bash
git add .agents/logs/verification/20260223_sec006_config_alignment.md
git commit -m "test: record sec006 verification evidence"
```

---

### Task 4: Implement SEC-005 Run-As + ACL Changes

**Files:**
- Modify: `databricks.yml`
- Create: `scripts/phase7/sec005_run_as_acl_apply.sh`
- Create: `.agents/logs/verification/20260223_sec005_run_as_acl.md`

**Step 1: Capture failing pre-state**

Run:
```bash
databricks bundle validate -t dev
mkdir -p .agents/logs/verification
databricks jobs list -t dev -o json > .agents/logs/verification/20260223_sec005_jobs_before.json
```
Expected: current jobs do not yet satisfy target `run_as` + least-privilege policy.

**Step 2: Add reproducible change script**

Implement `scripts/phase7/sec005_run_as_acl_apply.sh` to:
- apply/update `run_as` principal
- apply minimum UC ACL (`USE CATALOG`, `USE SCHEMA`, `SELECT`, `MODIFY`)
- print changed resources and principals
- support `--target <dev|prod-secure>`, `--dry-run`, `--apply`
- output machine-checkable assertion JSON at `.agents/logs/verification/20260223_sec005_acl_assertions.json`

Expected: script supports dry-run and apply mode.

**Step 3: Apply and validate metadata**

Run:
```bash
RUN_AS_PRINCIPAL="<service-principal-name-or-app-id>"
bash scripts/phase7/sec005_run_as_acl_apply.sh --target dev --run-as-principal "${RUN_AS_PRINCIPAL}" --apply
databricks jobs list -t dev -o json > .agents/logs/verification/20260223_sec005_jobs_after.json
jq -e '.run_as_ok and .use_catalog_ok and .use_schema_ok and .select_ok and .modify_ok' \
  .agents/logs/verification/20260223_sec005_acl_assertions.json >/dev/null
```
Expected: target jobs reflect service principal execution context and ACLs are applied.

**Step 4: Commit**

```bash
git add databricks.yml scripts/phase7/sec005_run_as_acl_apply.sh .agents/logs/verification/20260223_sec005_run_as_acl.md
git commit -m "feat: apply sec005 run-as and acl hardening"
```

---

### Task 5: Verify SEC-005 Smoke (L3)

**Files:**
- Create: `scripts/phase7/verify_sec005_smoke_l3.sh`
- Update: `.agents/logs/verification/20260223_sec005_run_as_acl.md`

**Step 1: Run A/Silver/B/C smoke with parameterized date + run_id**

Run:
```bash
RUN_ID="sec005_smoke_$(date -u +%Y%m%dT%H%M%SZ)"
DATE_KST="${DATE_KST:-$(TZ=Asia/Seoul date -d 'yesterday' +%F)}"
databricks bundle run pipeline_a_guardrail -t dev --params run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}
databricks bundle run pipeline_silver_materialization -t dev --params run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}
databricks bundle run pipeline_b_controls -t dev --params run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}
databricks bundle run pipeline_c_analytics -t dev --params run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}
```
Expected: all runs are submitted successfully.

**Step 2: Poll every 20 seconds with 10-minute timeout**

Run:
```bash
bash scripts/phase7/verify_sec005_smoke_l3.sh --target dev --run-id "${RUN_ID}" --poll-seconds 20 --timeout-seconds 600
```
Expected: all target runs reach `SUCCESS` within timeout.

**Step 3: Record evidence**

Include:
- run ids
- poll interval/timeout
- per-pipeline final state
- failed task details if any

Expected: L3 evidence is sufficient for SEC-005 DoD audit.

**Step 4: Commit**

```bash
git add scripts/phase7/verify_sec005_smoke_l3.sh .agents/logs/verification/20260223_sec005_run_as_acl.md
git commit -m "test: add sec005 smoke verification evidence"
```

Note:
- `e2e_full_pipeline` idempotency 검증은 G1 종료 직전(SEC-008 signoff) 1회 수행한다.
- 현재 SEC-005/SEC-006 실행 계획에서는 idempotency를 수행하지 않는다.

---

### Task 6: Final Review Loop And G1 Document Sync

**Files:**
- Modify: `.roadmap/implementation_roadmap.md`
- Modify: `.specs/decision_open_items.md` (only if new unresolved assumption is discovered)
- Create: `.agents/logs/verification/20260223_sec005_sec006_signoff.md`

**Step 1: Reviewer subagent performs final audit**

Check:
- `SEC-006` drift is zero
- `SEC-005` run_as + ACL + smoke pass evidence exists
- no undocumented assumptions remain

Expected: pass/fail checklist with blocking findings.

**Step 2: Apply fixes for findings (if any)**

Use minimal patches only for failed checklist items.
Expected: reviewer re-check returns pass.

**Step 3: Update roadmap statuses/evidence paths**

Update `SEC-006`, `SEC-005` rows:
- `status`
- `evidence_path`
- detail task progress notes

Expected: roadmap reflects verified state, not estimated state.

**Step 4: Commit**

```bash
git add .roadmap/implementation_roadmap.md .agents/logs/verification/20260223_sec005_sec006_signoff.md
if [[ -n "$(git status --porcelain -- .specs/decision_open_items.md)" ]]; then
  git add .specs/decision_open_items.md
fi
git commit -m "docs: sync roadmap after sec005 sec006 hardening"
```

---

## Verification Matrix

| Scope | Minimum level | Command |
|---|---|---|
| SEC-006 config alignment | L1 | `.venv/bin/python -m pytest tests/unit/ -v -x` |
| SEC-005 run_as + ACL + smoke (current scope) | L3 | `bash scripts/phase7/verify_sec005_smoke_l3.sh --target dev --run-id "${RUN_ID}" --poll-seconds 20 --timeout-seconds 600` |

G1 close policy note:
- Idempotency (`e2e_full_pipeline`)는 G1 종료 직전에 1회 수행한다. 이 계획의 현재 범위에는 포함하지 않는다.

## Exit Criteria

- SEC-006 target keys in `configs/dev.yaml` and `configs/common.yaml` exactly match observed baseline.
- SEC-005 service principal `run_as` transition is applied and least-privilege ACL is enforced.
- Pipeline A/Silver/B/C smoke runs succeed under transitioned execution context.
- `.roadmap/implementation_roadmap.md` G1 관련 상태와 증적 경로가 최신화된다.

## Rollback Notes

- If `run_as` transition fails, restore previous execution principal before next smoke attempt.
- If ACL hardening blocks pipelines, re-open minimal required permissions only for failing objects, then re-run smoke.
- Every rollback action must be logged in `.agents/logs/verification/` with UTC timestamp and actor.
