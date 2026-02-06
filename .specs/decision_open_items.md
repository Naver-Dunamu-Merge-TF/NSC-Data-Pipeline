# 결정 필요 항목 목록 (Open Decisions)

작성일: 2026-02-05
업데이트: 2026-02-06

## 목적
구현 중 **명확히 결정되지 않았거나 가정으로 처리한 항목**을 기록하고,
결정이 내려지면 본 문서를 갱신한다.

## 업데이트 규칙
- 구현 중 새로운 가정/모호점이 생기면 **즉시 본 문서에 추가**한다.
- 결정이 확정되면 항목을 `결정됨`으로 변경하고 **근거 문서/룰/테이블**을 명시한다.

## 결정 필요 항목

### D-001 `user_id` ↔ `wallet_id` 매핑 기준
- 현재 가정: `user_id == wallet_id`로 취급
- 영향: `gold.recon_daily_snapshot_flow`의 `user_id` 기준 대사 결과
- 결정 필요: 실제 매핑 테이블 존재 여부 및 SSOT
- 제안: 매핑 테이블 생기면 즉시 치환, 그 전까지는 동일 키 가정 유지

### D-002 일일 스냅샷 start/end 선택 규칙
- 현재 가정: 대상 `date_kst` 내 **최소/최대 `snapshot_ts`**를 start/end로 사용
- 영향: `delta_balance_total` 계산
- 결정 필요: “일자 내 첫/마지막 스냅샷” vs “정해진 cutoff 시각” 규칙
- 제안: 샘플 데이터/운영 수집 주기 확인 후 규칙 고정

### D-003 `issued_supply` 산정 SSOT
- 현재 가정: 원장 타입(MINT/CHARGE/BURN/WITHDRAW) 합산
- 영향: `gold.ledger_supply_balance_daily` 결과
- 결정 필요: OLTP 발행량 스냅샷 테이블 존재 시 전환 여부
- 제안: OLTP 스냅샷이 있으면 SSOT로 즉시 전환

### D-004 게이팅 처리 정책
- 현재 가정: Pipeline A가 stale/drop이면 **CRITICAL → WARN 다운그레이드**
- 영향: `gold.exception_ledger` severity
- 결정 필요: **severity 유지 + 알림 억제**로 바꿀지 여부
- 제안: 운영 알림 정책이 확정되면 severity 정책을 고정

### D-005 Drift/공급 차이 임계치 비교 방식
- 현재 가정: `value > threshold` (경계값은 경보 아님)
- 영향: `drift_abs`, `supply_diff_abs` 경보
- 결정 필요: `>` vs `>=` 규칙 고정
- 제안: 임계치가 0인 경우 과경보 방지를 위해 `>` 유지

### D-006 결제 실패 status 집합
- 현재 가정: `FAILED`, `CANCELLED`
- 영향: `gold.ops_payment_failure_daily.failed_cnt`
- 결정 필요: 실패 정의를 룰 테이블에 공식화
- 제안: `gold.dim_rule_scd2`에 실패 상태 목록 추가

### D-007 페어링 품질 지표 정의
- 현재 가정: `related_id` 그룹 크기 2 + 서로 다른 `wallet_id`를 pair 후보로 계산
- 영향: `gold.ops_ledger_pairing_quality_daily.pair_candidate_rate`
- 결정 필요: 페어링 규칙 확정(실데이터 기준)
- 제안: 운영 데이터로 분포 확인 후 규칙 고정

### D-008 `ledger_entries` 멱등성 키 확장 여부
- 현재 가정: `(tx_id, wallet_id)` MERGE
- 영향: 중복 tx_id 발생 시 멱등성 붕괴 가능
- 결정 필요: `entry_seq` 등 보조 키 필요 여부
- 제안: tx_id 다중 엔트리 발생 여부 확인 후 확장

### D-009 completeness 연속 0 윈도우 상태 저장
- 현재 가정: `previous_zero_windows=0` (상태 미연결)
- 영향: `completeness_zero_windows` 계산 정확도
- 결정 필요: 상태 저장 위치(`gold.pipeline_state` 또는 `silver.dq_status` 기반)
- 제안: `gold.pipeline_state`에 per-table window 카운터 저장

### D-010 `drift_pct` 분모 0 처리
- 현재 가정: `net_flow_total == 0`이면 `drift_pct = NULL`
- 영향: `gold.recon_daily_snapshot_flow.drift_pct`
- 결정 필요: 0 분모 처리(0/NULL/별도 규칙)
- 제안: NULL 유지 (분모 0 의미 왜곡 방지)

### D-011 `gold.fact_payment_anonymized.category` 다중 아이템 처리
- 현재 가정: `order_ref` 기준 `order_items` 중 **line_amount(= price_at_purchase * quantity)**가 가장 큰 아이템의 `products.category`를 선택
- tie-break: line_amount 동일 시 **가장 작은 `item_id`** 사용
- 영향: `gold.fact_payment_anonymized.category`
- 결정 필요: 다중 카테고리 집계/대표값 산정 규칙 확정
- 제안: 운영 요구가 없으면 현재 규칙 유지

### D-012 `gold.fact_payment_anonymized` 소스 필터
- 현재 가정: `silver.order_events` 중 `order_source = PAYMENT_ORDERS`만 팩트로 사용
- 영향: 결제 팩트의 중복 방지, 주문 이벤트 제외
- 결정 필요: `ORDERS` 이벤트 포함 여부
- 제안: 결제 지표 목적이라면 `PAYMENT_ORDERS` 유지

### D-013 Silver Analytics 파티셔닝
- 현재 가정: `silver.order_items`, `silver.products`는 `date_kst` 컬럼이 없어 **파티션 없음**
- 영향: 테이블 파티션 전략, 백필 단위
- 결정 필요: 분석 요구에 따라 파티션 컬럼 추가 여부
- 제안: 필요 시 `snapshot_date_kst` 등 보강 후 파티셔닝 검토

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
- 현재 상태: Phase 7에서는 사용자 principal(`2dt026@msacademy.msai.kr`) ACL로 임시 운영 중
- 영향: 운영 이관 시 잡 실행 주체/권한 일관성
- 결정 필요: 서비스 프린시플 생성 시점(Phase 8 vs 재구축 단계)과 `run_as` 전환 계획
- 제안: 최소 `run_as`용 SP 1개를 Phase 8에서 우선 도입하고, 재구축 단계에서 분리 권한 모델 완성

### D-019 Analytics salt 해석 우선순위
- 상태: **결정됨(2026-02-06, 개발단계)**
- 결정: `ANON_USER_KEY_SALT` 환경변수 우선, 없으면 Secret Scope(`ledger-analytics-dev/salt_user_key`), 둘 다 없으면 로컬 더미 `local-salt-v1` 사용
- 영향: 로컬/Databricks 실행 모두에서 익명화 키 생성 동작을 일관화
- 근거: D-014, D-015 및 Phase 6 구현 정책
