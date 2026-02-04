# 구현 계획표 (2026-02-04)

## 기준 문서
- `.specs/project_specs.md`
- `.specs/data_contract.md`
- `.ref/database_schema`

## Phase 1 — 리포지토리 골격 + 공통 기반
- `src/transforms`, `src/io`, `src/jobs`, `tests/unit`, `tests/integration`, `configs`, `scripts` 디렉터리 생성
- 공통 유틸 구현: UTC↔KST 변환, `date_kst` 계산, `[start, end)` 윈도우 유틸
- 공통 모델/스키마 정의: 계약 컬럼 목록, 타입 캐스팅 규칙, 필수 컬럼 체크
- 룰 로딩 기반 마련: `gold.dim_rule_scd2` 구조, 로컬 시드(`mock_data/fixtures/dim_rule_scd2.json`) 로더
- 실행 추적 공통 스펙: `run_id` 생성/전파, `gold.pipeline_state` 인터페이스 정의
Commit: `chore: scaffold project structure and common utilities`

## Phase 2 — Bronze 적재 + Mock 데이터 로더
- Bronze 테이블 스펙 정의 및 공통 메타 컬럼(`ingested_at`, `source_extracted_at`, `batch_id`) 부여
- 로컬 Mock 데이터 로더 구현: `mock_data/bronze/*` → Bronze staging
- Databricks Dev 카탈로그 업로드 스크립트 추가(`scripts/upload_mock_data.py`)
- Bronze 적재 IO 인터페이스 확정(파일 덤프 우선)
Commit: `feat: add bronze ingestion and mock data loaders`

## Phase 3 — Silver(Controls) 변환 + 계약 검증
- `silver.wallet_snapshot` 변환 로직 구현(스냅샷 시각, balance_total 파생)
- `silver.ledger_entries` 변환 로직 구현(타입 매핑으로 `amount_signed` 파생)
- 계약 위반 레코드 격리: `silver.bad_records_*` 처리 및 fail-fast 기준 적용
- Silver 테이블 멱등성 MERGE 키 적용
- 단위 테스트 추가: 부호 매핑, 스키마 검증, bad_records 분기
Commit: `feat: implement silver controls transforms with validation`

## Phase 4 — Pipeline A (Guardrail DQ)
- DQ 메트릭 계산: freshness, completeness, duplicates, contract
- `silver.dq_status` 산출 및 `gold.exception_ledger` 기록
- 룰 임계치 기반 severity 매핑
- Job 파라미터 표준(`run_mode`, `start_ts`, `end_ts`, `run_id`) 적용
Commit: `feat: add pipeline A guardrail job and outputs`

## Phase 5 — Pipeline B (Ledger & Admin Controls)
- 일일 대사: `delta_balance_total` vs `net_flow_total` 계산
- 총량 정합성: `issued_supply` vs `wallet_total_balance` 계산
- 게이팅 적용: Pipeline A 결과에 따른 알림 억제/태그 처리
- `gold.recon_daily_snapshot_flow`, `gold.ledger_supply_balance_daily` 작성
- 운영 지표: `gold.ops_payment_failure_daily`, `gold.ops_ledger_pairing_quality_daily`
- (옵션) `gold.admin_tx_search` 배치 인덱스
- 통합 테스트 추가: recon/supply 결과 및 멱등성
Commit: `feat: implement pipeline B ledger controls and ops metrics`

## Phase 6 — Silver(Analytics) + Pipeline C
- `silver.order_events`, `silver.order_items`, `silver.products` 변환 구현
- PII 제거 및 `user_key` 익명화 처리(Secret Scope 기반, 로컬은 더미 값)
- `gold.fact_payment_anonymized` 산출 및 파티셔닝 적용
- 단위 테스트: 익명화, 조인 기반 `category` 파생
Commit: `feat: add analytics silver transforms and pipeline C`

## Phase 7 — Job Wiring + 환경 설정
- 공통 파라미터 처리, `run_id` 전파, `gold.pipeline_state` 업데이트 구현
- `configs/dev.yaml`, `configs/prod.yaml`, `configs/common.yaml` 구조 확정
- Databricks Workflows/Jobs 정의(`databricks.yml` 또는 jobs 스크립트)
Commit: `chore: wire jobs and environment configs`

## Phase 8 — 테스트/CI 정리
- `tests/integration` PySpark 테스트 구성 및 스모크 시나리오 작성
- E2E 테스트 스켈레톤 및 실행 가이드 추가
- CI 스크립트 초안(유닛 테스트 게이트)
Commit: `test: add integration/e2e scaffolding and CI hooks`

## Phase 9 — 안정화 및 문서화
- 멱등성/백필 시나리오 검증 보강
- 운영/장애 대응 런북, 알림 정책 문서화
- 성능/파티셔닝 점검(필요 시 최적화 반영)
Commit: `docs: add runbook and operational checklist`
