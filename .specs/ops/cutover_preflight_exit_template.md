# Cutover Preflight / Exit Criteria Template

Last updated: 2026-02-25  
Reference: `.specs/cloud/cloud_migration_rebuild_plan.md`

## 1. Cutover Metadata

- `T_cutover_utc`:
- Operator:
- Source env:
- Target env:
- Change window:

## 1.1 Gate Interpretation

- `G1-Run` (운영가동): A/Silver/B/C 서버리스 실행 가능 + staged smoke 수렴.
- `G1-Sec` (보안완결): `SEC-003` external location L3 + `SEC-007` cadence 종료.
- 최종 `G1` 서명은 `G1-Run`과 `G1-Sec` 동시 충족 시에만 가능.
- `G1-Sec` 미충족 상태에서는 조건부 승인 범위/철회 조건을 명시해야 한다.

## 2. Preflight Checklist

- [ ] `G1-Run` 기준 증적(SEC-005 staged smoke PASS) 확인
- [ ] `G1-Sec` 미충족 항목(`SEC-003`, SEC-007 cadence)과 조건부 승인 범위 기록
- [ ] 구독/RG/워크스페이스/스토리지 이름 재확인
- [ ] UC 권한(`USE CATALOG`, `USE SCHEMA`, `SELECT`, `MODIFY`) 검증
- [ ] Secret 주입 상태(`salt`, 토큰) 검증
- [ ] SEC binding window(`sec003_sec004_binding_window.sh`) 실행 계획/파라미터 확정 (`G1-Sec` 항목)
- [ ] 서버리스 SEC 검증 job(`sec_access_secret_binding_window`) 배포 및 Job ID 확인 (`G1-Sec` 항목)
- [ ] SEC L3 검증 스크립트(`verify_sec003_sec004_l3.sh`) 폴링(20s)/타임아웃(10m) 기준 확인 (`G1-Sec` 항목)
- [ ] 파이프라인 파라미터(`run_mode`, `start_ts`, `end_ts`, `run_id`) 확정
- [ ] 기존 Workflows 정지/재개 순서 확정
- [ ] Bootstrap job(`bootstrap_catalog`) 배포 완료 확인
- [ ] `sync_dim_rule_scd2` job 배포 + 실행 경로 확인
- [ ] `pipeline_silver_materialization` job 배포 + 스케줄/의존성 확인
- [ ] `gold.dim_rule_scd2` row 수/`is_current` 유효성(동일 domain+metric당 1건) 검증
- [ ] Pipeline B 동일 `run_id` 재실행 검증 계획 수립(`exception_ledger` 6-key 기준)
- [ ] 모니터링 범위 확인(`v1 Core 4` 활성, table-based alert 비활성)

## 3. Execution Checklist

- [ ] 신규 환경 인프라/UC 준비 완료
- [ ] `bootstrap_catalog` 실행: 3 스키마 + 23 계약 테이블 생성 확인
- [ ] `sync_dim_rule_scd2` 실행: `gold.dim_rule_scd2` 최신 seed 반영 확인
- [ ] Pipeline A backfill 실행
- [ ] Pipeline Silver backfill 실행
- [ ] Pipeline B/C backfill 실행
- [ ] `T_cutover_utc` 이후 incremental 전환
- [ ] 기존 환경 Workflows 중지
- [ ] 신규 환경 Workflows 활성화

## 4. Exit Criteria

| Stage | Exit Criteria | Status | Notes |
|---|---|---|---|
| Infra/UC (Run) | UC managed table 경로 접근 성공 + A/Silver/B/C 실행 가능 |  |  |
| Pipeline A | `silver.dq_status` 생성, CRITICAL 급증 없음 |  |  |
| Pipeline Silver | `silver.wallet_snapshot/ledger_entries/order_events/order_items/products` 생성 + `silver.bad_records` 적재/검증 완료 |  |  |
| Pipeline B/C | Gold 핵심 테이블 생성 완료 |  |  |
| Rule SSOT | `gold.dim_rule_scd2` 존재 + current rule 유효성 통과 |  |  |
| SEC-003 (G1-Sec) | 서버리스에서 UC ACL + external location R/W 검증 성공 |  |  |
| SEC-004 | KV-backed secret scope read + backend=`AZURE_KEYVAULT` 검증 성공(회전 full 검증은 후속 사이클) |  |  |
| Pipeline B Rerun | 동일 `run_id` 재실행 성공 + `exception_ledger` 6-key 중복 0건 |  |  |
| Incremental | `T_cutover_utc` 이후 누락/중복 없음 |  |  |
| State | `gold.pipeline_state.last_run_id` 최신 반영 |  |  |
| Monitoring | `v1 Core 4` 경보 규칙 활성 + table-based alert 비활성 확인 |  |  |
| G1 Final Signoff | `G1-Run` + `G1-Sec` 동시 충족 |  |  |

## 5. Rollback Trigger

- [ ] 연속 CRITICAL로 B/C 게이팅 지속
- [ ] Gold 핵심 테이블 미생성/갱신 실패
- [ ] 누락/중복이 허용 기준 초과

## 6. Evidence Links

- Verification logs:
- Query evidence:
- Incident tickets:
