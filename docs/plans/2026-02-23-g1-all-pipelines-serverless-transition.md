# G1 All-Pipeline Serverless Transition Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for per-task implementation, review, and fix loops. Use `superpowers:executing-plans` to execute tasks in order.

**Goal:** Convert `pipeline_a_guardrail`, `pipeline_silver_materialization`, `pipeline_b_controls`, and `pipeline_c_analytics` to serverless job compute while preserving run context, least-privilege access, and L3 smoke reliability.

**Architecture:** Keep Databricks Jobs orchestration and pipeline code unchanged (`scripts/run_pipeline_*.py`, `src/*`). Change compute wiring in `databricks.yml` from `job_clusters/new_cluster` to serverless `performance_target + environments`. Apply the resolved D-044 execution identity and ACL model (`SP + verifier`) before smoke runs, then verify runtime metadata and L3 convergence with schedule interference controls.

**Tech Stack:** Databricks Asset Bundles (`databricks.yml`), Databricks CLI, Bash scripts, `jq`, pytest, Markdown evidence under `.agents/logs/verification/`.

---

## Mandatory Subagent Loop (Implement -> Review -> Fix)

1. Implementation subagent performs only current task scope.
2. Spec reviewer subagent checks SSOT alignment (`.specs/*`, roadmap DoD, verification level).
3. Code-quality reviewer subagent checks regression risk, determinism, and operability.
4. If findings exist, fix subagent applies minimal changes and reviewer re-checks.
5. Parent agent records evidence and updates status docs only from verified outcomes.

Loop checklist for every task:
- DoD alignment: `.roadmap/implementation_roadmap.md` (`SEC-005`, `SEC-007`, `SEC-008`)
- Decision hygiene: `.specs/decision_open_items.md` (`D-044` fixed values must be used)
- Verification ladder compliance: L0/L1/L2/L3 as applicable
- Evidence completeness: UTC, executor, commands, outputs, blockers, next action

---

## Fixed Preconditions (D-044)

- `run_as` service principal: `2dt-final-team4-datapipeline-runas-dev-20260223`
- `app_id` (SSOT value): `eb69a479-7a7d-4e2b-9cba-05d2262d8d3c`
- ACL subjects: `service principal + verifier(2dt026@msacademy.msai.kr)`
- account-level prerequisite: verifier keeps `roles/servicePrincipal.manager` and `roles/servicePrincipal.user`

Reference: `.specs/decision_open_items.md` D-044 section.

---

### Task 1: Freeze Baseline, Scope, And Preconditions

**Files:**
- Read: `databricks.yml`
- Read: `.roadmap/implementation_roadmap.md`
- Read: `.specs/decision_open_items.md`
- Create: `.agents/logs/verification/20260223_all_pipeline_serverless_kickoff.md`

**Step 1: Capture baseline**

Run:
```bash
mkdir -p .agents/logs/verification
databricks bundle validate -t dev | tee .agents/logs/verification/20260223_all_pipeline_serverless_bundle_validate.log
databricks jobs list -t dev -o json > .agents/logs/verification/20260223_all_pipeline_serverless_jobs_before.json
```
Expected: validation passes and pre-change job snapshot is stored.

**Step 2: Record kickoff decisions**

Document in kickoff note:
- fixed compute path is blocked in current training RG window
- D-044 resolved principal/app_id and verifier principal
- serverless conversion scope is only A/Silver/B/C

Expected: markdown with `Known`, `Unknown`, `Blocked`, `Out-of-Scope`.

**Step 3: Commit**

```bash
git add .agents/logs/verification/20260223_all_pipeline_serverless_kickoff.md
git commit -m "Capture baseline and D-044 preconditions for serverless transition"
```

---

### Task 2: Write Failing Tests For Serverless Compute Contract

**Files:**
- Create: `tests/unit/test_all_pipeline_serverless_transition.py`

**Step 1: Add failing tests (TDD)**

For each target job (`pipeline_a_guardrail`, `pipeline_silver_materialization`, `pipeline_b_controls`, `pipeline_c_analytics`) assert:
- `performance_target` exists
- `environments` exists and task uses `environment_key`
- `job_clusters` is absent
- task-level `job_cluster_key` is absent
- existing `run_as`, schedule, parameters, retry, timeout are preserved

**Step 2: Run and confirm failing state**

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_all_pipeline_serverless_transition.py -v
```
Expected: FAIL before implementation.

**Step 3: Commit**

```bash
git add tests/unit/test_all_pipeline_serverless_transition.py
git commit -m "Define red test contract for four pipeline serverless wiring"
```

---

### Task 3: Convert Bundle Wiring And Deploy

**Files:**
- Modify: `databricks.yml`
- Update: `tests/unit/test_all_pipeline_serverless_transition.py`

**Step 1: Convert compute wiring**

For each target job:
- remove `job_clusters`
- remove task `job_cluster_key`
- add `performance_target: STANDARD`
- add job `environments` and task `environment_key`
- preserve task graph, schedule, retries, timeout, notifications, run_as, parameters

Also ensure:
- `targets.dev.variables.run_as_principal` is `eb69a479-7a7d-4e2b-9cba-05d2262d8d3c`

**Step 2: Validate and run tests**

Run:
```bash
databricks bundle validate -t dev
.venv/bin/python -m pytest tests/unit/test_all_pipeline_serverless_transition.py -v
```
Expected: validate OK and tests PASS.

**Step 3: Deploy and snapshot runtime**

Run:
```bash
databricks bundle deploy -t dev | tee .agents/logs/verification/20260223_all_pipeline_serverless_deploy.log
databricks jobs list -t dev -o json > .agents/logs/verification/20260223_all_pipeline_serverless_jobs_after_deploy.json
```
Expected: deployed job settings reflect serverless wiring.

**Step 4: Commit**

```bash
git add databricks.yml tests/unit/test_all_pipeline_serverless_transition.py
git commit -m "Switch four pipelines to serverless compute and deploy updated bundle"
```

---

### Task 4: Apply Resolved Run-As + ACL Model (SP + Verifier)

**Files:**
- Create: `scripts/phase7/sec005_apply_verifier_acl.sh`
- Update: `.agents/logs/verification/20260223_sec005_run_as_acl.md`

**Step 1: Implement verifier ACL helper script**

Script requirements:
- options: `--target`, `--catalog`, `--principal`, `--dry-run|--apply`
- apply/check `USE_CATALOG` on catalog and `USE_SCHEMA/SELECT/MODIFY` on `bronze`, `silver`, `gold`
- write JSON assertions:
  - `.agents/logs/verification/20260223_sec005_verifier_acl_assertions.json`

**Step 2: L0 syntax checks**

Run:
```bash
bash -n scripts/phase7/sec005_apply_verifier_acl.sh
bash -n scripts/phase7/sec005_run_as_acl_apply.sh
```
Expected: no syntax errors.

**Step 3: Apply SP run_as + SP ACL and verifier ACL**

Run:
```bash
RUN_AS_PRINCIPAL="eb69a479-7a7d-4e2b-9cba-05d2262d8d3c"
VERIFIER_PRINCIPAL="2dt026@msacademy.msai.kr"
CATALOG_NAME="$(python - <<'PY'
import yaml
from pathlib import Path
cfg = yaml.safe_load(Path('configs/dev.yaml').read_text(encoding='utf-8'))
print(cfg['databricks']['catalog'])
PY
)"

bash scripts/phase7/sec005_run_as_acl_apply.sh \
  --target dev \
  --run-as-principal "${RUN_AS_PRINCIPAL}" \
  --catalog "${CATALOG_NAME}" \
  --apply

bash scripts/phase7/sec005_apply_verifier_acl.sh \
  --target dev \
  --catalog "${CATALOG_NAME}" \
  --principal "${VERIFIER_PRINCIPAL}" \
  --apply
```
Expected: SP run_as is applied and both subjects have minimum ACL.

**Step 4: Assertions gate**

Run:
```bash
jq -e '.run_as_ok and .use_catalog_ok and .use_schema_ok and .select_ok and .modify_ok' \
  .agents/logs/verification/20260223_sec005_acl_assertions.json >/dev/null
jq -e '.use_catalog_ok and .use_schema_ok and .select_ok and .modify_ok' \
  .agents/logs/verification/20260223_sec005_verifier_acl_assertions.json >/dev/null
```
Expected: both commands exit 0.

**Step 5: Commit**

```bash
git add scripts/phase7/sec005_apply_verifier_acl.sh \
  .agents/logs/verification/20260223_sec005_run_as_acl.md
git commit -m "Apply resolved SEC-005 run-as identity and verifier ACL baseline"
```

---

### Task 5: Add Runtime Serverless Assertion Script

**Files:**
- Create: `scripts/phase7/verify_all_pipeline_serverless_runtime.sh`
- Update: `.agents/logs/verification/20260223_all_pipeline_serverless_kickoff.md`

**Step 1: Implement runtime checker**

Script requirements:
- inputs: `--target`, `--output-json`
- fetch deployed jobs
- assert serverless config for four targets:
  - `performance_target` present
  - no `job_clusters`
  - no task `job_cluster_key`
  - `run_as` present
- output JSON:
  - `.agents/logs/verification/20260223_all_pipeline_serverless_runtime_assertions.json`

**Step 2: L0 check**

Run:
```bash
bash -n scripts/phase7/verify_all_pipeline_serverless_runtime.sh
```
Expected: no syntax errors.

**Step 3: Execute assertion**

Run:
```bash
bash scripts/phase7/verify_all_pipeline_serverless_runtime.sh --target dev \
  --output-json .agents/logs/verification/20260223_all_pipeline_serverless_runtime_assertions.json
jq -e 'all(.[]; .status == "PASS")' \
  .agents/logs/verification/20260223_all_pipeline_serverless_runtime_assertions.json >/dev/null
```
Expected: all four pipelines PASS.

**Step 4: Commit**

```bash
git add scripts/phase7/verify_all_pipeline_serverless_runtime.sh \
  .agents/logs/verification/20260223_all_pipeline_serverless_kickoff.md
git commit -m "Add deterministic runtime assertions for serverless four-pipeline jobs"
```

---

### Task 6: Execute L3 Smoke With Schedule Interference Control

**Files:**
- Create: `scripts/phase7/toggle_core_pipeline_schedules.sh`
- Update: `scripts/phase7/verify_sec005_smoke_l3.sh`
- Create: `.agents/logs/verification/20260223_all_pipeline_serverless_smoke.md`

**Step 1: Implement schedule toggle helper**

Script requirements:
- options: `--target`, `--pause|--resume`
- target jobs: A/Silver/B/C only
- output JSON for applied states:
  - `.agents/logs/verification/20260223_all_pipeline_serverless_schedule_states.json`

**Step 2: L0 checks**

Run:
```bash
bash -n scripts/phase7/toggle_core_pipeline_schedules.sh
bash -n scripts/phase7/verify_sec005_smoke_l3.sh
```
Expected: no syntax errors.

**Step 3: Pause schedules, run smoke, always resume**

Run:
```bash
RUN_ID="serverless4_smoke_$(date -u +%Y%m%dT%H%M%SZ)"
DATE_KST="${DATE_KST:-$(TZ=Asia/Seoul date -d 'yesterday' +%F)}"

cleanup() {
  bash scripts/phase7/toggle_core_pipeline_schedules.sh --target dev --resume || true
}
trap cleanup EXIT

bash scripts/phase7/toggle_core_pipeline_schedules.sh --target dev --pause

databricks bundle run pipeline_a_guardrail -t dev --no-wait \
  --params run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}
databricks bundle run pipeline_silver_materialization -t dev --no-wait \
  --params run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}
databricks bundle run pipeline_b_controls -t dev --no-wait \
  --params run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}
databricks bundle run pipeline_c_analytics -t dev --no-wait \
  --params run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}

bash scripts/phase7/verify_sec005_smoke_l3.sh \
  --target dev \
  --run-id "${RUN_ID}" \
  --poll-seconds 20 \
  --timeout-seconds 600
```
Expected: all four runs reach `TERMINATED/SUCCESS`; schedules are resumed in all cases.

**Step 4: Commit**

```bash
git add scripts/phase7/toggle_core_pipeline_schedules.sh \
  scripts/phase7/verify_sec005_smoke_l3.sh \
  .agents/logs/verification/20260223_all_pipeline_serverless_smoke.md
git commit -m "Run isolated serverless smoke window with deterministic schedule control"
```

---

### Task 7: Verify Pipeline A 10-Minute Cadence On Serverless

**Files:**
- Create: `scripts/phase7/verify_pipeline_a_serverless_cadence.sh`
- Update: `.agents/logs/verification/20260223_all_pipeline_serverless_smoke.md`

**Step 1: Implement cadence checker**

Script requirements:
- inputs: `--target`, `--window-hours`, `--min-samples`, `--max-total-seconds`, `--max-queue-seconds`, `--output-json`
- read recent runs of `pipeline_a_guardrail`
- compute queue delay and total runtime percentiles
- output summary JSON:
  - `.agents/logs/verification/20260223_pipeline_a_serverless_cadence.json`

**Step 2: L0 check**

Run:
```bash
bash -n scripts/phase7/verify_pipeline_a_serverless_cadence.sh
```
Expected: no syntax errors.

**Step 3: Execute cadence gate**

Run:
```bash
bash scripts/phase7/verify_pipeline_a_serverless_cadence.sh \
  --target dev \
  --window-hours 24 \
  --min-samples 6 \
  --max-total-seconds 600 \
  --max-queue-seconds 120 \
  --output-json .agents/logs/verification/20260223_pipeline_a_serverless_cadence.json
```
Expected: PASS, or explicit BLOCKED with measured cause.

**Step 4: Commit**

```bash
git add scripts/phase7/verify_pipeline_a_serverless_cadence.sh \
  .agents/logs/verification/20260223_all_pipeline_serverless_smoke.md
git commit -m "Measure Pipeline A serverless cadence against 10-minute operating target"
```

---

### Task 8: Final Audit And Document Sync

**Files:**
- Modify: `.roadmap/implementation_roadmap.md`
- Modify: `.specs/decision_open_items.md` (only if new unresolved assumptions appear)
- Modify: `.specs/ops/operations_runbook.md` (if baseline changed)
- Create: `.agents/logs/verification/20260223_all_pipeline_serverless_signoff.md`

**Step 1: Final reviewer checklist**

Required checks:
- bundle + runtime metadata both show serverless for A/Silver/B/C
- SP run_as (`eb69a479-7a7d-4e2b-9cba-05d2262d8d3c`) is effective
- ACL assertions PASS for SP and verifier (`2dt026@msacademy.msai.kr`)
- L3 smoke PASS with 20s poll and 600s timeout
- Pipeline A cadence gate PASS or clearly documented blocker

Expected: PASS/FAIL checklist with blockers and owner.

**Step 2: Fix-only loop**

For each failed item:
- minimal patch
- rerun only relevant verification command
- re-review until PASS or explicit BLOCKED state

**Step 3: Sync docs with verified state only**

Update:
- roadmap status/evidence paths
- decision log entries only when unresolved assumptions are newly discovered
- runbook only for finalized operational baseline

Expected: no estimated status; all status changes point to evidence files.

**Step 4: Commit**

```bash
git add .roadmap/implementation_roadmap.md \
  .specs/decision_open_items.md \
  .specs/ops/operations_runbook.md \
  .agents/logs/verification/20260223_all_pipeline_serverless_signoff.md
git commit -m "Synchronize roadmap and signoff documents after serverless transition evidence"
```

---

## Verification Matrix

| Scope | Minimum level | Command |
|---|---|---|
| Script syntax per edit | L0 | `python -m py_compile <python_file>` and/or `bash -n <script>` |
| Serverless contract test | L1 | `.venv/bin/python -m pytest tests/unit/test_all_pipeline_serverless_transition.py -v -x` |
| Unit+integration guard | L2 | `.venv/bin/python -m pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80` |
| Run-as/ACL assertion gate | L3-supporting | `jq -e '.run_as_ok and .use_catalog_ok and .use_schema_ok and .select_ok and .modify_ok' .agents/logs/verification/20260223_sec005_acl_assertions.json` |
| Runtime serverless assertion | L3-supporting | `bash scripts/phase7/verify_all_pipeline_serverless_runtime.sh --target dev --output-json .agents/logs/verification/20260223_all_pipeline_serverless_runtime_assertions.json` |
| A/Silver/B/C smoke convergence | L3 | `bash scripts/phase7/verify_sec005_smoke_l3.sh --target dev --run-id "${RUN_ID}" --poll-seconds 20 --timeout-seconds 600` |
| Pipeline A cadence gate | L3-supporting | `bash scripts/phase7/verify_pipeline_a_serverless_cadence.sh --target dev --window-hours 24 --min-samples 6 --max-total-seconds 600 --max-queue-seconds 120` |

## Exit Criteria

- A/Silver/B/C deployed definitions are serverless and runtime assertions pass.
- `job_clusters` and task `job_cluster_key` are absent for the four target jobs.
- D-044 run_as principal (`eb69a479-7a7d-4e2b-9cba-05d2262d8d3c`) is active on target jobs.
- SP and verifier principals both pass minimum UC ACL assertions.
- L3 smoke completes successfully within 20s polling / 600s timeout.
- Pipeline A cadence evidence supports 10-minute operating target or is explicitly escalated as blocker.
- Roadmap/decision/runbook are synchronized with evidence.

## Rollback Notes

- If conversion regresses, restore previous compute wiring and redeploy.
- If one pipeline regresses, roll back only that pipeline and keep others on serverless.
- If run_as/ACL changes cause failure, revert to prior execution principal only for incident containment, then reopen D-044 incident log.
- Record all rollback actions under `.agents/logs/verification/` with UTC timestamp, actor, and reason.
