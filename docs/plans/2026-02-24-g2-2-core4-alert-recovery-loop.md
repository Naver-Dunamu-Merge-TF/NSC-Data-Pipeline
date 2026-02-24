# G2-2 Core4 Alert Recovery Plan (MON-003 -> MON-004 -> MON-005)

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for per-task implementation, review, and fix loops. Use `superpowers:executing-plans` when running this plan in a separate execution session.

**Goal:** 발화가 되지 않는 Core4 룰 계열을 교정해 `MON-003(재생성) -> MON-004(재확인/재바인딩) -> MON-005(재발화/수신)`을 완료한다.

**Root-Cause Context:** 기존 Core4 룰은 생성/활성/바인딩은 성공했으나 AlertsManagement 기준 발화 증적이 0건이다. 동일 RG의 발화 이력이 있는 룰과 비교 시 `createdWithApiVersion` 계열 차이가 확인됐으므로, MON-003 재생성 시 생성 경로를 교정해야 한다.

**Architecture:** 순서를 고정한다.
1. `MON-003` 재생성: Core4 4개를 교정된 생성 경로로 재생성
2. `MON-004` 확인: Action Group 바인딩 재적용/검증
3. `MON-005` 재발화: Fired + 실제 수신 채널 도착 증적 확보

각 단계는 전 단계 증적이 없으면 다음 단계 진행 금지.

---

## Bundle Scope Lock

| Bundle | Linked Tasks | Intent | Done When |
|---|---|---|---|
| `G2-2 Core4 Alert Recovery` | `MON-003`, `MON-004`, `MON-005` | 발화 불능 계열 교정 후 운영 발화 증적 복구 | Core4 4개 교정 + 라우팅 일치 + Fired 1건 + 수신 1건 |

In scope:
- `MON-003`: Core4 4개 재생성(생성 경로 교정)
- `MON-004`: Action Group 라우팅 재검증/재바인딩
- `MON-005`: 테스트 발화 + 수신 확인

Out of scope:
- Workbook/game-day/v2 table alert

---

## Decision Lock (Recovery)

1. Core4 카디널리티는 여전히 정확히 4개로 고정한다.
2. MON-003 재생성은 발화 이력이 있는 계열과 동등한 생성 방식으로 수행한다.
   - 최소 검증 포인트:
     - `createdWithApiVersion=2022-06-15` 확인
     - `enabled=true`
     - scope/location/evaluation/window/action payload 정상
3. MON-005는 20초 폴링, 10분 타임아웃 표준을 유지한다.
4. D-052 preflight를 recovery에서도 동일 강도로 적용한다.
   - required extension version: `1.0.0b2`
   - mismatch 시 즉시 `Blocked`

### Preflight Gate (D-052)

Run:
```bash
REQUIRED_SQ_EXT_VERSION="1.0.0b2"

az extension add --name scheduled-query --allow-preview true \
  | tee .agents/logs/verification/20260224_mon003_cli_prereq_recovery.log

SQ_EXT_VERSION="$(az extension show --name scheduled-query --query version -o tsv)"
echo "scheduled-query version=${SQ_EXT_VERSION}" \
  | tee -a .agents/logs/verification/20260224_mon003_cli_prereq_recovery.log

test "${SQ_EXT_VERSION}" = "${REQUIRED_SQ_EXT_VERSION}"
```
Expected: extension version이 `1.0.0b2`와 일치한다.

---

## Mandatory Subagent Loop (Implement -> Review -> Fix)

각 Task는 반드시 아래 루프를 적용한다.

1. **구현 서브에이전트**: 해당 Task 범위 코드/스크립트/실행만 담당
2. **스펙 리뷰 서브에이전트**: `.specs/ops/azure_monitoring_integration_plan.md`, `.specs/ops/operations_runbook.md`, `.roadmap/implementation_roadmap.md` 정합성 검증
3. **운영/품질 리뷰 서브에이전트**: 발화 재현성, 라우팅 누락, 원복 누락 리스크 점검
4. blocking finding 존재 시 **수정 서브에이전트**가 최소 변경으로 보정
5. 동일 리뷰 재실행 후 blocking finding 0일 때만 다음 Task로 진행
6. 부모 에이전트만 roadmap 상태/증적 경로를 최종 갱신

공통 체크리스트:
- Core4 4종 범위/명명 고정 준수
- Severity + Owner 라우팅 일치
- Fired 증적 + 수신 증적 동시 확보
- 임시 완화/디버그 변경사항 원복 증적 필수

---

## Task 1: Recovery Kickoff + Baseline Capture

**Files:**
- Create: `.agents/logs/verification/20260224_g2_2_core4_recovery_kickoff.md`
- Create: `.agents/logs/verification/20260224_g2_2_core4_before_snapshot.json`
- Create: `.agents/logs/verification/20260224_mon003_cli_prereq_recovery.log`

**Steps:**
1. D-052 preflight 실행 및 로그 고정
2. Core4 4개 현재 상태 스냅샷 수집 (`show` 결과 전체)
3. 기존 발화 불가 증적(AlertsManagement 0건)을 킥오프 문서에 잠금
4. 실행 입력값(RG/LAW/AG IDs/규칙명 4개) 고정

---

## Task 2: MON-003 Regenerate Core4 Rules

**Files:**
- Modify/Create: `scripts/ops/monitoring/create_core4_alert_rules.sh`
- Create: `.agents/logs/verification/20260224_mon003_core4_rules_before_recreate.json`
- Create: `.agents/logs/verification/20260224_mon003_core4_alerts_recreate.log`
- Create: `.agents/logs/verification/20260224_mon003_core4_alerts_recreate.md`

**Steps:**
1. 재생성 로직 구현
   - 기존 Core4 4개 정의를 `.agents/logs/verification/20260224_mon003_core4_rules_before_recreate.json`에 백업 후 교정 경로로 재생성
   - idempotent 보장
2. 재생성 실행
3. 필수 검증
   - 4개 규칙 모두 조회 가능
   - `enabled=true`
   - `createdWithApiVersion=2022-06-15`
   - 핵심 속성(scope/location/evaluation/window/actions) 기대치와 일치

**Fail-fast:**
- 4개 중 1개라도 검증 실패 시 MON-003 `Blocked`
- 4개 중 1개라도 `createdWithApiVersion != 2022-06-15`면 즉시 `Blocked`

---

## Task 3: MON-004 Re-bind / Verify Action Groups

**Files:**
- Modify/Create: `scripts/ops/monitoring/bind_core4_action_groups.sh`
- Create: `.agents/logs/verification/20260224_mon004_action_group_binding_recheck.log`
- Create: `.agents/logs/verification/20260224_mon004_action_group_binding_recheck.md`

**Steps:**
1. Core4 4개에 정책 매핑 재적용
   - platform: `job-failure`, `cluster-timeout`
   - ops: `success-delay`, `retry-exhausted`
2. expected/actual AG ID 비교 검증
3. 불일치 즉시 실패 처리

---

## Task 4: MON-005 Re-fire + Receipt Proof

**Files:**
- Modify/Create: `scripts/ops/monitoring/fire_core4_test_alert.sh`
- Create: `.agents/logs/verification/20260224_mon005_test_alert_refire.log`
- Create: `.agents/logs/verification/20260224_mon005_test_alert_refire.md`

**Steps:**
1. 재발화 실행 (20초 폴링, 10분 timeout)
2. Fired 증적 확보
   - alert rule id/name
   - monitorCondition=`Fired`
   - start time
3. 수신 채널 도착 증적 확보
   - 수신 시각(UTC/KST)
   - 채널(email/webhook/teams)
   - severity / incident id
4. 테스트용 임시 완화가 있으면 원복 + 원복 로그 남김

**Fail-fast:**
- Fired 미관측 또는 수신 증적 미확보 시 MON-005 `Blocked`

---

## Task 5: Closure Sync

**Files:**
- Modify: `.roadmap/implementation_roadmap.md`
- Create: `.agents/logs/verification/20260224_g2_2_core4_recovery_signoff.md`

**Steps:**
1. `MON-003~005` 상태/증적 경로 반영
2. G2-2 bundle 상태 갱신
3. Signoff 문서에 다음 고정
   - 재생성 검증 결과
   - 라우팅 검증 결과
   - Fired/수신 증적
   - 잔여 리스크

---

## Verification Contract (Recovery)

- L0 (선행):
  - `bash -n scripts/ops/monitoring/create_core4_alert_rules.sh`
  - `bash -n scripts/ops/monitoring/bind_core4_action_groups.sh`
  - `bash -n scripts/ops/monitoring/fire_core4_test_alert.sh`
- D-052 preflight (선행):
  - `az extension add --name scheduled-query --allow-preview true`
  - `az extension show --name scheduled-query --query version -o tsv`
  - expected: `1.0.0b2`
- Minimum level: `L3` (`MON-003~005`)
- L3 standard:
  - poll interval `20s`
  - timeout `10m`
- 증적 저장 경로: `.agents/logs/verification/`
- 완료 주장 전, 증적 파일 존재 + roadmap 반영 검증 필수
