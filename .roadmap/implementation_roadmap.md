# 구현 계획표 (2026-02-04)

## 기준 문서
- `.specs/project_specs.md`
- `.specs/data_contract.md`
- `.ref/database_schema`

## Phase 1 — 리포지토리 골격 + 공통 기반
- [ ] `src/transforms`, `src/io`, `src/jobs`, `tests/unit`, `tests/integration`, `configs`, `scripts` 디렉터리 생성
- [ ] 공통 유틸 구현: UTC↔KST 변환, `date_kst` 계산, `[start, end)` 윈도우 유틸
- [ ] 공통 모델/스키마 정의: 계약 컬럼 목록, 타입 캐스팅 규칙, 필수 컬럼 체크
- [ ] 룰 로딩 기반 마련: `gold.dim_rule_scd2` 구조, 로컬 시드(`mock_data/fixtures/dim_rule_scd2.json`) 로더
- [ ] 실행 추적 공통 스펙: `run_id` 생성/전파, `gold.pipeline_state` 인터페이스 정의
- [ ] Commit

## Phase 2 — Bronze 적재 + Mock 데이터 로더
- [ ] Bronze 테이블 스펙 정의 및 공통 메타 컬럼(`ingested_at`, `source_extracted_at`, `batch_id`) 부여
- [ ] 로컬 Mock 데이터 로더 구현: `mock_data/bronze/*` → Bronze staging
- [ ] Databricks Dev 카탈로그 업로드 스크립트 추가(`scripts/upload_mock_data.py`)
- [ ] Bronze 적재 IO 인터페이스 확정(파일 덤프 우선)
- [ ] Bronze 스키마 에볼루션 정책 적용: append-only + `mergeSchema = true`
- [ ] Commit

## Phase 3 — Silver(Controls) 변환 + 계약 검증
- [ ] `silver.wallet_snapshot` 변환 로직 구현(스냅샷 시각, balance_total 파생)
- [ ] `silver.ledger_entries` 변환 로직 구현(타입 매핑으로 `amount_signed` 파생)
- [ ] `date_kst` 파티셔닝 규칙을 Silver 테이블 생성에 반영
- [ ] 계약 위반 레코드 격리: `silver.bad_records_*` 처리 및 fail-fast 기준 적용
- [ ] bad_records_rate 계산 + fail-fast 임계치 룰 적용(`gold.dim_rule_scd2`)
- [ ] 룰 테이블 기반 허용값/임계치 검증 플로우 추가(entry_type, status 등)
- [ ] Silver 테이블 멱등성 MERGE 키 적용
- [ ] 단위 테스트 추가: 부호 매핑, 스키마 검증, bad_records 분기
- [ ] Commit

## Phase 4 — Pipeline A (Guardrail DQ)
- [ ] DQ 메트릭 계산: freshness, completeness, duplicates, contract
- [ ] `silver.dq_status` 산출 및 `gold.exception_ledger` 기록
- [ ] 룰 임계치 기반 severity 매핑
- [ ] `dq_tag` 정책 정의 및 exception_ledger severity 매핑 확정
- [ ] Job 파라미터 표준(`run_mode`, `start_ts`, `end_ts`, `run_id`) 적용
- [ ] Commit

## Phase 5 — Pipeline B (Ledger & Admin Controls)
- [ ] 일일 대사: `delta_balance_total` vs `net_flow_total` 계산
- [ ] 총량 정합성: `issued_supply` vs `wallet_total_balance` 계산
- [ ] 게이팅 적용: Pipeline A 결과에 따른 알림 억제/태그 처리
- [ ] 룰 테이블 기반 drift/supply 임계치 적용 및 exception severity 결정
- [ ] `gold.recon_daily_snapshot_flow`, `gold.ledger_supply_balance_daily` 작성
- [ ] 운영 지표: `gold.ops_payment_failure_daily`, `gold.ops_ledger_pairing_quality_daily`
- [ ] (옵션) `gold.admin_tx_search` 배치 인덱스
- [ ] 통합 테스트 추가: recon/supply 결과 및 멱등성
- [ ] Commit

## Phase 6 — Silver(Analytics) + Pipeline C
- [ ] `silver.order_events`, `silver.order_items`, `silver.products` 변환 구현
- [ ] PII 제거 및 `user_key` 익명화 처리(Secret Scope 기반, 로컬은 더미 값)
- [ ] `gold.fact_payment_anonymized` 산출 및 파티셔닝 적용
- [ ] 단위 테스트: 익명화, 조인 기반 `category` 파생
- [ ] Commit

## Phase 7 — Cloud/Platform Setup (Azure + Databricks)
- [ ] Azure 스토리지 준비: ADLS Gen2 컨테이너/경로 설계 및 네이밍 규칙 정의
- [ ] Key Vault/Secret Scope 설정: `salt`, DB 연결, 토큰 등 시크릿 관리
- [ ] Databricks Workspace/Unity Catalog 준비: 메타스토어, 카탈로그/스키마 생성
- [ ] Storage Credential + External Location 설정(UC 기반)
- [ ] 서비스 프린시플/권한 부여: 카탈로그, 스키마, 테이블 ACL
- [ ] 클러스터 정책/기본 클러스터 템플릿 정의(DBR 버전, 자동 종료, 태그)
- [ ] Workflows 알림 채널 연동(Slack/Email) 및 재시도 정책 정의
- [ ] Commit

## Phase 8 — Job Wiring + 환경 설정
- [ ] 공통 파라미터 처리, `run_id` 전파, `gold.pipeline_state` 업데이트 구현
- [ ] `gold.pipeline_state` 갱신 규칙 정의(성공/실패, last_processed_end, last_run_id)
- [ ] `configs/dev.yaml`, `configs/prod.yaml`, `configs/common.yaml` 구조 확정
- [ ] Databricks Workflows/Jobs 정의(`databricks.yml` 또는 jobs 스크립트)
- [ ] Commit

## Phase 9 — 테스트/CI 정리
- [ ] `tests/integration` PySpark 테스트 구성 및 스모크 시나리오 작성
- [ ] E2E 테스트 스켈레톤 및 실행 가이드 추가
- [ ] CI 스크립트 초안(유닛 테스트 게이트)
- [ ] Commit

## Phase 10 — 안정화 및 문서화
- [ ] 멱등성/백필 시나리오 검증 보강
- [ ] 운영/장애 대응 런북, 알림 정책 문서화
- [ ] 스키마 변경/마이그레이션 정책 문서화(Silver/Gold 명시적 변경)
- [ ] 성능/파티셔닝 점검(필요 시 최적화 반영)
- [ ] Commit

## Phase별 산출물 체크리스트

### Phase 1
- [ ] 디렉터리 골격 생성 완료
- [ ] 공통 유틸(UTC↔KST, `date_kst`, 윈도우) 구현
- [ ] 계약/스키마 유틸 및 필수 컬럼 검증 구현
- [ ] 룰 로딩(로컬 시드) 동작 확인
- [ ] `run_id`/`gold.pipeline_state` 인터페이스 정의 완료

### Phase 2
- [ ] Bronze 테이블 스펙 문서화
- [ ] Mock 데이터 로더 동작 확인
- [ ] Dev 카탈로그 업로드 스크립트 동작 확인
- [ ] Bronze IO 인터페이스 확정
- [ ] Bronze 스키마 에볼루션 정책(`mergeSchema=true`) 적용 확인

### Phase 3
- [ ] `silver.wallet_snapshot` 산출 샘플 검증
- [ ] `silver.ledger_entries.amount_signed` 파생 검증
- [ ] bad_records 격리 및 fail-fast 임계치 동작 확인
- [ ] 룰 테이블 기반 허용값/임계치 검증 동작 확인
- [ ] Silver `date_kst` 파티셔닝 적용 확인
- [ ] 단위 테스트 통과

### Phase 4
- [ ] DQ 메트릭 산출 검증
- [ ] `silver.dq_status`/`gold.exception_ledger` 기록 확인
- [ ] `dq_tag` 및 severity 매핑 규칙 확정
- [ ] 표준 파라미터(`run_mode`, `start_ts`, `end_ts`, `run_id`) 적용 확인

### Phase 5
- [ ] `gold.recon_daily_snapshot_flow` 결과 검증
- [ ] `gold.ledger_supply_balance_daily` 결과 검증
- [ ] 게이팅(알림 억제/태그) 동작 확인
- [ ] 룰 기반 drift/supply 임계치 적용 확인
- [ ] 운영 지표 2종 산출 검증
- [ ] (옵션) `gold.admin_tx_search` 산출 여부 결정
- [ ] 통합 테스트 통과

### Phase 6
- [ ] `silver.order_events/order_items/products` 산출 검증
- [ ] `user_key` 익명화 동작 확인(Secret Scope/로컬 더미)
- [ ] `gold.fact_payment_anonymized` 파티셔닝 적용 확인
- [ ] 단위 테스트 통과

### Phase 7
- [ ] ADLS Gen2 경로/컨테이너 구조 확정
- [ ] Key Vault/Secret Scope 시크릿 등록 확인
- [ ] Unity Catalog 메타스토어/카탈로그/스키마 생성 확인
- [ ] Storage Credential/External Location 설정 확인
- [ ] 서비스 프린시플 권한 부여 확인
- [ ] 클러스터 정책/템플릿 정의 완료
- [ ] Workflows 알림/재시도 정책 설정 완료

### Phase 8
- [ ] `gold.pipeline_state` 갱신 규칙 구현 확인
- [ ] 환경 설정 파일 구조 확정
- [ ] Workflows/Jobs 정의 완료

### Phase 9
- [ ] 통합/스모크 테스트 스위트 준비
- [ ] E2E 스켈레톤 및 실행 가이드 작성
- [ ] CI 유닛 테스트 게이트 초안 작성

### Phase 10
- [ ] 멱등성/백필 시나리오 검증 완료
- [ ] 운영 런북/알림 정책 문서화 완료
- [ ] 스키마 변경/마이그레이션 정책 문서화 완료
- [ ] 성능/파티셔닝 점검 및 튜닝 항목 기록
