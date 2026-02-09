# 결정 필요 항목 목록 (Open Decisions)

작성일: 2026-02-05
업데이트: 2026-02-09

## 목적
구현 중 **명확히 결정되지 않았거나 가정으로 처리한 항목**을 기록하고,
결정이 내려지면 본 문서를 갱신한다.

## 업데이트 규칙
- 구현 중 새로운 가정/모호점이 생기면 **즉시 본 문서에 추가**한다.
- 결정이 확정되면 항목을 `결정됨`으로 변경하고 **근거 문서/룰/테이블**을 명시한다.

## 결정 필요 항목

### D-001 `user_id` ↔ `wallet_id` 매핑 기준
- 상태: **결정됨(2026-02-09)**
- 결정: 현 단계에서는 `user_id == wallet_id`로 취급한다.
- 영향: `gold.recon_daily_snapshot_flow`의 `user_id` 기준 대사 결과
- 재검토 트리거: 외부 SSOT(매핑 테이블 또는 소유 이력)가 도입되면 신규 결정으로 전환 여부를 검토한다.
- 근거: 사용자 결정(옵션 A)

### D-002 일일 스냅샷 start/end 선택 규칙
- 상태: **결정됨(2026-02-09)**
- 결정: 현 단계에서는 대상 `date_kst` 내 **최소/최대 `snapshot_ts`**를 start/end로 사용한다.
- 영향: `delta_balance_total` 계산
- 재검토 트리거: 업스트림이 “일자 cutoff 기반” 스냅샷 정책을 제공하면, cutoff 규칙으로 전환을 검토한다.
- 근거: 사용자 결정(옵션 A)

### D-003 `issued_supply` 산정 SSOT
- 상태: **결정됨(2026-02-09)**
- 결정: 현 단계에서는 원장 타입(MINT/CHARGE/BURN/WITHDRAW) 합산을 `issued_supply`로 사용한다.
- 영향: `gold.ledger_supply_balance_daily` 결과
- 재검토 트리거: OLTP/정산의 발행량 스냅샷 SSOT가 제공되면, 이를 SSOT로 전환하는 개선을 검토한다.
- 근거: 사용자 결정(옵션 A)

### D-004 게이팅 처리 정책
- 상태: **결정됨(2026-02-06)**
- 결정: Pipeline A가 stale/drop이어도 `gold.exception_ledger.severity`는 원본 등급을 유지하고, 알림 채널에서만 억제한다.
- 영향: 예외 심각도 의미를 보존하면서 운영 알림 노이즈를 제어한다.
- 근거: 운영 관측/감사 정확도 우선 정책

### D-005 Drift/공급 차이 임계치 비교 방식
- 상태: **결정됨(2026-02-06)**
- 결정: 임계치 비교는 `value > threshold`를 사용한다.
- 영향: 경계값 도달만으로 과경보가 발생하지 않도록 한다.
- 근거: 임계치 0 구간에서 노이즈 억제

### D-006 결제 실패 status 집합
- 상태: **결정됨(2026-02-06)**
- 결정: 실패 지표(`gold.ops_payment_failure_daily.failed_cnt`)는 `FAILED`, `CANCELLED`만 포함한다.
- 보완: `REFUNDED`는 실패율과 분리된 별도 지표로 관리한다(동일 Pipeline B 내 추가 산출물로 처리, 신규 파이프라인 불필요).
- 영향: 실패율 의미를 유지하면서 환불 추세를 별도로 관찰 가능
- 근거: 운영 지표 해석 분리 원칙

### D-007 페어링 품질 지표 정의
- 상태: **결정됨(2026-02-06)**
- 결정: `related_id` 그룹 크기 2 + 서로 다른 `wallet_id`인 경우만 pair 후보로 계산한다.
- 영향: 규칙 단순성과 재현성을 우선하며, 운영 대시보드 해석 일관성을 확보한다.
- 근거: 현 단계의 최소 안정 규칙 고정

### D-008 `ledger_entries` 멱등성 키 확장 여부
- 상태: **결정됨(2026-02-09)**
- 결정: 현 단계에서는 `silver.ledger_entries` 멱등성 키를 `(tx_id, wallet_id)`로 유지한다.
- 영향: `tx_id`는 행 단위 유니크(PK)라는 계약을 전제로 DQ에서 중복을 차단한다.
- 재검토 트리거: 실데이터에서 “동일 `tx_id` 다중 엔트리”가 관측되면 `entry_seq`(또는 `entry_id`) 도입으로 재결정한다.
- 근거: `.specs/data_contract.md`의 `transaction_ledger.tx_id` PK 가정 + 사용자 결정(옵션 A)

### D-009 completeness 연속 0 윈도우 상태 저장
- 상태: **결정됨(2026-02-06)**
- 결정: `gold.pipeline_state`에 `source_table`별 연속 0 윈도우 카운터를 저장/갱신한다.
- 영향: 실행 간 completeness 상태 연속성을 보장하고, 누적 경보 정확도를 높인다.
- 근거: 상태 저장 일관성 우선 정책

### D-010 `drift_pct` 분모 0 처리
- 상태: **결정됨(2026-02-06)**
- 결정: `net_flow_total == 0`이면 `drift_pct = NULL`로 유지한다.
- 영향: 분모 0 구간의 의미 왜곡을 방지하고 지표 해석을 명확히 유지한다.
- 근거: 수학적 정의 불가 구간은 NULL 표현 원칙

### D-011 `gold.fact_payment_anonymized.category` 다중 아이템 처리
- 상태: **결정됨(2026-02-06)**
- 결정: `order_ref` 기준 `order_items` 중 line_amount가 가장 큰 아이템의 `products.category`를 대표값으로 사용하고, 동률이면 가장 작은 `item_id`를 선택한다.
- 영향: 단일 카테고리 스키마를 유지해 분석/집계 단순성을 확보한다.
- 근거: 현 단계 팩트 스키마 단순화 우선

### D-012 `gold.fact_payment_anonymized` 소스 필터
- 상태: **결정됨(2026-02-06)**
- 결정: `silver.order_events` 중 `order_source = PAYMENT_ORDERS`만 `gold.fact_payment_anonymized`에 포함한다.
- 영향: 결제 이벤트 중심 팩트 정의를 유지하고 중복 위험을 줄인다.
- 근거: 결제 지표 목적의 스코프 고정

### D-013 Silver Analytics 파티셔닝
- 상태: **결정됨(2026-02-06)**
- 결정: `silver.order_items`, `silver.products`는 현재 단계에서 파티션 없이 유지한다.
- 영향: 스키마/운영 복잡도를 낮추고, 데이터 규모 증가 시 파티션 컬럼 보강 후 재평가한다.
- 근거: 초기 단계 단순화 + 단계적 최적화 원칙

### D-014 Analytics `salt` Secret Scope/Key 정의
- 상태: **결정됨(2026-02-06, dev 임시 기준)**
- 결정: `scope=ledger-analytics-dev`, `key=salt_user_key`
- 후속: 운영 재구축 시 Key Vault-backed Secret Scope로 전환
- 영향: `user_key` 익명화 구현 및 배포 환경 설정
- 근거: `.specs/phase7_cloud_setup_status.md`, `scripts/phase7/setup_minimal_cloud.sh`

### D-015 로컬 더미 `salt` 값
- 상태: **결정됨(2026-02-06)**
- 결정: 로컬 더미 `salt` 상수는 `local-salt-v1`
- 영향: 로컬 테스트 재현성
- 근거: 재현 가능한 테스트 실행을 위한 고정 상수 정책

### D-016 `gold.fact_payment_anonymized` 멱등성/파티셔닝 전략
- 상태: **결정됨(2026-02-06, 개발단계 임시)**
- 결정: `date_kst` 단위 `overwrite partition` 전략을 사용하고, Pipeline C에서는 대상 파티션만 교체한다.
- 영향: 백필/재실행 시 동일 `date_kst` 범위에 대해 결과 수렴을 보장한다.
- 후속: 운영 데이터량/지연 요구가 커지면 `MERGE` 키 전략으로 재평가한다.
- 근거: `.specs/cloud_migration_rebuild_plan.md`, `.roadmap/implementation_roadmap.md` Phase 6

### D-017 개발 단계 보안 하드닝 유예 범위
- 상태: **결정됨(2026-02-06)**
- 결정: 개발/테스트 단계에서는 퍼블릭 엔드포인트 기반 최소 구성으로 진행하고, NSG/서브넷 분리/Private Endpoint/강화된 시크릿 경로는 **개발 완료 후 재구축 단계**에서 적용
- 영향: Phase 7의 보안 관련 산출물은 “최종 보안 구성”이 아닌 임시 구성이 될 수 있음
- 근거: 사용자 결정 및 `.specs/cloud_migration_rebuild_plan.md`

### D-018 서비스 프린시플 실행 주체 전환 시점
- 상태: **결정됨(2026-02-06)**
- 결정: 서비스 프린시플 기반 `run_as`/권한 전환은 보안 설정된 신규 리소스 준비 완료 후(Phase 11) 진행한다.
- 영향: Phase 8~10 구간은 사용자 principal 임시 운영을 유지하고, Secure Environment Rebuild 단계에서 전환을 수행한다.
- 근거: 사용자 결정 및 `.roadmap/implementation_roadmap.md` Phase 11 정책

### D-019 Analytics salt 해석 우선순위
- 상태: **결정됨(2026-02-06, 개발단계)**
- 결정: `ANON_USER_KEY_SALT` 환경변수 우선, 없으면 Secret Scope(`ledger-analytics-dev/salt_user_key`), 둘 다 없으면 로컬 더미 `local-salt-v1` 사용
- 영향: 로컬/Databricks 실행 모두에서 익명화 키 생성 동작을 일관화
- 근거: D-014, D-015 및 Phase 6 구현 정책

### D-020 `gold.pipeline_state` 실패 시 업데이트 규칙
- 상태: **결정됨(2026-02-06, 개발단계)**
- 결정: 성공 시 `last_success_ts`, `last_processed_end`, `last_run_id`를 모두 갱신하고, 실패 시 `last_success_ts`/`last_processed_end`는 유지하며 `last_run_id`, `updated_at`만 갱신
- 영향: 증분 재개 체크포인트는 마지막 성공 지점을 보존하고, 최근 실패 실행 ID는 추적 가능
- 근거: `.specs/project_specs.md` 9.1, Phase 8 구현 정책
