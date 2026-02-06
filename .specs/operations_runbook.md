# Operations Runbook (Pipeline A/B/C)

Last updated: 2026-02-06

## 1. Scope

- Pipeline A (Guardrail DQ)
- Pipeline B (Ledger/Admin controls)
- Pipeline C (Analytics anonymized mart)
- 공통 상태 테이블: `gold.pipeline_state`
- 공통 예외 테이블: `gold.exception_ledger`

## 2. Alert Policy

1. 기본 알림 트리거:
- `gold.exception_ledger.severity = CRITICAL`

2. 억제 규칙:
- Pipeline A의 `SOURCE_STALE` 또는 `EVENT_DROP_SUSPECTED`가 존재하면 Pipeline B/C의 CRITICAL은 운영 알림을 억제할 수 있다.

3. 재시도:
- Workflows 재시도 2회, 간격 5분

4. 채널:
- 현재 dev: Email
- secure 재구축 후: Slack + Email

## 3. Incident Triage

1. `gold.exception_ledger`에서 최신 CRITICAL 확인
2. `gold.pipeline_state`에서 대상 파이프라인의 `last_success_ts`, `last_processed_end`, `last_run_id` 확인
3. 원인 분류:
- 데이터 품질/계약 위반
- 권한/시크릿/네트워크
- 리소스(클러스터 시작 실패, 타임아웃)

## 4. Recovery Playbook

### 4.1 Pipeline A 실패

1. Bronze 소스 최신성/필수 컬럼 확인
2. `bad_records_rate` 초과 여부 확인
3. 실패 원인 해소 후 동일 윈도우 재실행

### 4.2 Pipeline B 실패

1. `silver.wallet_snapshot`, `silver.ledger_entries` 대상 `date_kst` 데이터 존재 확인
2. 룰 테이블(`gold.dim_rule_scd2`) drift/supply 임계치 확인
3. 대상 `date_kst` 범위 backfill 재실행

### 4.3 Pipeline C 실패

1. Secret Scope (`ledger-analytics-dev/salt_user_key`) 접근 확인
2. `silver.order_events/order_items/products` 조인 키 품질 확인
3. 대상 `date_kst` 파티션 재실행(파티션 overwrite)

## 5. Escalation

1. 2회 재시도 후 실패 지속
2. 핵심 Gold 테이블 미생성 상태가 30분 이상 지속
3. 데이터 누락/중복이 운영 허용치 초과

## 6. Evidence

- 검증/조치 로그: `.agents/logs/verification/`
- E2E 증적 템플릿: `.agents/logs/verification/templates/e2e_evidence_template.md`
