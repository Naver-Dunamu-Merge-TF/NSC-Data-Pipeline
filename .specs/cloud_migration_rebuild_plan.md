# Cloud Migration/Rebuild Plan (Data-pipeline, Test-first)

Last updated: 2026-02-06

## 1. 목적

이 문서는 현재 테스트 중심 Azure Databricks 환경을 빠르게 생성/폐기하면서 기능을 검증하고,
개발 완료 후 보안 강화 환경으로 재구축할 때 데이터/운영 절차를 일관되게 유지하기 위한 기준이다.

본 계획은 "기존 리소스 인플레이스 강화"보다 "신규 보안 환경 생성 후 컷오버"를 기본 전략으로 한다.

## 2. 현재 전제(프로젝트 상황)

1. 현재 단계: mock data 기반 개발(Phase 6~7).
2. 보안 정책: 개발 단계에서는 최소 구성(퍼블릭 엔드포인트 허용), 하드닝은 재구축 단계에서 적용.
3. 데이터 원칙: Bronze 원본 기반으로 Silver/Gold를 재계산 가능한 구조를 유지.
4. 운영 원칙: 모든 산출물은 `run_id` 추적 가능해야 하며, 일 경계는 `date_kst`를 기준으로 한다.

현재 dev 테스트 환경 기준값:

- Subscription ID: `27db5ec6-d206-4028-b5e1-6004dca5eeef`
- Resource Group: `2dt-final-team4`
- Region: `koreacentral`
- Databricks Workspace: `2dt-final-team4-databricks-test`
- ADLS Storage Account: `2dtfinalteam4storagetest`
- ADLS Container: `2dt-final-team4-adls-test`

현재 확인된 갭(Phase 7 미완료):

- Key Vault 미구성
- 서비스 프린시플 기반 실행 주체/권한 모델 미확정
- Slack 알림 채널 미연동(현재 Email only)
- Pipeline B/C Workflow 정책 미배포(현재 Pipeline A 우선 반영)

컷오버 전 확정이 필요한 의사결정:

- D-016: `gold.fact_payment_anonymized` 멱등성/파티셔닝 방식
- D-018: 서비스 프린시플 실행 주체 전환 시점

## 3. 범위

Phase 7~8 항목 기준:

- ADLS Gen2 컨테이너/경로
- Databricks Workspace + Unity Catalog(메타스토어/카탈로그/스키마)
- Storage Credential + External Location
- Key Vault + Secret Scope
- 서비스 프린시플/권한(카탈로그/스키마/테이블 ACL 포함)
- Workflows/클러스터 정책/알림/재시도

비범위:

- OLTP 트랜잭션 처리 시스템 재구축
- 실시간 Serving API 마이그레이션

## 4. 리소스 모델 정책

1. 환경 구분은 `dev`(검증용)와 `prod-secure`(보안 적용)로 분리한다.
2. 테스트용 환경은 폐기 가능(disposable)해야 한다.
3. 보안 적용은 기존 `dev` 환경을 수정하지 않고 별도 리소스로 생성한다.
4. 컷오버 완료 후 테스트용 리소스를 폐기한다.

권장 리소스 축:

- `Resource Group`: 환경별 분리
- `Storage Account/Container`: 환경별 분리
- `Databricks Workspace`: 환경별 분리
- `Unity Catalog Catalog/Schema`: 환경별 분리 또는 명시적 네이밍 분리

리소스 식별 규칙(권장):

- 이름 패턴: `<org>-<project>-<env>-<purpose>`
- 필수 태그: `env`, `owner`, `cost_center`, `destroyable`, `expires_on`
- 파괴 가능 환경(`destroyable=true`)만 자동 정리 대상에 포함

## 5. 데이터/스키마 마이그레이션 전략

1. Silver/Gold는 파생 데이터로 간주하고, 복구/이관 시 Bronze 기준 재계산을 우선한다.
2. Bronze는 append-only 원칙을 유지하고, 필요 시 소스 재적재 또는 mock 재적재로 복구한다.
3. Silver/Gold 스키마 변경은 계약 기반 명시적 변경만 허용한다.
4. `date_kst` 파티션 단위 백필 + 재실행 멱등성(MERGE 키/overwrite partition)을 보장한다.
5. `gold.dim_rule_scd2`는 버전 테이블로 취급하여 이관 시 seed/동기화 기준을 고정한다.
6. `gold.pipeline_state`는 운영 연속성이 필요하면 이전하고, 테스트 환경에서는 초기화 가능하다.

## 6. 컷오버 기준과 실행 순서

컷오버 기준 시각:

- `T_cutover_utc`를 단일 값으로 선언한다.
- 백필 범위: `event_time < T_cutover_utc`
- 증분 범위: `event_time >= T_cutover_utc`
- 권장 동결 구간: `T_cutover_utc` 전후 30분(설정/권한 변경 금지)

사전 점검(Preflight):

1. 대상 구독/RG/워크스페이스/스토리지 이름 재확인
2. UC 권한 체크(`USE CATALOG`, `USE SCHEMA`, `SELECT`, `MODIFY`)
3. Secret 주입 상태 확인(`salt`, 연결 토큰, Scope 접근 권한)
4. 파이프라인 파라미터 템플릿 확정(`run_mode`, `start_ts`, `end_ts`, `run_id`)
5. 기존 Workflows 중단/재개 계획 확정(정지 순서, 재개 순서)

실행 순서(신규 보안 환경 기준):

1. 신규 리소스 생성(네트워크/스토리지/워크스페이스/UC).
2. Secret 주입(Key Vault + Secret Scope) 및 연결정보 검증.
3. UC 오브젝트 생성(카탈로그/스키마/External Location/Storage Credential).
4. Bronze 적재 경로 연결 및 읽기/쓰기 권한 검증.
5. Pipeline A backfill 실행.
6. Pipeline B/C backfill 실행.
7. `T_cutover_utc` 이후 증분 실행 전환.
8. `gold.pipeline_state` 갱신 정상 여부 확인.
9. 기존 환경 Workflows 중지, 신규 환경 Workflows 활성화.

단계별 종료 기준(Exit Criteria):

| 단계 | 종료 기준 | 실패 시 기본 조치 |
|---|---|---|
| Infra/UC 준비 | External Location 조회 + 경로 접근 성공 | 권한/Credential 재검증 후 재시도 |
| Pipeline A | `silver.dq_status` 생성, CRITICAL 급증 없음 | 파라미터 축소 재실행 |
| Pipeline B/C Backfill | Gold 핵심 테이블 생성 완료 | 날짜 구간 분할 재실행 |
| Incremental 전환 | `T_cutover_utc` 이후 데이터 누락 없음 | 이전 스케줄 유지 + 증분 재동기화 |
| State 확인 | `gold.pipeline_state` 최신 `last_run_id` 반영 | 상태 테이블 복구/재기록 |

## 7. Unity Catalog/권한 정책

1. External Location은 ADLS 경로를 환경별 prefix로 분리한다.
2. Storage Credential은 환경별 Access Connector 또는 Service Principal과 1:1 매핑한다.
3. 권한은 최소 권한 원칙으로 부여한다.
4. 테이블 ACL은 최소 단위(`USE CATALOG`, `USE SCHEMA`, `SELECT`, `MODIFY`)로 분리한다.
5. 권한 정책은 코드/문서에서 재현 가능해야 한다.

권한 최소 세트(권장):

- 실행 주체: Catalog/Schema `USE`, 대상 테이블 `SELECT`/`MODIFY`
- 운영 조회 주체: `SELECT` only
- 실험/개발 주체: 개발용 스키마 한정 `MODIFY`

## 8. Secret/자격증명 정책

1. 개발 단계:
- 테스트 우선 정책으로 최소한의 비밀 관리만 적용한다.
- 로컬 더미 값은 문서화된 고정값을 사용한다.
2. 보안 재구축 단계:
- Key Vault를 SSOT로 사용한다.
- Databricks Secret Scope는 Key Vault 연동 방식으로 구성한다.
- 코드/문서/`.env`에 평문 토큰 저장을 금지한다.

자격증명 운영 규칙:

- 환경별로 별도 Scope/Key를 사용한다(`dev`, `prod-secure` 분리).
- 시크릿 교체 시 파이프라인 중단 없는 롤링 교체 절차를 사용한다.
- 만료 주기/회전 이력을 운영 문서에 기록한다.

## 9. 검증 게이트

1. 인프라 게이트
- 스토리지 경로 접근, UC External Location 조회, 권한 검증 통과
2. 데이터 게이트
- Pipeline A/B/C 스모크 실행 성공
- `gold.exception_ledger`와 `silver.dq_status` 생성 확인
3. 품질 게이트
- `pytest tests/unit/ -v -x` 통과
- 필요 시 `pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80` 통과
4. 멱등성 게이트
- 동일 윈도우 재실행 시 결과 수렴 확인

컷오버 검증용 mock 시나리오 카탈로그(문서 내 기준):

| 시나리오 | 목적 | 최소 권장 행 수 |
|---|---|---|
| `one_day_normal` | 기본 정상 흐름 검증 | 테이블별 2~5행 |
| `dup_tx_id` | 중복 거래 탐지 검증 | `transaction_ledger` 6~10행 |
| `missing_required` | 필수 컬럼 누락 격리 검증 | 대상 테이블 3~5행(불량 1행 포함) |
| `invalid_amount` | 금액/잔액 비정상 처리 검증 | 대상 테이블 3~5행(불량 1행 포함) |
| `unknown_entry_type` | 허용값 외 타입 검증 | `transaction_ledger` 3~5행 |
| `status_not_allowed` | 결제 상태 허용값 검증 | `payment_orders` 3~5행 |
| `stale_source` | freshness 및 게이팅 검증 | 대상 테이블 5~10행 |
| `zero_window` | completeness 0건 윈도우 검증 | 윈도우 내 0행 |
| `drift_mismatch` | 대사 불일치 검증 | snapshot 4행 + ledger 2~4행 |
| `supply_mismatch` | 공급/잔액 불일치 검증 | `ledger_entries` 4~6행 |
| `pairing_quality` | related_id 페어링 품질 검증 | `ledger_entries` 6~8행 |
| `analytics_multi_item` | category 파생 규칙 검증 | items 3~4행 + products 3~4행 |
| `analytics_missing_product` | category NULL 처리 검증 | items 2행 + products 1행 |
| `backfill_two_days` | 파티션 백필/멱등성 검증 | `one_day_normal` 2일치 |
| `bad_records_rate_exceed` | fail-fast 임계치 초과 검증 | 대상 50행 + 불량 1행 |
| `timezone_boundary` | UTC→KST 경계 검증 | 3~5행 |
| `hold_release_zero_flow` | `HOLD/RELEASE` 순흐름 0 검증 | 3~5행 |
| `tx_id_multi_entry` | 멱등성 키 충돌 위험 검증 | 3~6행 |
| `related_id_type_cast` | 관련키 타입 캐스팅 검증 | orders/payment/ledger 1~3행 |
| `status_null_and_invalid` | 상태 NULL/비허용 검증 | 3~5행 |
| `missing_event_time` | 이벤트 시각 누락 검증 | 3~5행 |
| `large_amount_precision` | DECIMAL 경계 검증 | 2~3행 |
| `gating_effect` | A 파이프라인 게이팅 영향 검증 | 최소 행수 |

운영 적용 우선순위:
1. `one_day_normal`, `dup_tx_id`, `missing_required`, `invalid_amount`
2. `stale_source`, `zero_window`, `drift_mismatch`, `supply_mismatch`
3. `backfill_two_days`, `bad_records_rate_exceed`, `gating_effect`

핵심 검증 쿼리 관점(필수):

1. `gold.recon_daily_snapshot_flow`
- `date_kst`별 row 수/`drift_abs` 분포 확인
2. `gold.ledger_supply_balance_daily`
- `diff_amount`와 `is_ok` 일관성 확인
3. `gold.exception_ledger`
- 컷오버 직후 비정상적 CRITICAL 급증 여부 확인
4. `gold.pipeline_state`
- `last_processed_end`, `last_run_id`, `updated_at` 최신성 확인

증적 보관:

- 검증 로그는 `.agents/logs/verification/`에 저장한다.
- 컷오버 실행 기록(`T_cutover_utc`, 실행자, 결과)은 별도 운영 로그에 남긴다.

## 10. 롤백 원칙

1. 애플리케이션/잡 문제는 Workflows 활성 환경 전환으로 우선 롤백한다.
2. 데이터 문제는 Bronze 기준 재백필로 복구한다.
3. 스키마/권한 문제는 신규 환경 재생성 후 재컷오버를 우선한다.
4. 롤백 판단은 데이터 정합성, 복구 시간, 운영 영향으로 평가한다.

롤백 트리거(예시):

- Pipeline A에서 연속 CRITICAL 발생으로 B/C 게이팅 지속
- Gold 핵심 테이블 미생성 또는 `pipeline_state` 갱신 실패 지속
- 컷오버 후 지정 관측 창에서 데이터 누락/중복이 허용 기준 초과

## 11. 폐기 안전장치

1. 파괴 대상은 환경 태그와 네이밍 규칙으로 식별 가능한 리소스로 제한한다.
2. 파괴 전 체크:
- 구독/리소스그룹/워크스페이스 이름 확인
- 보존 대상(`prod-secure`) 여부 확인
- 복구 경로(Bronze 재적재/백필 절차) 확인
3. 파괴 후 체크:
- Workflows 비활성 확인
- 남은 권한/시크릿/External Location orphan 리소스 확인

금지 작업:

- 환경 식별 불명확 상태에서 파괴 실행
- `prod-secure` 태그 리소스 포함 파괴 실행
- 파괴 전 증적(대상 목록/복구 경로) 미기록 상태에서 실행

## 12. 실행 체크리스트

- [ ] 환경별 네이밍 규칙(`dev`, `prod-secure`) 확정
- [ ] `T_cutover_utc` 운영 규칙 확정
- [x] UC 오브젝트 생성/권한 부여 절차 스크립트화(`scripts/phase7/setup_minimal_cloud.sh`)
- [ ] Secret Scope/Key Vault 연동 절차 확정
- [ ] 백필/증분 전환 런북 작성
- [ ] 멱등성 검증 시나리오(재실행/백필) 확정
- [ ] 파괴 안전장치 체크리스트 확정
- [ ] 컷오버 단계별 Exit Criteria 템플릿 문서화
- [x] 검증 쿼리/로그 경로(`.agents/logs/verification/`) 운영 템플릿 확정(`scripts/phase7/audit_cloud_state.sh`)

## 13. 의사결정 연계

- D-017: 개발 단계 보안 하드닝 유예 범위
- D-014: Analytics `salt` Secret Scope/Key 정의
- D-015: 로컬 더미 `salt` 값
- D-016: `gold.fact_payment_anonymized` 멱등성/파티셔닝 전략
- D-018: 서비스 프린시플 실행 주체 전환 시점

## 14. 참조

- `.roadmap/implementation_roadmap.md` (Phase 7~10)
- `.specs/project_specs.md`
- `.specs/data_contract.md`
- `.specs/decision_open_items.md`
- `.specs/cloud_migration_rebuild_plan_ref.md`
