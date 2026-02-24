# G2-2 Core4 Alert Go-Live Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for per-task implementation, review, and fix loops. Use `superpowers:executing-plans` when running this plan in a separate execution session.

**Goal:** `MON-003`, `MON-004`, `MON-005`를 단일 번들(`G2-2 Core4 Alert Go-Live`)로 완료해 Core4 Alert 4종을 운영 발화 가능한 상태로 go-live 한다.

**Architecture:** 구현 순서를 `규칙 생성(MON-003) -> Action Group 라우팅(MON-004) -> 테스트 경보 발화/수신(MON-005)`로 고정한다. 각 단계는 전 단계 증적이 없으면 다음 단계로 넘어가지 않는다. 번들 종료는 Core4 4종 `enabled=true`, 라우팅 바인딩 확인, 테스트 경보 1회 수신 증적이 모두 확보될 때만 허용한다.

**Tech Stack:** Azure CLI (`az extension`, `az monitor scheduled-query`, `az monitor action-group`), KQL(Log Analytics), shell scripts (`scripts/ops/monitoring/*`), SSOT docs (`.specs/*`, `.roadmap/*`), evidence logs (`.agents/logs/verification/*`).

---

## Bundle Scope Lock

| Bundle | Linked Tasks | Bundle Intent | Done When |
|---|---|---|---|
| `G2-2 Core4 Alert Go-Live` | `MON-003`, `MON-004`, `MON-005` | Core4 알림은 규칙/라우팅/발화 테스트를 한 세트로 완료한다 | Core4 4종 활성 + Action Group 라우팅 + 테스트 경보 수신 1회 |

In scope:
- `MON-003`: Core Execution Alert 4종 생성/활성화
- `MON-004`: Severity + Owner Action Group 라우팅 연결
- `MON-005`: 테스트 알람 1회 발화 및 실제 수신 확인

Out of scope:
- Workbook 작업(`MON-006`)
- Runbook 링크 최종 반영(`MON-007`)
- game-day 루틴(`MON-008`)
- v2 테이블 기반 알림(`MON-009`, `GOV-007`)

---

## Decision Lock (2026-02-24)

1. Core4 규칙 카디널리티는 **정확히 4개**로 고정한다(옵션 1).
   - `dev-dp-pipeline-a-job-failure-alert`
   - `dev-dp-pipeline-a-success-delay-alert`
   - `dev-dp-pipeline-b-retry-exhausted-alert`
   - `dev-dp-pipeline-c-cluster-timeout-alert`
2. `scheduled-query` preview extension 사용을 허용하고 버전을 고정한다(옵션 1).
   - required version: `1.0.0b2`
   - preflight에서 설치/버전 검증 실패 시 `MON-003`을 즉시 `Blocked` 처리한다.

---

## Review Findings (Severity-Ordered, 2026-02-24)

| Severity | Finding | Plan Reflection | Status |
|---|---|---|---|
| High | `scheduled-query` CLI 선행조건/버전 고정 누락 시 실행 즉시 실패 가능 | Task 1 Step 3에 extension preflight(`--allow-preview true`) + version pin(`1.0.0b2`) + mismatch fail-fast를 추가 | Closed |
| Medium | Tech Stack에 비유효 명령(`az monitor alert`) 포함 | Tech Stack 명령 집합을 `az extension`, `az monitor scheduled-query`, `az monitor action-group`으로 정정 | Closed |
| Medium | MON-003 활성 검증이 광역 list 기반이라 false pass 가능 | Task 2 Step 3을 Core4 규칙명 4개 고정 검증(`show` + `enabled=true` assert)으로 변경 | Closed |
| Medium | MON-004 라우팅 검증이 출력만 있고 실패 조건 부재 | Task 3 Step 3에 expected/actual Action Group ID 비교 및 불일치 시 실패 처리 추가 | Closed |
| Low | 신규 shell script 문법(L0) 검증 누락 | Verification Contract에 `bash -n scripts/ops/monitoring/*.sh` 선행 검증 추가 | Closed |

---

## Mandatory Subagent Loop (Implement -> Review -> Fix)

1. 구현 서브에이전트가 현재 Task 범위만 수정/실행한다.
2. 스펙 리뷰 서브에이전트가 `.specs/ops/azure_monitoring_integration_plan.md`, `.specs/ops/operations_runbook.md`, `.roadmap/implementation_roadmap.md` 정합성을 검증한다.
3. 운영 리뷰 서브에이전트가 라우팅 누락, 노이즈 임계치, 증적 재현성 리스크를 점검한다.
4. blocking finding이 있으면 수정 서브에이전트가 최소 변경으로 보정한다.
5. 동일 리뷰를 재실행해 blocking finding이 0일 때만 다음 Task로 진행한다.
6. 부모 에이전트만 roadmap 상태/증적 경로를 최종 갱신한다.

공통 리뷰 체크리스트:
- Core4 4종이 v1 SSOT 범위(실패/지연/재시도 소진/클러스터 실패)에 정확히 매핑되는가
- Action Group 라우팅이 Severity + Owner 정책과 일치하는가
- 테스트 발화 증적이 "규칙 발화"와 "수신 채널 도착"을 모두 포함하는가
- 신규 가정/모호점은 `.specs/decision_open_items.md`에 즉시 기록되는가

---

### Task 1: Kickoff And Input Freeze

**Files:**
- Read: `.roadmap/implementation_roadmap.md`
- Read: `.specs/ops/azure_monitoring_integration_plan.md`
- Read: `.specs/ops/operations_runbook.md`
- Read: `.specs/ops/monitoring_resource_naming_baseline.md`
- Modify (if needed): `.specs/decision_open_items.md`
- Create: `.agents/logs/verification/20260224_g2_2_core4_kickoff.md`
- Create: `.agents/logs/verification/20260224_mon003_cli_prereq.log`

**Step 1: 번들 대상/DoD 잠금**

Run:
```bash
rg -n "G2-2|MON-003|MON-004|MON-005|Core Execution Alerts|Action Group" \
  .roadmap/implementation_roadmap.md \
  .specs/ops/azure_monitoring_integration_plan.md \
  .specs/ops/operations_runbook.md
```
Expected: `MON-003~005` 요구사항과 Core4 정책이 동일하게 확인된다.

**Step 2: 실행 입력값/규칙명 고정**

킥오프 문서에 다음 값을 고정한다.
- `ENV` (`dev`)
- `RESOURCE_GROUP`
- `DBW_RESOURCE_ID`
- `LAW_RESOURCE_ID`, `LAW_GUID`
- Action Group 후보(`platform`, `ops`)
- Core4 규칙명 4개(Decision Lock 기준)
- 번들 종료 조건(4종 enabled + routing + test receipt)

**Step 3: CLI 선행조건 검증(`scheduled-query` preview + version pin)**

Run:
```bash
REQUIRED_SQ_EXT_VERSION="1.0.0b2"

az extension add --name scheduled-query --allow-preview true \
  | tee .agents/logs/verification/20260224_mon003_cli_prereq.log

SQ_EXT_VERSION="$(az extension show --name scheduled-query --query version -o tsv)"
echo "scheduled-query version=${SQ_EXT_VERSION}" \
  | tee -a .agents/logs/verification/20260224_mon003_cli_prereq.log

test "${SQ_EXT_VERSION}" = "${REQUIRED_SQ_EXT_VERSION}"
```
Expected: `scheduled-query`가 설치되고 버전이 `1.0.0b2`와 일치한다.

**Step 4: Decision hygiene**

Action Group 수신자/채널 또는 severity 매핑이 불명확하면 `.specs/decision_open_items.md`에 open item을 추가한다.

---

### Task 2: Implement MON-003 (Core4 Rule Provisioning)

**Files:**
- Create: `scripts/ops/monitoring/create_core4_alert_rules.sh`
- Create: `scripts/ops/monitoring/kql/core4_job_failure.kql`
- Create: `scripts/ops/monitoring/kql/core4_success_delay.kql`
- Create: `scripts/ops/monitoring/kql/core4_retry_exhausted.kql`
- Create: `scripts/ops/monitoring/kql/core4_cluster_start_timeout.kql`
- Create: `.agents/logs/verification/20260224_mon003_core4_alerts.log`
- Create: `.agents/logs/verification/20260224_mon003_core4_alerts.md`

**Step 1: Core4 KQL/규칙 템플릿 작성**

원칙:
- v1 범위 외 지표(`dq_status`, `exception_ledger`, `pipeline_state` row 기반 알림)는 포함하지 않는다.
- 명명은 `.specs/ops/monitoring_resource_naming_baseline.md` 패턴을 따른다.
- Core4는 규칙 4개만 운영한다(추가 규칙 생성은 out of scope).

**Step 2: 규칙 4종 생성/업데이트 실행**

Run:
```bash
ENV=dev
RG="<resource-group>"
DBW_RESOURCE_ID="<databricks-workspace-resource-id>"
LAW_RESOURCE_ID="<log-analytics-resource-id>"
LAW_GUID="<log-analytics-workspace-guid>"

bash scripts/ops/monitoring/create_core4_alert_rules.sh \
  --env "${ENV}" \
  --resource-group "${RG}" \
  --dbw-resource-id "${DBW_RESOURCE_ID}" \
  --law-resource-id "${LAW_RESOURCE_ID}" \
  --law-guid "${LAW_GUID}" \
  | tee .agents/logs/verification/20260224_mon003_core4_alerts.log
```
Expected: Core4 alert rule 4개가 생성 또는 업데이트된다.

**Step 3: 활성 상태 검증**

Run:
```bash
CORE4_RULES=(
  "${ENV}-dp-pipeline-a-job-failure-alert"
  "${ENV}-dp-pipeline-a-success-delay-alert"
  "${ENV}-dp-pipeline-b-retry-exhausted-alert"
  "${ENV}-dp-pipeline-c-cluster-timeout-alert"
)

for RULE in "${CORE4_RULES[@]}"; do
  ENABLED="$(az monitor scheduled-query show -g "${RG}" -n "${RULE}" --query enabled -o tsv)"
  echo "rule=${RULE} enabled=${ENABLED}" | tee -a .agents/logs/verification/20260224_mon003_core4_alerts.log
  test "${ENABLED}" = "true"
done
```
Expected: Core4 4개 규칙이 모두 조회되고 `enabled=true` 검증을 통과한다.

---

### Task 3: Implement MON-004 (Action Group Routing)

**Files:**
- Create: `scripts/ops/monitoring/bind_core4_action_groups.sh`
- Modify: `.specs/ops/operations_runbook.md`
- Create: `.agents/logs/verification/20260224_mon004_action_group_binding.log`
- Create: `.agents/logs/verification/20260224_mon004_action_group_binding.md`

**Step 1: 라우팅 매핑 테이블 확정**

런북에 아래를 명시한다.
- Alert rule -> Severity -> Owner -> Action Group
- dev/prod 채널 강도 차등 원칙

**Step 2: Action Group 바인딩 적용**

Run:
```bash
ENV=dev
RG="<resource-group>"
PLATFORM_AG_ID="<action-group-id-platform>"
OPS_AG_ID="<action-group-id-ops>"

bash scripts/ops/monitoring/bind_core4_action_groups.sh \
  --env "${ENV}" \
  --resource-group "${RG}" \
  --platform-action-group-id "${PLATFORM_AG_ID}" \
  --ops-action-group-id "${OPS_AG_ID}" \
  | tee .agents/logs/verification/20260224_mon004_action_group_binding.log
```
Expected: Core4 4개 규칙의 `actions`가 정책대로 연결된다.

**Step 3: 규칙별 라우팅 검증**

Run:
```bash
CORE4_RULES=(
  "${ENV}-dp-pipeline-a-job-failure-alert"
  "${ENV}-dp-pipeline-a-success-delay-alert"
  "${ENV}-dp-pipeline-b-retry-exhausted-alert"
  "${ENV}-dp-pipeline-c-cluster-timeout-alert"
)

for RULE in "${CORE4_RULES[@]}"; do
  case "${RULE}" in
    *"job-failure-alert"|*"cluster-timeout-alert") EXPECTED_AG_ID="${PLATFORM_AG_ID}" ;;
    *) EXPECTED_AG_ID="${OPS_AG_ID}" ;;
  esac

  ACTUAL_AG_IDS="$(az monitor scheduled-query show -g "${RG}" -n "${RULE}" --query "actions.actionGroups[].actionGroupId" -o tsv)"
  echo "rule=${RULE} expected_ag=${EXPECTED_AG_ID} actual_ag=${ACTUAL_AG_IDS}" \
    | tee -a .agents/logs/verification/20260224_mon004_action_group_binding.log
  echo "${ACTUAL_AG_IDS}" | rg -q "${EXPECTED_AG_ID}"
done
```
Expected: 각 규칙이 예상 Action Group ID를 포함하며, 불일치 시 즉시 실패한다.

---

### Task 4: Implement MON-005 (Test Fire And Receipt)

**Files:**
- Create: `scripts/ops/monitoring/fire_core4_test_alert.sh`
- Create: `.agents/logs/verification/20260224_mon005_test_alert_fire.log`
- Create: `.agents/logs/verification/20260224_mon005_test_alert_fire.md`

**Step 1: 테스트 발화 시나리오 실행**

Run:
```bash
ENV=dev
RG="<resource-group>"

bash scripts/ops/monitoring/fire_core4_test_alert.sh \
  --env "${ENV}" \
  --resource-group "${RG}" \
  --poll-interval-sec 20 \
  --timeout-sec 600 \
  | tee .agents/logs/verification/20260224_mon005_test_alert_fire.log
```
Expected: 테스트용 또는 저노이즈 시나리오 기반 alert 1회가 실제 `Fired` 상태로 관측된다.

L3 polling standard:
- 20초 간격으로 alert state를 조회한다.
- 10분 내 미발화 시 실패로 처리한다.

**Step 2: 수신 채널 도착 확인**

필수 기록:
- 수신 시각(UTC/KST)
- 수신 채널(email/webhook/teams 등)
- alert rule 이름/심각도/incident ID

Expected: Action Group 수신 증적 1건 이상 확보.

**Step 3: 테스트 후 정리**

임시 테스트 규칙/임계치 완화가 있다면 원복하고 원복 로그를 증적에 남긴다.

---

### Task 5: Bundle Closure And Roadmap Sync

**Files:**
- Modify: `.roadmap/implementation_roadmap.md`
- Create: `.agents/logs/verification/20260224_g2_2_core4_alert_go_live_signoff.md`

**Step 1: roadmap 상태 갱신**

갱신 항목:
- `MON-003`, `MON-004`, `MON-005` status -> `Done`
- `evidence_path`를 실제 생성 파일로 교체
- `2.4 G2 execution bundle status`에 `G2-2` 행 추가 또는 갱신

**Step 2: 증적 존재성 검증**

Run:
```bash
rg -n "G2-2|MON-003|MON-004|MON-005|20260224_mon003|20260224_mon004|20260224_mon005" \
  .roadmap/implementation_roadmap.md

test -f .agents/logs/verification/20260224_mon003_core4_alerts.log
test -f .agents/logs/verification/20260224_mon004_action_group_binding.log
test -f .agents/logs/verification/20260224_mon005_test_alert_fire.log
```
Expected: roadmap와 증적 파일 경로가 일치한다.

**Step 3: Signoff 문서 고정**

`20260224_g2_2_core4_alert_go_live_signoff.md`에 다음을 남긴다.
- Core4 4종 enabled 증적
- 라우팅 매핑 증적
- 테스트 발화/수신 증적
- 잔여 리스크(`MON-006~008`, v2 backlog) 명시

---

## Verification Contract For This Bundle

- L0: 신규 shell script 문법 검증을 선행한다.
  - `bash -n scripts/ops/monitoring/create_core4_alert_rules.sh`
  - `bash -n scripts/ops/monitoring/bind_core4_action_groups.sh`
  - `bash -n scripts/ops/monitoring/fire_core4_test_alert.sh`
- Minimum verification level: `L3` (`MON-003~005` 모두 L3)
- L3 표준: 상태 폴링 20초 간격, 타임아웃 10분
- Retry 정책: transient error에 한해 최대 2회, 5분 간격
- 증적 저장 경로: `.agents/logs/verification/`
- 문서/로드맵 정합성 검증 명령은 각 Task 종료 시 필수로 실행
