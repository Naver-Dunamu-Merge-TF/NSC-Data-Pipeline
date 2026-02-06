# Mock Data Scenario Expansion Plan (2026-02-06)

## 목적
현재 mock 데이터는 해피패스 1개 시나리오로 구성되어 있어
DQ/계약 위반/멱등성/게이팅 등 핵심 위험을 충분히 검증하기 어렵다.
본 문서는 **deterministic**하고 **작지만 의미 있는** 시나리오 세트를 정의한다.

## 원칙
- **작게 시작**: 시나리오당 최소 행 수로 핵심 규칙을 검증한다.
- **결정적 데이터**: 랜덤 금지, 고정값만 사용.
- **계약 준수**: `.specs/data_contract.md` 스키마 기준.
- **파이프라인 목적 중심**: DQ/Recon/Analytics의 위험 지점을 우선 커버.
- **확장 가능**: 필요 시 행 수/케이스를 단계적으로 증설.

## 디렉터리/네이밍
- 시나리오: `mock_data/scenarios/<scenario>/<table>.jsonl`
- Bronze 미러: `mock_data/bronze/<table>_raw/<scenario>/data.jsonl`
- 생성: `mock_data_gen` 스크립트 활용

## 시나리오 목록 및 권장 행 수

### 1) one_day_normal
- 목적: 전체 파이프라인 정상 흐름 확인
- 행 수: 각 테이블 2~5행
- 커버: Silver 변환, 기본 조인, 기본 집계

### 2) dup_tx_id
- 목적: 중복 tx_id 감지 및 DQ duplicate rate 확인
- 대상: `transaction_ledger`
- 행 수: 6~10행 (중복 2~3개 포함)

### 3) missing_required
- 목적: 필수 컬럼 누락 → bad_records 격리
- 대상: `transaction_ledger`, `user_wallets` 등
- 행 수: 3~5행 (불량 1행)

### 4) invalid_amount
- 목적: `amount <= 0`, `balance < 0` 처리 확인
- 대상: `transaction_ledger`, `user_wallets`
- 행 수: 3~5행 (불량 1행)

### 5) unknown_entry_type
- 목적: 허용값 외 entry_type 처리 확인
- 대상: `transaction_ledger`
- 행 수: 3~5행 (불량 1행)

### 6) status_not_allowed
- 목적: 허용되지 않는 결제 상태 처리 확인
- 대상: `payment_orders`
- 행 수: 3~5행 (불량 1행)

### 7) stale_source
- 목적: freshness 경보 및 게이팅 태그 확인
- 대상: `transaction_ledger`, `user_wallets`
- 행 수: 5~10행 (ingested_at 과거)

### 8) zero_window
- 목적: completeness 연속 0 윈도우 카운트 확인
- 대상: 윈도우 내 **0행**

### 9) drift_mismatch
- 목적: `delta_balance_total` vs `net_flow_total` 불일치
- 대상: `wallet_snapshot`, `ledger_entries`
- 행 수: snapshot 2유저 x 2시점(4행), ledger 2~4행

### 10) supply_mismatch
- 목적: 발행량 vs 지갑합 불일치
- 대상: `ledger_entries`
- 행 수: 4~6행 (MINT/BURN 포함)

### 11) pairing_quality
- 목적: related_id 기반 페어링 품질 지표
- 대상: `ledger_entries`
- 행 수: 6~8행 (related_id 그룹 2~3개)

### 12) analytics_multi_item
- 목적: multi-item category 파생 규칙 확인
- 대상: `orders`, `order_items`, `products`, `payment_orders`
- 행 수: orders 1~2행, items 3~4행, products 3~4행

### 13) analytics_missing_product
- 목적: product 매칭 실패 시 category NULL 처리
- 대상: `order_items`, `products`
- 행 수: items 2행, products 1행

### 14) backfill_two_days
- 목적: 파티션 overwrite/멱등성 확인
- 대상: 주요 테이블 전반
- 행 수: `one_day_normal` x 2일치

### 15) bad_records_rate_exceed
- 목적: fail-fast 임계치(예: 1%) 초과 테스트
- 대상: 해당 테이블 단독
- 행 수: **50행 + 불량 1행**

## 우선순위(권장)
1. dup_tx_id, missing_required, invalid_amount
2. stale_source, zero_window
3. drift_mismatch, supply_mismatch
4. analytics_multi_item, analytics_missing_product
5. backfill_two_days, bad_records_rate_exceed

## 참고
- 임계치/룰은 `gold.dim_rule_scd2` 기준.
- 시나리오 확장은 테스트/통합 환경 준비 단계(Phase 9) 전까지 완료를 권장.
