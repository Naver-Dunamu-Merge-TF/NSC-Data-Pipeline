# Pipeline State Status Contract Alignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for per-task implementation in this session. Use `superpowers:executing-plans` when running this plan in a separate execution session.

**Goal:** `gold.pipeline_state.status` 컬럼을 Data-pipeline 계약에 정식 도입해 ops-agent의 감지/검증/리포트 경로와 계약을 일치시킨다.

**Architecture:** 기존 체크포인트 모델(`last_success_ts`, `last_processed_end`, `last_run_id`, `updated_at`)은 유지하고, 마지막 실행 결과를 나타내는 `status(success|failure)`를 추가한다. Pipeline A/Silver/B/C의 성공/실패 상태 전이가 동일 규칙으로 기록되도록 `pipeline_state_io`를 단일 진실 원천(SSOT)으로 사용한다. 코드 구현/테스트는 선행 가능하지만 Databricks dev 실행 게이트는 `schema migration apply 완료 -> 코드 배포 -> L3 검증` 순서로 고정한다.

**Tech Stack:** Python (PySpark), Databricks Delta/Unity Catalog, pytest (`.venv/bin/python -m pytest`), Databricks bundle/jobs CLI, Markdown specs.

---

## Scope Lock

In scope:
- Data-pipeline 계약/코드/테스트에 `gold.pipeline_state.status` 추가
- Databricks dev 테이블 마이그레이션 및 기존 row backfill
- L1/L2/L3 검증 증적 확보
- 관련 스펙 문서 반영

Out of scope:
- ops-agent 내부 triage 로직 구조 개편
- 모니터링 v2 확장 범위 변경
- `gold.pipeline_state` 외 테이블 스키마 개편

---

## Mandatory Subagent Loop (Implement -> Review -> Fix)

1. 구현 서브에이전트가 해당 Task 범위만 수정하고 테스트를 실행한다.
2. 스펙 리뷰 서브에이전트가 DoD/SSOT 정합성을 검토한다.
3. 코드 품질 리뷰 서브에이전트가 회귀/안정성/가독성 리스크를 검토한다.
4. blocking finding이 있으면 수정 서브에이전트가 최소 변경으로 보정한다.
5. 동일 리뷰를 재실행해 blocking finding이 0이 되면 Task를 완료한다.
6. 부모 에이전트만 roadmap/spec/verification evidence를 갱신한다.

공통 리뷰 체크리스트:
- `status` 값 제한이 `success|failure`로 강제되는가
- 실패 시 checkpoint 유지(D-020)가 유지되는가
- `pipeline_state` 읽기 경로에서 배포 순서 리스크(마이그레이션 전/후)가 제어되는가
- 테스트가 계약 드리프트를 재발 방지하도록 구성되었는가

---

### Task 1: Status Semantics Freeze And Decision Hygiene

**Files:**
- Read: `.specs/data_contract.md`
- Read: `.specs/project_specs.md`
- Read: `.specs/decision_open_items.md`
- Modify: `.specs/decision_open_items.md`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_semantics.md`

**Step 1: 상태 전이 규칙 확정**

정책을 문서로 고정한다.
- 성공 실행: `status='success'`
- 실패 실행: `status='failure'`
- 실패 시 `last_success_ts`, `last_processed_end` 유지(D-020 유지)

**Step 2: 배포 순서 리스크 기록**

`decision_open_items`에 아래를 명시한다.
- 마이그레이션 선행 필수
- backfill 규칙
- 롤백 전략(DDL/UPDATE 실패 시 중단)

**Step 3: 증적 기록**

`.agents/logs/verification/20260224_pipeline_state_status_semantics.md`에 결정/근거/영향 범위를 기록한다.

---

### Task 2: Add Failing Tests For New Contract

**Files:**
- Modify: `tests/unit/test_contracts.py`
- Modify: `tests/unit/test_pipeline_state_io.py`
- Modify: `tests/integration/test_ci_coverage_regression.py`

**Step 1: contract 테스트에 `status` 요구 추가**

- `gold.pipeline_state` cast map에 `status` 존재 검증
- 허용값 검증용 unit test 추가 (`success`, `failure`는 통과, 그 외 실패)

**Step 2: state transition 테스트 강화**

- 성공 전이 후 `status='success'`
- 실패 전이 후 `status='failure'`
- 실패 전이에서 checkpoint 보존 검증 유지

**Step 3: 실패 확인 (red)**

Run:
```bash
.venv/bin/python -m pytest tests/unit/test_contracts.py tests/unit/test_pipeline_state_io.py -q
```
Expected: `status` 누락으로 최소 1개 이상 실패.

---

### Task 3: Implement `status` In Contract And State IO

**Files:**
- Modify: `src/common/contracts.py`
- Modify: `src/io/pipeline_state_io.py`

**Step 1: 계약 컬럼 추가**

`gold.pipeline_state` 계약에 아래 컬럼을 추가한다.
- `status` (`string`, required 권장)

**Step 2: IO 모델/전이 로직 반영**

- `PipelineStateRecord`에 `status` 필드 추가
- `as_dict()`에 `status` 포함
- `apply_pipeline_state()` 성공/실패 전이 시 status 값을 강제 설정
- 파서(`parse_pipeline_state_record`)에서 status 미존재 row 처리 전략 반영
  - 마이그레이션 이전 호환 위해 보수적 fallback 규칙을 적용

**Step 3: 타입/값 검증**

- `status` normalize/validation을 `pipeline_state_io`에 집중
- 허용값 외 입력 시 `ValueError`

---

### Task 4: Wire Runtime Writers And Migration SQL

**Files:**
- Modify: `scripts/run_pipeline_a.py`
- Modify: `scripts/run_pipeline_silver.py`
- Modify: `scripts/run_pipeline_b.py`
- Modify: `scripts/run_pipeline_c.py`
- Create: `scripts/phase7/migrate_pipeline_state_add_status.sql`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_migration_dev.sql.log`

**Step 1: writer 경로 정합 확인/보정**

각 파이프라인에서 `apply_pipeline_state()` 결과가 계약 정렬 후 `status`를 실제 write하도록 보정한다.

**Step 2: migration SQL 작성**

`migrate_pipeline_state_add_status.sql`에 포함:
1. `ALTER TABLE <catalog>.gold.pipeline_state ADD COLUMNS (status STRING)`
2. 결정적 backfill 규칙 (`status IS NULL` 대상):

```sql
UPDATE <catalog>.gold.pipeline_state
SET status = CASE
  WHEN last_success_ts IS NOT NULL AND updated_at = last_success_ts THEN 'success'
  ELSE 'failure'
END
WHERE status IS NULL;
```

3. 값 검증 query (`status` 분포/NULL 건수/허용값 외 건수):

```sql
SELECT status, COUNT(*) AS cnt
FROM <catalog>.gold.pipeline_state
GROUP BY status;

SELECT COUNT(*) AS null_status_cnt
FROM <catalog>.gold.pipeline_state
WHERE status IS NULL;

SELECT COUNT(*) AS invalid_status_cnt
FROM <catalog>.gold.pipeline_state
WHERE status NOT IN ('success', 'failure');
```

**Step 3: dev 적용 로그 남김**

적용 명령/결과를 `.agents/logs/verification/20260224_pipeline_state_status_migration_dev.sql.log`에 저장한다.

---

### Task 5: Expand Tests And Run L0/L1/L2

**Files:**
- Modify: `tests/integration/test_pipeline_b_readiness.py`
- Modify: `tests/integration/test_pipeline_c_readiness.py`
- Modify: `tests/unit/test_upstream_readiness.py`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_deploy.log`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_readiness_regression.log`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_l0.log`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_l1.log`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_l2.log`

**Step 1: migration 이후 코드 배포(dev)**

Run:
```bash
databricks bundle deploy -t dev | tee .agents/logs/verification/20260224_pipeline_state_status_deploy.log
```
Expected: deploy 성공, 런타임 코드가 status 스키마와 정합한 버전으로 반영된다.

**Step 2: readiness 회귀 테스트 (mandatory)**

Run:
```bash
.venv/bin/python -m pytest \
  tests/unit/test_upstream_readiness.py \
  tests/integration/test_pipeline_b_readiness.py \
  tests/integration/test_pipeline_c_readiness.py -q \
  | tee .agents/logs/verification/20260224_pipeline_state_status_readiness_regression.log
```
Expected: pass. upstream readiness 경로 회귀 없음.

**Step 3: L0 syntax check**

Run:
```bash
python -m py_compile src/common/contracts.py src/io/pipeline_state_io.py scripts/run_pipeline_a.py scripts/run_pipeline_silver.py scripts/run_pipeline_b.py scripts/run_pipeline_c.py
```
Expected: syntax error 0건.

**Step 4: L1 unit gate**

Run:
```bash
.venv/bin/python -m pytest tests/unit/ -v -x
```
Expected: unit tests pass.

**Step 5: L2 combined gate**

Run:
```bash
.venv/bin/python -m pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80
```
Expected: 전체 pass + coverage 80% 이상.

---

### Task 6: Run L3 Dev E2E And Compatibility Probe

**Files:**
- Create: `.agents/logs/verification/20260224_pipeline_state_status_l3_run.log`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_l3_poll.log`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_schema_probe.log`
- Create: `.agents/logs/verification/20260224_pipeline_state_status_ops_agent_query_probe.log`

**Step 1: L3 실행**

Run:
```bash
DATE="${DATE:-$(TZ=Asia/Seoul date -d 'yesterday' +%F)}"
RUN_ID="${RUN_ID:-pipeline_state_status_$(date -u +%Y%m%dT%H%M%SZ)}"
databricks bundle run e2e_full_pipeline -t dev --params run_mode=backfill,date_kst_start=${DATE},date_kst_end=${DATE},run_id=${RUN_ID}
```

**Step 2: L3 표준 폴링**

- 20초 간격 폴링
- 10분 타임아웃
- 실패 시 즉시 run output 수집

**Step 3: schema probe 확인**

`gold.pipeline_state`에서 아래 컬럼을 검증한다.
- `pipeline_name, status, last_success_ts, last_processed_end, last_run_id, dq_zero_window_counts, updated_at`

Expected: `status` 존재 + NULL 0건(backfill 완료 기준).

**Step 4: ops-agent query 호환성 검증 (P0 acceptance)**

Run:
```bash
CATALOG_NAME="<dev-catalog>"
WAREHOUSE_ID="<sql-warehouse-id>"
COMPAT_SQL="SELECT pipeline_name, status, last_success_ts, last_processed_end, last_run_id FROM ${CATALOG_NAME}.gold.pipeline_state WHERE pipeline_name IN ('pipeline_silver','pipeline_b','pipeline_c')"

REQ_JSON="$(jq -nc --arg statement "${COMPAT_SQL}" --arg warehouse_id "${WAREHOUSE_ID}" '{statement:$statement, warehouse_id:$warehouse_id, disposition:\"INLINE\"}')"
RESP="$(databricks api post /api/2.0/sql/statements --json "${REQ_JSON}" -o json)"
STATEMENT_ID="$(echo "${RESP}" | jq -r '.statement_id // empty')"
STATE="$(echo "${RESP}" | jq -r '.status.state // \"\"')"
while [[ "${STATE}" == "PENDING" || "${STATE}" == "RUNNING" ]]; do
  sleep 2
  RESP="$(databricks api get "/api/2.0/sql/statements/${STATEMENT_ID}" -o json)"
  STATE="$(echo "${RESP}" | jq -r '.status.state // \"\"')"
done
echo "${RESP}" | tee .agents/logs/verification/20260224_pipeline_state_status_ops_agent_query_probe.log
[[ "${STATE}" == "SUCCEEDED" ]]
echo "${RESP}" | jq -e '.result.data_array | length > 0'
echo "${RESP}" | jq -e 'all(.result.data_array[]; (.[1] == "success" or .[1] == "failure"))'
```
Expected: ops-agent가 쓰는 핵심 SELECT(`pipeline_name, status, last_success_ts, last_processed_end, last_run_id`)가 에러 없이 성공하고, `status` 값이 허용값만 반환된다.

---

### Task 7 (Final): Reflect To Specifications And Roadmap

**Files:**
- Modify: `.specs/data_contract.md`
- Modify: `.specs/project_specs.md`
- Modify: `.specs/architecture_guide.md`
- Modify: `.specs/ops/operations_runbook.md`
- Modify: `.specs/decision_open_items.md`
- Modify: `.roadmap/implementation_roadmap.md` (관련 task evidence/status만)
- Create: `.agents/logs/verification/20260224_pipeline_state_status_spec_reflection.md`

**Step 1: SSOT 문서 반영**

- `gold.pipeline_state` 컬럼 목록에 `status` 추가
- 성공/실패 갱신 규칙에 `status` 전이 명시
- triage/runbook query 예시 정합화

**Step 2: 드리프트 제거**

- `architecture_guide`의 `pipeline_state` 설명을 실제 계약과 1:1로 맞춤
- 충돌 문구 제거

**Step 3: roadmap/evidence 업데이트**

- 해당 변경의 증적 링크를 roadmap에 반영
- spec reflection 완료 증적 문서 작성

---

## Verification Evidence Contract

모든 검증 로그는 아래 경로에 저장한다.
- `.agents/logs/verification/20260224_pipeline_state_status_*.log`
- `.agents/logs/verification/20260224_pipeline_state_status_*.md`

완료 선언 조건:
- L0/L1/L2 pass 증적
- L3 run + poll + schema probe 증적
- ops-agent 호환 쿼리(pass) 증적
- Task 7 명세 반영 증적

---

## Rollout Order (Must Follow)

1. Task 1 (정책 잠금)
2. Task 2 (red tests)
3. Task 3 (코드 구현)
4. Task 4 (migration 작성 + dev apply 완료)
5. Task 5 (코드 배포 + L0/L1/L2)
6. Task 6 (L3 + 호환성 검증)
7. Task 7 (명세 반영, 마지막)

배포 순서 위반 금지:
- Task 4 migration apply 이전 Databricks 런타임 실행 금지
- migration 없이 런타임 코드 선배포 금지
- L2 실패 상태에서 L3 진행 금지
- Task 7 이전 완료 선언 금지

---

Plan complete and saved to `docs/plans/2026-02-24-pipeline-state-status-contract-alignment.md`.
