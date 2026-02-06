# 구현 계획표 (2026-02-04)

## 기준 문서
- `.specs/project_specs.md`
- `.specs/data_contract.md`
- `.specs/cloud_migration_rebuild_plan.md`
- `.ref/database_schema`

## Phase 1 — 리포지토리 골격 + 공통 기반
- [x] `src/transforms`, `src/io`, `src/jobs`, `tests/unit`, `tests/integration`, `configs`, `scripts` 디렉터리 생성
- [x] 공통 유틸 구현: UTC↔KST 변환, `date_kst` 계산, `[start, end)` 윈도우 유틸
- [x] 공통 모델/스키마 정의: 계약 컬럼 목록, 타입 캐스팅 규칙, 필수 컬럼 체크
- [x] 룰 로딩 기반 마련: `gold.dim_rule_scd2` 구조, 로컬 시드(`mock_data/fixtures/dim_rule_scd2.json`) 로더
- [x] 실행 추적 공통 스펙: `run_id` 생성/전파, `gold.pipeline_state` 인터페이스 정의
- [x] Commit

## Phase 2 — Bronze 적재 + Mock 데이터 로더
- [x] Bronze 테이블 스펙 정의 및 공통 메타 컬럼(`ingested_at`, `source_extracted_at`, `batch_id`) 부여
- [x] 로컬 Mock 데이터 로더 구현: `mock_data/bronze/*` → Bronze staging
- [x] Databricks Dev 카탈로그 업로드 스크립트 추가(`scripts/upload_mock_data.py`)
- [x] Bronze 적재 IO 인터페이스 확정(파일 덤프 우선)
- [x] Bronze 스키마 에볼루션 정책 적용: append-only + `mergeSchema = true`
- [x] Commit

## Phase 3 — Silver(Controls) 변환 + 계약 검증
- [x] `silver.wallet_snapshot` 변환 로직 구현(스냅샷 시각, balance_total 파생)
- [x] `silver.ledger_entries` 변환 로직 구현(타입 매핑으로 `amount_signed` 파생)
- [x] `date_kst` 파티셔닝 규칙을 Silver 테이블 생성에 반영
- [x] 계약 위반 레코드 격리: `silver.bad_records_*` 처리 및 fail-fast 기준 적용
- [x] bad_records_rate 계산 + fail-fast 임계치 룰 적용(`gold.dim_rule_scd2`)
- [x] 룰 테이블 기반 허용값/임계치 검증 플로우 추가(entry_type, status 등)
- [x] Silver 테이블 멱등성 MERGE 키 적용
- [x] 단위 테스트 추가: 부호 매핑, 스키마 검증, bad_records 분기
- [x] Commit

## Phase 4 — Pipeline A (Guardrail DQ)
- [x] DQ 메트릭 계산: freshness, completeness, duplicates, contract
- [x] `silver.dq_status` 산출 및 `gold.exception_ledger` 기록
- [x] 룰 임계치 기반 severity 매핑
- [x] `dq_tag` 정책 정의 및 exception_ledger severity 매핑 확정
- [x] Job 파라미터 표준(`run_mode`, `start_ts`, `end_ts`, `run_id`) 적용
- [x] Commit

## Phase 5 — Pipeline B (Ledger & Admin Controls)
- [x] 일일 대사: `delta_balance_total` vs `net_flow_total` 계산
- [x] 총량 정합성: `issued_supply` vs `wallet_total_balance` 계산
- [x] 게이팅 적용: Pipeline A 결과에 따른 알림 억제/태그 처리
- [x] 룰 테이블 기반 drift/supply 임계치 적용 및 exception severity 결정
- [x] `gold.recon_daily_snapshot_flow`, `gold.ledger_supply_balance_daily` 작성
- [x] 운영 지표: `gold.ops_payment_failure_daily`, `gold.ops_ledger_pairing_quality_daily`
- [x] (옵션) `gold.admin_tx_search` 배치 인덱스
- [x] 통합 테스트 추가: recon/supply 결과 및 멱등성
- [x] Commit

## Phase 6 — Silver(Analytics) + Pipeline C
- [x] `silver.order_events`, `silver.order_items`, `silver.products` 변환 구현
- [x] PII 제거 및 `user_key` 익명화 처리(Secret Scope 기반, 로컬은 더미 값)
- [x] `gold.fact_payment_anonymized` 산출 및 파티셔닝 적용
- [x] 단위 테스트: 익명화, 조인 기반 `category` 파생
- [x] Commit

## Phase 7 — Dev Platform Baseline (테스트 리소스, 완료)
- [x] (개발 단계 임시정책) 기능 검증 목적의 최소 구성 유지(퍼블릭 엔드포인트 허용)
- [x] Azure 스토리지 준비: ADLS Gen2 컨테이너/경로 설계 및 네이밍 규칙 정의
- [x] Databricks Workspace/Unity Catalog 준비: 메타스토어, 카탈로그/스키마 생성
- [x] Storage Credential + External Location 설정(UC 기반)
- [x] 개발 임시 Secret Scope 구성(`ledger-analytics-dev/salt_user_key`)
- [x] 클러스터 정책/기본 클러스터 템플릿 정의(DBR 버전, 자동 종료, 태그)
- [x] Workflows 재시도/알림 정책 1차 적용(Email+Retry)
- [x] Phase 7 설정/점검 스크립트 추가(`scripts/phase7/setup_minimal_cloud.sh`, `scripts/phase7/audit_cloud_state.sh`)
- [x] Commit

## Phase 8 — Resource-agnostic Job Wiring + Config (현재 리소스에서 우선)
- [x] 공통 파라미터 처리, `run_id` 전파, `gold.pipeline_state` 업데이트 구현
- [x] `gold.pipeline_state` 갱신 규칙 정의(성공/실패, last_processed_end, last_run_id)
- [x] `configs/dev.yaml`, `configs/prod.yaml`, `configs/common.yaml` 구조 확정
- [x] Databricks Workflows/Jobs 정의 코드화(`databricks.yml` 또는 jobs 스크립트)
- [x] 환경 고유값(workspace/job/policy ID, storage path) 변수화
- [x] Commit

## Phase 9 — 테스트/CI 베이스라인 정리 (이식 가능 자산 우선)
- [x] `tests/integration` PySpark 테스트 구성 및 스모크 시나리오 작성
- [x] E2E 테스트 스켈레톤 및 실행 가이드 추가(워크스페이스 파라미터화)
- [x] CI 스크립트 초안(유닛 테스트 게이트 + 커버리지 기준)
- [x] 검증 로그/증적 템플릿(`.agents/logs/verification/`) 정리
- [x] Commit

## Phase 10 — 기능 안정화 + 운영 문서화 (이관 전 고정)
- [x] 멱등성/백필 시나리오 검증 보강
- [x] 운영/장애 대응 런북, 알림 정책 문서화
- [x] 스키마 변경/마이그레이션 정책 문서화(Silver/Gold 명시적 변경)
- [x] 성능/파티셔닝 점검(필요 시 최적화 반영)
- [x] 컷오버 Preflight/Exit Criteria 템플릿 고정(참조: `.specs/cloud_migration_rebuild_plan.md`)
- [x] Commit

## Phase 11 — Secure Environment Rebuild (신규 리소스 생성)
- [ ] 보안 하드닝: NSG/서브넷 분리/Private Endpoint/네트워크 경로 강화
- [ ] Key Vault + Key Vault-backed Secret Scope 구성
- [ ] 서비스 프린시플 기반 `run_as`/권한 모델 전환(UC ACL 포함)
- [ ] Secure Workspace/UC 오브젝트 프로비저닝 자동화 스크립트 확정
- [ ] 신규 환경 E2E 스모크(L3) 통과
- [ ] Commit

## Phase 12 — Migration Rehearsal (Dry-run)
- [ ] `T_cutover_utc` 기준 dry-run 리허설 실행
- [ ] Pipeline A/B/C backfill + incremental 전환 리허설
- [ ] 롤백 리허설(Workflow 전환 + Bronze 기준 재백필) 수행
- [ ] 검증 쿼리/증적 로그 수집 및 결과 기록
- [ ] Commit

## Phase 13 — Production Cutover + Hypercare
- [ ] 컷오버 실행 및 신규 환경 Workflows 활성화
- [ ] Post-cutover 검증(정합성/누락/중복/알림) 수행
- [ ] 구 dev/테스트 리소스 정리(보존 정책 반영)
- [ ] 운영 인수인계 문서/체크리스트 최종 확정
- [ ] Commit

## Phase별 산출물 체크리스트

### Phase 1
- [x] 디렉터리 골격 생성 완료
- [x] 공통 유틸(UTC↔KST, `date_kst`, 윈도우) 구현
- [x] 계약/스키마 유틸 및 필수 컬럼 검증 구현
- [x] 룰 로딩(로컬 시드) 동작 확인
- [x] `run_id`/`gold.pipeline_state` 인터페이스 정의 완료

### Phase 2
- [x] Bronze 테이블 스펙 문서화
- [x] Mock 데이터 로더 동작 확인
- [x] Dev 카탈로그 업로드 스크립트 동작 확인
- [x] Bronze IO 인터페이스 확정
- [x] Bronze 스키마 에볼루션 정책(`mergeSchema=true`) 적용 확인

### Phase 3
- [x] `silver.wallet_snapshot` 산출 샘플 검증
- [x] `silver.ledger_entries.amount_signed` 파생 검증
- [x] bad_records 격리 및 fail-fast 임계치 동작 확인
- [x] 룰 테이블 기반 허용값/임계치 검증 동작 확인
- [x] Silver `date_kst` 파티셔닝 적용 확인
- [x] 단위 테스트 통과

### Phase 4
- [x] DQ 메트릭 산출 검증
- [x] `silver.dq_status`/`gold.exception_ledger` 기록 확인
- [x] `dq_tag` 및 severity 매핑 규칙 확정
- [x] 표준 파라미터(`run_mode`, `start_ts`, `end_ts`, `run_id`) 적용 확인

### Phase 5
- [x] `gold.recon_daily_snapshot_flow` 결과 검증
- [x] `gold.ledger_supply_balance_daily` 결과 검증
- [x] 게이팅(알림 억제/태그) 동작 확인
- [x] 룰 기반 drift/supply 임계치 적용 확인
- [x] 운영 지표 2종 산출 검증
- [x] (옵션) `gold.admin_tx_search` 산출 여부 결정
- [x] 통합 테스트 통과

### Phase 6
- [x] `silver.order_events/order_items/products` 산출 검증
- [x] `user_key` 익명화 동작 확인(Secret Scope/로컬 더미)
- [x] `gold.fact_payment_anonymized` 파티셔닝 적용 확인
- [x] 단위 테스트 통과

### Phase 7
- [x] ADLS Gen2 경로/컨테이너 구조 확정
- [x] Dev 임시 Secret Scope 시크릿 등록 확인
- [x] Unity Catalog 메타스토어/카탈로그/스키마 생성 확인
- [x] Storage Credential/External Location 설정 확인
- [x] 클러스터 정책/템플릿 정의 완료
- [x] Workflows 알림/재시도 정책 1차 설정 완료(Email+Retry)
- [x] 설정/점검 스크립트 기반 재현성 확인
- [x] Commit 완료

### Phase 8
- [x] `gold.pipeline_state` 갱신 규칙 구현 확인
- [x] 환경 설정 파일 구조 확정
- [x] Workflows/Jobs 정의 코드화 완료
- [x] 환경 고유값 변수화 완료

### Phase 9
- [x] 통합/스모크 테스트 스위트 준비
- [x] E2E 스켈레톤 및 실행 가이드(워크스페이스 파라미터화) 작성
- [x] CI 유닛 테스트 게이트/커버리지 기준 초안 작성
- [x] 검증 로그 템플릿 정리

### Phase 10
- [x] 멱등성/백필 시나리오 검증 완료
- [x] 운영 런북/알림 정책 문서화 완료
- [x] 스키마 변경/마이그레이션 정책 문서화 완료
- [x] 성능/파티셔닝 점검 및 튜닝 항목 기록
- [x] 컷오버 Preflight/Exit Criteria 템플릿 고정

### Phase 11
- [ ] 보안 하드닝 인프라 생성 완료(NSG/서브넷/Private Endpoint)
- [ ] Key Vault-backed Secret Scope 구성 완료
- [ ] 서비스 프린시플 기반 실행 주체/권한 모델 전환 완료
- [ ] Secure Workspace/UC 자동화 스크립트 검증 완료
- [ ] 신규 환경 E2E 스모크(L3) 통과

### Phase 12
- [ ] Dry-run 컷오버 리허설 완료
- [ ] Backfill + incremental 전환 리허설 완료
- [ ] 롤백 리허설 완료
- [ ] 검증 증적/로그 기록 완료

### Phase 13
- [ ] 운영 컷오버 완료
- [ ] Post-cutover 검증 완료
- [ ] 구 dev/테스트 리소스 정리 완료
- [ ] 운영 인수인계 문서/체크리스트 확정
