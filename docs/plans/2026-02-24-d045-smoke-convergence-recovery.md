# D-045 Smoke Convergence Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `pipeline_a_guardrail`/`pipeline_silver_materialization`의 `gold.dim_rule_scd2` 룰 로딩 실패와 그 연쇄(`pipeline_b_controls`/`pipeline_c_analytics` fail-closed), 그리고 retry 대기(`Waiting for cluster`)로 인한 600초 smoke timeout을 제거해 L3 smoke를 600초 내에 수렴시킨다.

**Architecture:** 복구를 두 레이어로 분리한다. (1) 실행 전 `sync_dim_rule_scd2` + 룰 무결성 사전검증으로 A/Silver의 결정적 실패를 차단한다. (2) smoke 실행을 `A/Silver -> B/C` 단계형으로 바꾸고, poller는 `deterministic failure + retry pending` 패턴을 감지하면 즉시 cancel/fail-fast 처리해 상위 run `RUNNING` 고착을 제거한다.

**Tech Stack:** Databricks Asset Bundles (`databricks.yml`), Bash (`scripts/phase7/*.sh`), Python (`src/io/rule_loader.py`), pytest, verification evidence under `.agents/logs/verification/`.

## Design Decisions (Open Questions Resolved)

1. `--fail-fast-deterministic`는 기본값 `off`로 둔다.  
   이유: false positive로 정상 재시도를 잘라내는 운영 리스크를 피하고, D-046 복구 smoke에서만 명시적으로 `on` 한다.
2. SEC-005 L3 게이트 판정은 staged smoke(`A/Silver -> B/C`)를 공식 기준으로 채택한다.  
   이유: B/C는 `pipeline_silver` readiness 의존이 명시된 fail-closed 구조이므로 동시 제출보다 단계형이 아키텍처 정합성이 높다. 병렬 4개 제출 smoke는 관측용 보조 신호로 유지한다.
3. 결정적 실패 판별 신호는 parent `state_message`가 아니라 task-level output을 사용한다.  
   이유: 현재 timeout 케이스에서 parent run은 `RUNNING`만 보이고 상세 에러는 task output에 존재한다.
4. smoke 시작 전 preflight로 run_as SP 권한 + rule table 상태를 검증한다.  
   이유: `sync_dim_rule_scd2` 성공만으로 runtime read 가능성이 보장되지 않으므로, grants/assertion + table 무결성을 분리 점검한다.

---

### Task 1: 실패 시그니처를 재현 가능하게 고정하고 Red Test를 만든다

**Files:**
- Modify: `tests/unit/test_sec005_execution_hardening.py`
- Modify: `tests/unit/test_rule_loader.py`
- Create: `.agents/logs/verification/20260224_d046_smoke_recovery_kickoff.md`

**Step 1: 현재 실패 체인 고정 기록**

Run:
```bash
cat > .agents/logs/verification/20260224_d046_smoke_recovery_kickoff.md <<'EOF'
# D-046 Smoke Recovery Kickoff
- source: 20260224_d045_smoke_failure_root_cause.md
- failure_chain:
  1) A/Silver rule load failure (gold.dim_rule_scd2)
  2) B/C readiness fail-closed
  3) retry pending waiting-for-cluster
  4) parent run RUNNING -> 600s timeout
EOF
```
Expected: 재현 기준 문서가 저장된다.

**Step 2: 실패하는 테스트 추가(기능 요구 먼저 고정)**

- `verify_sec005_smoke_l3.sh`에 아래 요구를 검사하는 정적 테스트를 추가:
  - `--pipelines` (부분 파이프라인 poll 지원)
  - `--fail-fast-deterministic` (결정적 실패 조기 종료)
  - `--fail-fast-deterministic` default는 `off`
  - `databricks jobs cancel-run` 호출 경로 존재
  - task output 수집 경로(`databricks jobs get-run-output`) 존재
- `rule_loader` 예외 메시지에 원인 예외 클래스/메시지 포함 요구 테스트 추가

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_sec005_execution_hardening.py tests/unit/test_rule_loader.py -v
```
Expected: 새 요구가 아직 구현 전이면 FAIL.

**Step 3: Commit**

```bash
git add tests/unit/test_sec005_execution_hardening.py tests/unit/test_rule_loader.py .agents/logs/verification/20260224_d046_smoke_recovery_kickoff.md
git commit -m "test: define smoke convergence recovery requirements"
```

---

### Task 2: 룰 로딩 실패의 원인 가시성을 높인다 (A/Silver 1차 원인 단축)

**Files:**
- Modify: `src/io/rule_loader.py`
- Modify: `tests/unit/test_rule_loader.py`

**Step 1: Red test 확인**

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_rule_loader.py -v -k "runtime_rules"
```
Expected: 예외 메시지 요구 테스트 FAIL.

**Step 2: 최소 구현**

- `load_runtime_rules()`의 strict/fallback 실패 메시지에 `cause_type` + `cause_message`를 포함한다.
- 기존 fail-fast 정책(테이블 payload 무결성 오류는 fallback 금지)은 유지한다.

예시 메시지 목표:
- `Failed to load runtime rules from table (..., mode=fallback, cause=ValueError: Multiple is_current=true ...)`

**Step 3: 테스트 재실행**

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_rule_loader.py -v
```
Expected: PASS.

**Step 4: Commit**

```bash
git add src/io/rule_loader.py tests/unit/test_rule_loader.py
git commit -m "chore: include root cause detail in runtime rule load errors"
```

---

### Task 3: smoke 실행을 단계형으로 바꿔 B/C 연쇄 실패를 차단한다

**Files:**
- Create: `scripts/phase7/verify_sec005_rule_preflight.sh`
- Create: `scripts/phase7/run_sec005_smoke_recovery.sh`
- Modify: `tests/unit/test_sec005_execution_hardening.py`

**Step 1: Red test 확인**

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_sec005_execution_hardening.py -v -k "smoke"
```
Expected: 신규 스크립트/플래그 요구 테스트 FAIL.

**Step 2: 실행 스크립트 구현**

`run_sec005_smoke_recovery.sh` 순서:
1. `toggle_core_pipeline_schedules.sh --pause`
2. `verify_sec005_rule_preflight.sh --target <target> --catalog <catalog> --run-as-principal <sp-app-id>`
3. `databricks bundle run sync_dim_rule_scd2 -t <target> ...`
4. A/Silver submit (`--no-wait`)
5. `verify_sec005_smoke_l3.sh --pipelines pipeline_a_guardrail,pipeline_silver_materialization --fail-fast-deterministic ...`
6. A/Silver 성공 시 B/C submit
7. `verify_sec005_smoke_l3.sh --pipelines pipeline_b_controls,pipeline_c_analytics --fail-fast-deterministic ...`
8. trap으로 무조건 schedule resume

`verify_sec005_rule_preflight.sh` 요구사항:
- SP 대상 grants assertion(`USE_CATALOG`, `USE_SCHEMA`, `SELECT`, `MODIFY`) 확인
- `gold.dim_rule_scd2` 존재 + `is_current=true` 무결성 체크(SQL)
- `gold.pipeline_state` 존재 확인
- machine-checkable JSON 출력(예: `rule_table_exists`, `rule_current_uniqueness_ok`, `pipeline_state_exists`, `sp_acl_ok`)

**Step 3: 스크립트 문법 검증**

Run:
```bash
bash -n scripts/phase7/verify_sec005_rule_preflight.sh
bash -n scripts/phase7/run_sec005_smoke_recovery.sh
```
Expected: PASS.

**Step 4: Commit**

```bash
git add scripts/phase7/verify_sec005_rule_preflight.sh scripts/phase7/run_sec005_smoke_recovery.sh tests/unit/test_sec005_execution_hardening.py
git commit -m "feat: add staged smoke runner with rule sync preflight"
```

---

### Task 4: retry pending으로 RUNNING 고착되는 케이스를 verifier에서 조기 종료한다

**Files:**
- Modify: `scripts/phase7/verify_sec005_smoke_l3.sh`
- Modify: `tests/unit/test_sec005_execution_hardening.py`

**Step 1: Red test 확인**

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_sec005_execution_hardening.py -v -k "polling_and_timeout"
```
Expected: fail-fast/cancel 관련 요구 테스트 FAIL.

**Step 2: 최소 구현**

`verify_sec005_smoke_l3.sh`에 추가:
- `--pipelines` 입력으로 대상 파이프라인 subset 지원
- `--fail-fast-deterministic` 플래그
- `--fail-fast-deterministic` 기본값은 `off` (호환성 유지)
- task-level 실패 판별 경로:
  - `jobs get-run`으로 `tasks[].run_id` 수집
  - 각 task run에 대해 `jobs get-run-output` 조회
  - output에서 결정적 시그니처(`Failed to load runtime rules from table`, `UpstreamReadinessError`) 탐지
- run/task 상태에서 아래 조건을 동시에 만족할 때만 fail-fast:
  - 같은 task_key에서 결정적 실패 시그니처가 확인된 TERMINATED/FAILED attempt 존재
  - 후속 retry attempt가 `PENDING` + `Waiting for cluster`
- fail-fast 시:
  - `databricks jobs cancel-run`으로 해당 run 정리
  - summary JSON에 `failure_reason`, `cancelled_run_ids`, `detected_errors` 기록

**Step 3: 테스트 재실행**

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_sec005_execution_hardening.py -v
```
Expected: PASS.

**Step 4: Commit**

```bash
git add scripts/phase7/verify_sec005_smoke_l3.sh tests/unit/test_sec005_execution_hardening.py
git commit -m "feat: fail-fast deterministic smoke failures and cancel pending retries"
```

---

### Task 5: SSOT 문서와 운영 가이드를 현재 복구 전략으로 잠근다

**Files:**
- Modify: `.specs/decision_open_items.md`
- Modify: `.specs/ops/operations_runbook.md`
- Modify: `.roadmap/implementation_roadmap.md`
- Create: `.agents/logs/verification/20260224_d046_smoke_recovery_plan.md`

**Step 1: D-046 결정 추가**

`decision_open_items.md`에 D-046 추가:
- SEC-005 smoke 표준 실행을 `sync_dim_rule_scd2 -> A/Silver -> B/C`로 고정
- smoke verifier fail-fast deterministic 정책 고정
- staged smoke를 SEC-005 공식 L3 게이트로 채택, 기존 병렬 4개 smoke는 보조 관측으로 명시

**Step 2: runbook 복구 절차 반영**

- 6.x Recovery Playbook에 “smoke convergence 실패 시 staged re-run 절차” 추가
- 증적 파일명/명령어를 실제 스크립트 기준으로 반영

**Step 3: roadmap blocker 문구 갱신**

- SEC-005/SEC-007 next action을 D-046 실행 기준으로 변경
- SEC-005 acceptance 기준에 “staged smoke pass + 증적 파일”을 명시

**Step 4: Commit**

```bash
git add .specs/decision_open_items.md .specs/ops/operations_runbook.md .roadmap/implementation_roadmap.md .agents/logs/verification/20260224_d046_smoke_recovery_plan.md
git commit -m "docs: lock D-046 smoke convergence recovery policy"
```

---

### Task 6: Verification Ladder 실행 및 종료 기준 확인

**Files:**
- Update: `.agents/logs/verification/20260224_d046_smoke_recovery_verification.md`

**Step 1: L0**

Run:
```bash
python -m py_compile src/io/rule_loader.py
bash -n scripts/phase7/verify_sec005_smoke_l3.sh
bash -n scripts/phase7/verify_sec005_rule_preflight.sh
bash -n scripts/phase7/run_sec005_smoke_recovery.sh
```
Expected: syntax PASS.

**Step 2: L1**

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_rule_loader.py tests/unit/test_sec005_execution_hardening.py -v -x
```
Expected: PASS.

**Step 3: L2 (src/io + scripts 변경 기준)**

Run:
```bash
.venv/bin/python -m pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80
```
Expected: PASS, coverage >= 80.

**Step 4: L3 (20s poll / 600s timeout 고정)**

Run:
```bash
bash scripts/phase7/run_sec005_smoke_recovery.sh \
  --target dev \
  --date-kst "$(python - <<'PY'
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
print((datetime.now(ZoneInfo('Asia/Seoul')) - timedelta(days=1)).date().isoformat())
PY
)" \
  --run-id "d046_smoke_$(date -u +%Y%m%dT%H%M%SZ)" \
  --poll-seconds 20 \
  --timeout-seconds 600
```
Expected:
- A/Silver가 룰 로딩 실패 없이 종료
- B/C readiness fail-closed 전파 없음
- pending retry `Waiting for cluster` 고착 없이 모든 대상 run TERMINATED
- smoke summary exit_code=0

**Step 5: 종료 기준**

- `20260224_d046_smoke_recovery_verification.md`에 L0/L1/L2/L3 증적 링크, UTC 타임라인, blocker=none 기록
- `20260223_all_pipeline_serverless_signoff.md`의 L3 항목을 PASS로 갱신하고 SEC-005/SEC-007 상태 재평가
- (보조) 기존 방식 병렬 4개 smoke는 정보성으로 1회 실행 가능하나, 실패해도 SEC-005 판정은 staged smoke 기준을 따른다.
