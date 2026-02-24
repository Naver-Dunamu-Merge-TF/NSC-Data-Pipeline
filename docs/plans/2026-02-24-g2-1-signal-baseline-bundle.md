# G2-1 Signal+Baseline Bundle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for per-task implementation, review, and fix loops. Use `superpowers:executing-plans` when running this plan in a separate execution session.

**Goal:** `MON-001`, `MON-002`, `GOV-001`, `GOV-002`를 단일 번들(`G2-1 Signal+Baseline`)로 완료해 모니터링 신호 연결과 운영 기준선 문서를 동시에 잠근다.

**Architecture:** 실행을 3개 레이어로 고정한다. (1) `MON-001`에서 Databricks diagnostic logs -> Log Analytics 연결 및 A/B/C 유입 증적을 확보한다. (2) `MON-002`에서 dev/prod 리소스 매핑과 명명 규칙 SSOT를 고정한다. (3) `GOV-001`, `GOV-002`에서 Current/Planned 동기화 매트릭스와 정기 증적 누적 규칙을 운영 문서에 반영한다. 모든 상태 변경은 증적 파일 생성 이후에만 허용한다.

**Tech Stack:** Azure CLI (`az monitor`, `az resource`), Databricks CLI (`databricks bundle`, `databricks jobs`), KQL(Log Analytics query), Markdown SSOT docs (`.specs/*`, `.roadmap/*`), shell verification (`rg`, `test`, `jq`).

---

## Bundle Scope Lock

| Task ID | Scope | Locked Deliverable |
|---|---|---|
| `MON-001` | Signal wiring | Databricks diagnostic logs -> Log Analytics 연결 + A/B/C 최소 리소스 매핑 스냅샷 + 유입 증적 |
| `MON-002` | Baseline mapping | dev/prod 리소스 매핑표 + 명명 규칙 표준안 확정 |
| `GOV-001` | Governance matrix | Current/Planned 동기화 매트릭스 + 월 1회 갱신 규칙 |
| `GOV-002` | Evidence baseline | `bootstrap_catalog`, `bad_records_retention_cleanup` 증적 누적 규칙 확정 |

Out of scope:
- Core 4 alert rule 생성(`MON-003`) 이후 단계
- Workbook/Action Group/game-day(`MON-004~008`)
- v2 테이블 기반 알림(`MON-009`, `GOV-007`)의 구현 확대

---

## Mandatory Subagent Loop (Implement -> Review -> Fix)

1. 구현 서브에이전트가 현재 Task 범위만 수정한다.
2. 스펙 리뷰 서브에이전트가 DoD/의존성/SSOT 정합성을 점검한다.
3. 품질 리뷰 서브에이전트가 운영 리스크(명명 일관성, 증적 재현성, 문서 드리프트)를 점검한다.
4. 이슈가 있으면 수정 서브에이전트가 최소 변경으로 보정한다.
5. 동일 리뷰를 재실행해 blocking finding이 0일 때만 다음 Task로 진행한다.
6. 부모 에이전트만 최종 증적 링크와 roadmap status를 갱신한다.

Review checklist (모든 루프 공통):
- `.roadmap/implementation_roadmap.md`의 `MON-001/002`, `GOV-001/002` DoD 충족 여부
- `.specs/ops/azure_monitoring_integration_plan.md` v1 범위 일치 여부
- `.specs/ops/operations_runbook.md` 증적 필수 항목(UTC, run_id, 명령, 결과) 충족 여부
- Decision hygiene: 신규 가정/모호점 발생 시 `.specs/decision_open_items.md` 즉시 기록

---

### Task 1: Kickoff And Dependency Freeze

**Files:**
- Read: `.roadmap/implementation_roadmap.md`
- Read: `.specs/ops/azure_monitoring_integration_plan.md`
- Read: `.specs/ops/dev_infra_resource_map.md`
- Create: `.agents/logs/verification/20260224_g2_1_signal_baseline_kickoff.md`

**Step 1: 번들 대상과 의존성 확정**

Run:
```bash
rg -n "MON-001|MON-002|GOV-001|GOV-002|SEC-008" .roadmap/implementation_roadmap.md
```
Expected: 4개 task와 `SEC-008` 선행조건이 확인된다.

**Step 2: 실행 입력값 잠금**

킥오프 문서에 아래를 기록한다.
- 환경: `dev`
- Databricks workspace/resource group
- Log Analytics workspace resource ID(미확정이면 `Blocked`로 표시)
- 담당자(Platform/Ops/DataEng)
- 번들 종료 조건(증적 4종 + roadmap 반영)

Expected: Known/Unknown/Blocked가 분리된 baseline note 1개가 생성된다.

**Step 3: Commit**

```bash
git add .agents/logs/verification/20260224_g2_1_signal_baseline_kickoff.md
git commit -m "docs: add g2-1 signal baseline kickoff"
```

---

### Task 2: Implement MON-001 (Signal Wiring + LA Ingestion Evidence)

**Files:**
- Modify: `.specs/ops/azure_monitoring_integration_plan.md`
- Create: `.agents/logs/verification/20260224_mon001_signal_wiring.md`
- Create: `.agents/logs/verification/20260224_mon001_signal_wiring.log`
- Create: `.agents/logs/verification/20260224_mon001_run_status_poll.log`
- Create: `.agents/logs/verification/20260224_mon001_la_query_results.json`

**Step 1: Databricks diagnostic settings 연결 적용**

Run:
```bash
RESOURCE_GROUP="2dt-final-team4"
WORKSPACE_NAME="nsc-dbw-dev"
DBW_RESOURCE_ID="$(az databricks workspace show -g "${RESOURCE_GROUP}" -n "${WORKSPACE_NAME}" --query id -o tsv)"
LAW_RESOURCE_ID="<infra-provided-log-analytics-resource-id>"
LAW_WORKSPACE_GUID="$(az monitor log-analytics workspace show --ids "${LAW_RESOURCE_ID}" --query customerId -o tsv)"

az monitor diagnostic-settings list --resource "${DBW_RESOURCE_ID}" -o json \
  | tee .agents/logs/verification/20260224_mon001_signal_wiring.log

az monitor diagnostic-settings create \
  --name "diag-dbw-core-dev" \
  --resource "${DBW_RESOURCE_ID}" \
  --workspace "${LAW_RESOURCE_ID}" \
  --logs '[{"categoryGroup":"allLogs","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  -o json | tee -a .agents/logs/verification/20260224_mon001_signal_wiring.log
```
Expected: diagnostic setting이 Log Analytics workspace로 연결된다.
Expected: `LAW_RESOURCE_ID`(ARM 리소스 ID)와 `LAW_WORKSPACE_GUID`(query용 GUID)가 함께 고정된다.

**Step 2: A/B/C 실행 신호 생성 및 L3 폴링**

Run:
```bash
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
KST_YESTERDAY="$(TZ=Asia/Seoul date -d 'yesterday' +%F)"
POLL_SECONDS=20
TIMEOUT_SECONDS=900
POLL_LOG=".agents/logs/verification/20260224_mon001_run_status_poll.log"

poll_run() {
  local pipeline="$1"
  local run_id="$2"
  local deadline="$(( $(date +%s) + TIMEOUT_SECONDS ))"

  while true; do
    run_json="$(databricks jobs get-run "${run_id}" -o json)"
    life_cycle_state="$(echo "${run_json}" | jq -r '.state.life_cycle_state // \"UNKNOWN\"')"
    result_state="$(echo "${run_json}" | jq -r '.state.result_state // \"\"')"
    state_message="$(echo "${run_json}" | jq -r '.state.state_message // \"\"')"

    printf '%s pipeline=%s run_id=%s state=%s/%s msg=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${pipeline}" "${run_id}" "${life_cycle_state}" "${result_state}" "${state_message}" \
      | tee -a "${POLL_LOG}"

    if [[ "${life_cycle_state}" == "TERMINATED" || "${life_cycle_state}" == "SKIPPED" || "${life_cycle_state}" == "INTERNAL_ERROR" ]]; then
      echo "${run_json}" > ".agents/logs/verification/20260224_mon001_${pipeline}_${run_id}.json"
      [[ "${life_cycle_state}" == "TERMINATED" && "${result_state}" == "SUCCESS" ]] && return 0
      return 1
    fi

    if [[ "$(date +%s)" -ge "${deadline}" ]]; then
      echo "timeout pipeline=${pipeline} run_id=${run_id}" | tee -a "${POLL_LOG}"
      return 1
    fi

    sleep "${POLL_SECONDS}"
  done
}

databricks bundle run pipeline_a_guardrail -t dev --no-wait -o json \
  --params run_mode=incremental,run_id=mon001-a-${RUN_TS} \
  | tee .agents/logs/verification/20260224_mon001_submit_pipeline_a.json
A_RUN_ID="$(jq -r '.run_id' .agents/logs/verification/20260224_mon001_submit_pipeline_a.json)"

databricks bundle run pipeline_b_controls -t dev --no-wait -o json \
  --params run_mode=backfill,date_kst_start=${KST_YESTERDAY},date_kst_end=${KST_YESTERDAY},run_id=mon001-b-${RUN_TS} \
  | tee .agents/logs/verification/20260224_mon001_submit_pipeline_b.json
B_RUN_ID="$(jq -r '.run_id' .agents/logs/verification/20260224_mon001_submit_pipeline_b.json)"

databricks bundle run pipeline_c_analytics -t dev --no-wait -o json \
  --params run_mode=backfill,date_kst_start=${KST_YESTERDAY},date_kst_end=${KST_YESTERDAY},run_id=mon001-c-${RUN_TS} \
  | tee .agents/logs/verification/20260224_mon001_submit_pipeline_c.json
C_RUN_ID="$(jq -r '.run_id' .agents/logs/verification/20260224_mon001_submit_pipeline_c.json)"

test -n "${A_RUN_ID}" && test -n "${B_RUN_ID}" && test -n "${C_RUN_ID}"
poll_run "pipeline_a_guardrail" "${A_RUN_ID}"
poll_run "pipeline_b_controls" "${B_RUN_ID}"
poll_run "pipeline_c_analytics" "${C_RUN_ID}"
```
Expected: 세 파이프라인 run_id가 증적에 저장되고, 상태 폴링 로그가 남는다.

L3 standard:
- run 상태 폴링 간격: 20초
- 각 run 타임아웃: 15분
- 실패 시 원인(run output/cluster issue)을 증적 문서에 즉시 기록

**Step 3: Log Analytics 유입 확인(KQL)**

Run:
```bash
for attempt in 1 2; do
  az monitor log-analytics query \
    --workspace "${LAW_WORKSPACE_GUID}" \
    --analytics-query "AzureDiagnostics | where TimeGenerated > ago(90m) | where ResourceProvider == \"MICROSOFT.DATABRICKS\" | summarize cnt=count() by Resource, Category" \
    --timespan PT90M \
    -o json > .agents/logs/verification/20260224_mon001_la_query_results.json

  ROW_COUNT="$(jq '.tables[0].rows | length' .agents/logs/verification/20260224_mon001_la_query_results.json)"
  [[ "${ROW_COUNT}" -gt 0 ]] && break

  sleep 60
done
```
Expected: Databricks 관련 로그 레코드가 0건 초과로 조회된다(ingestion 지연 시 1회 재시도 허용).

**Step 4: MON-001 증적 문서화**

문서에 필수 기재:
- 진단 설정 이름/대상 리소스/LAW 연결값
- A/B/C run_id 및 상태
- MON-001 최소 리소스 매핑 스냅샷(Workspace ID, LAW resource ID/GUID, A/B/C job name)
- KQL 질의/결과 요약
- 재시도/이슈/후속 조치

**Step 5: Commit**

```bash
git add .specs/ops/azure_monitoring_integration_plan.md \
  .agents/logs/verification/20260224_mon001_signal_wiring.md \
  .agents/logs/verification/20260224_mon001_signal_wiring.log \
  .agents/logs/verification/20260224_mon001_run_status_poll.log \
  .agents/logs/verification/20260224_mon001_la_query_results.json
git commit -m "feat: complete mon001 signal wiring evidence"
```

---

### Task 3: Implement MON-002 (Resource Mapping + Naming Baseline)

**Files:**
- Create: `.specs/ops/monitoring_resource_naming_baseline.md`
- Create: `.agents/logs/verification/20260224_mon002_resource_mapping.md`
- Modify: `.specs/ops/azure_monitoring_integration_plan.md`

**Step 1: dev/prod 명명 규칙 표준안 고정**

규칙 문서에 최소 포함:
- Alert rule: `{env}-dp-{pipeline}-{signal}-alert`
- Action group: `{env}-dp-{owner}-ag`
- Workbook: `{env}-dp-monitoring-v1`
- Evidence file: `YYYYMMDD_<taskid>_<artifact>.{md|log|json}`

Expected: v1 범위에서 재사용 가능한 naming grammar가 고정된다.

**Step 2: 리소스 매핑표 작성**

`MON-001` 결과 + `.specs/ops/dev_infra_resource_map.md`를 사용해 아래 매핑을 작성한다.
- Databricks workspace/resource id
- Log Analytics workspace id
- Log Analytics workspace GUID(query 전용)
- 진단 설정 이름
- 파이프라인 A/B/C job name
- alert/workbook 예정 이름

Expected: MON-001 최소 매핑이 dev/prod 기준의 확장 매핑표로 정리되고 placeholder 필드가 명시된다.

**Step 3: 모니터링 SSOT 연결**

`azure_monitoring_integration_plan.md` M1 섹션에
- `monitoring_resource_naming_baseline.md` 참조
- MON-002 산출물 경로
를 추가한다.

Expected: SSOT -> baseline 문서 링크가 양방향으로 연결된다.

**Step 4: Commit**

```bash
git add .specs/ops/monitoring_resource_naming_baseline.md \
  .agents/logs/verification/20260224_mon002_resource_mapping.md \
  .specs/ops/azure_monitoring_integration_plan.md
git commit -m "docs: lock mon002 resource mapping and naming baseline"
```

---

### Task 4: Implement GOV-001 (Current/Planned Sync Matrix)

**Files:**
- Create: `.agents/logs/verification/20260224_gov001_current_planned_matrix.md`
- Modify: `.specs/project_specs.md`

**Step 1: Current/Planned 동기화 매트릭스 작성**

매트릭스 최소 컬럼:
- Domain (`WS-SEC`, `WS-MON`, `WS-CUT`, `WS-GOV`)
- Current SSOT section
- Planned item/backlog
- Last verified date (UTC)
- Owner

Expected: 현재/계획 상태를 월 단위로 갱신 가능한 표가 생성된다.

**Step 2: 월 1회 갱신 규칙 고정**

`project_specs.md`에 다음 운영 규칙을 반영한다.
- 매월 첫 영업일 KST 기준 갱신
- 갱신 시 evidence 파일 경로를 매트릭스에 기록
- 미갱신 35일 초과 시 `Blocked`로 승격

Expected: GOV-001 DoD의 주기/담당/경로 규칙이 문서화된다.

**Step 3: Commit**

```bash
git add .agents/logs/verification/20260224_gov001_current_planned_matrix.md \
  .specs/project_specs.md
git commit -m "docs: lock gov001 current planned sync matrix policy"
```

---

### Task 5: Implement GOV-002 (Ops Evidence Accumulation Baseline)

**Files:**
- Modify: `.specs/ops/operations_runbook.md`
- Create: `.agents/logs/verification/20260224_gov002_ops_evidence_baseline.md`
- Create: `.agents/logs/verification/templates/ops_job_evidence_template.md`

**Step 1: 증적 누적 대상과 규칙 확정**

대상 job:
- `bootstrap_catalog`
- `bad_records_retention_cleanup`

규칙:
- 파일명: `YYYYMMDD_<job>_<env>_<run_id>.md`
- 최소 필드: UTC, 실행자, 파라미터, run_id, 결과, 후속 액션
- 월별 인덱스 파일로 링크 집계

Expected: 정기 증적 누적 규칙이 runbook 기준선으로 고정된다.

**Step 2: runbook에 누적 운영 절차 추가**

`operations_runbook.md` Evidence 섹션에 추가:
- 누적 주기(월 1회 정기 + 수동 실행 시 즉시)
- 누락 대응(SLA 초과 시 온콜 알림)
- 템플릿 경로(`templates/ops_job_evidence_template.md`)

Expected: GOV-002 DoD(네이밍 규칙 + 증적 목록 + runbook 반영) 충족.

**Step 3: Commit**

```bash
git add .specs/ops/operations_runbook.md \
  .agents/logs/verification/20260224_gov002_ops_evidence_baseline.md \
  .agents/logs/verification/templates/ops_job_evidence_template.md
git commit -m "docs: establish gov002 operations evidence accumulation baseline"
```

---

### Task 6: Roadmap Sync + Final Verification

**Files:**
- Modify: `.roadmap/implementation_roadmap.md`
- Update (if needed): `.specs/decision_open_items.md`
- Create: `.agents/logs/verification/20260224_g2_1_signal_baseline_signoff.md`

**Step 1: roadmap 상태/증적 경로 동기화**

변경 대상:
- `MON-001`, `MON-002`, `GOV-001`, `GOV-002`
- `status`, `evidence_path`, 세부 태스크 문구

Expected: 실제 생성된 증적 파일 경로와 roadmap이 1:1로 일치한다.

**Step 2: 결정 위생 점검**

Run:
```bash
rg -n "TODO|TBD|가정|assumption|Blocked" \
  .specs/ops/azure_monitoring_integration_plan.md \
  .specs/ops/operations_runbook.md \
  .specs/project_specs.md \
  .roadmap/implementation_roadmap.md
```
Expected: 남는 가정이 있으면 `.specs/decision_open_items.md`에 신규 decision 항목을 추가한다.

**Step 3: 증적 무결성 확인**

Run:
```bash
test -f .agents/logs/verification/20260224_mon001_signal_wiring.md
test -f .agents/logs/verification/20260224_mon002_resource_mapping.md
test -f .agents/logs/verification/20260224_gov001_current_planned_matrix.md
test -f .agents/logs/verification/20260224_gov002_ops_evidence_baseline.md
rg -n "MON-001|MON-002|GOV-001|GOV-002" .roadmap/implementation_roadmap.md
```
Expected: 필수 증적 파일 4종 존재 + roadmap 반영 완료.

**Step 4: Commit**

```bash
git add .roadmap/implementation_roadmap.md \
  .specs/decision_open_items.md \
  .agents/logs/verification/20260224_g2_1_signal_baseline_signoff.md
git commit -m "docs: synchronize roadmap after g2-1 signal baseline bundle"
```

---

## Verification Contract For This Bundle

- `MON-001`: L3 (실행 신호 + Log Analytics 유입 증적 필수)
- `MON-002`: L1 (문서/매핑 검증)
- `GOV-001`: L1 (문서/매트릭스 검증)
- `GOV-002`: L1 (runbook/템플릿 검증)

L3 execution standard (MON-001):
- Poll interval: 20 seconds
- Timeout: 15 minutes (900 seconds)

Documentation-only checks (every task close):
```bash
rg -n "MON-001|MON-002|GOV-001|GOV-002|Log Analytics|증적" \
  .roadmap/implementation_roadmap.md \
  .specs/ops/azure_monitoring_integration_plan.md \
  .specs/ops/operations_runbook.md \
  .specs/project_specs.md
```

Acceptance gate:
1. LA 유입 확인 결과가 문서+로그(JSON 포함)로 재현 가능하다.
2. 리소스/명명 규칙이 SSOT 문서에 고정되어 재사용 가능하다.
3. 증적 누적 규칙이 runbook에 반영되고 템플릿까지 준비된다.
4. roadmap task 상태와 증적 경로가 실제 산출물과 일치한다.
