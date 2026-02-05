# 프로젝트 스펙 (Azure Databricks) — NSC Platform: Ledger Controls & Analytics (v1.0)

> **SSOT**: `.specs/SRS - Software Requirements Specification.md` (v1.1, 2026-01-30)  
> **DB 맥락**: `.specs/database_schema` (RDBMS 스키마 스냅샷)  
> **현재 커버 범위**: SRS 2.3(원장 및 관리자), 2.4(Analytics - OLAP)  
> **비범위(명시)**: SRS 2.1/2.2의 트랜잭션 처리(Freeze/Settle/Rollback 등) 및 ACID 원장 기록은 **Databricks 외부(OLTP RDBMS + Kafka)**에서 수행

---

## 1) 목적과 성공 기준

### 1.1 목적(Controls-first)

Databricks는 결제/지갑 서비스를 “대체”하지 않고, **원장 무결성 검증(controls)**과 **관리자 리포팅**, 그리고 **익명화된 분석용 적재(OLAP)**를 담당한다.

- **원장/관리자(2.3)**: “총 발행량 ↔ 사용자 잔액” 정합성, 일일 대사 결과, 이상 탐지/예외 로그
- **분석(2.4)**: 결제/주문 데이터를 익명화하여 Lakehouse에 적재(패턴/지표 생성). (시세 모니터링은 P3로 옵션)

### 1.2 완료 정의(DoD)

- 매일(자정 기준) **일일 대사 산출물**이 `gold`에 생성되고 예외가 `gold.exception_ledger`에 기록된다.
- `FR-ADM-01/03`에 대한 **자동 검증 지표**(drift / supply diff)가 재실행 시 **멱등**으로 수렴한다.
- 분석 적재(익명화) 파이프라인이 PII 없이 운영되고, 접근권한이 분리된다.
- 모든 잡이 `run_id`를 남기고, `gold.pipeline_state`에 성공 상태를 업데이트한다.

---

## 2) 시스템 경계(Out-of-scope 포함)

### 2.1 Databricks가 하는 일(In-scope)

- OLTP(서비스 DB)에서 추출된 테이블/덤프/CDC/Kafka 이벤트를 **Bronze에 적재**
- 계약(Contract) 기반으로 **Silver 정규화 + 검증(격리/Fail-fast)**
- **원장/관리자용 통제 결과(Gold)** 생성
  - 총량 정합성(supply vs wallet sum)
  - 일일 대사(delta balance vs net flow)
  - 예외 원장/알림 태깅
- **익명화된 분석용 데이터마트(Gold-mart)** 생성

### 2.2 Databricks가 하지 않는 일(명시적 비범위)

- 결제 Freeze/Settle/Rollback의 **트랜잭션 처리** 및 원장 쓰기
- ACID 보장(원장 원자성/격리성)은 **OLTP RDBMS** 책임
- 실시간(≤500ms) API 응답 SLA 제공(OLAP 플랫폼 특성상 비적합)
- FR-ADM-02(거래 내역 추적)의 **초단위 단건 조회(Serving)**: Backoffice DB + Admin API 영역(비범위, 상세: `.specs/backoffice_db_admin_api.md`)

---

## 3) 소스 데이터(SSOT: database_schema) 및 수집 방식

### 3.1 핵심 소스 테이블(현재 스키마)

> 실제 운영 DB명/스키마명은 환경 설정으로 주입한다.

- `user_wallets`: 사용자 지갑 잔액(가용/동결) 현행 상태
- `transaction_ledger`: 지갑 변동 이벤트 로그(원장)
- `payment_orders`: 결제 오더(상태/가맹점/금액)
- `orders`, `order_items`, `products`: 커머스 주문/상품(분석/패턴 용도)

확장 후보(향후): `krw_accounts`, `krw_transactions`, `naver_points` 등

### 3.2 SRS 핵심 엔티티 ↔ 소스 스키마 매핑(현재 스키마 기준)

| SRS 엔티티/필드 | 소스 테이블/컬럼 | Databricks(Silver) 표준 컬럼 | 비고 |
|---|---|---|---|
| UserWallet.`user_id` | `user_wallets.user_id` | `silver.wallet_snapshot.user_id` |  |
| UserWallet.`balance_available` | `user_wallets.balance` | `balance_available` |  |
| UserWallet.`balance_frozen` | `user_wallets.frozen_amount` | `balance_frozen` |  |
| UserWallet.`updated_at` | `user_wallets.updated_at` | `source_updated_at` |  |
| UserWallet.`wallet_address` | (미존재) | (미사용) | 지갑 서비스/블록체인 연동 영역(비범위) |
| TransactionLedger.`tx_id` | `transaction_ledger.tx_id` | `silver.ledger_entries.tx_id` |  |
| TransactionLedger.`timestamp` | `transaction_ledger.created_at` | `event_time` |  |
| TransactionLedger.`amount` | `transaction_ledger.amount` | `amount` | `DECIMAL(38,2)`로 표준화 권장 |
| TransactionLedger.`type` | `transaction_ledger.type` | `entry_type` | enum 정의는 룰 테이블로 관리 |
| TransactionLedger.`order_id` | `transaction_ledger.related_id` | `related_id` | `orders/order_items/payment_orders` 등과 연계 |
| TransactionLedger.`status` | `payment_orders.status` 등 | `status` | `related_id` 기반 조인/파생(미결정 시 NULL 허용) |
| TransactionLedger.`sender/receiver` | (직접 컬럼 미존재) | (파생) | double-entry 페어링 또는 업스트림 제공 필요 |

추가 전제/권장(스키마 충돌 방지):
- `orders.order_id`는 `BIGINT`, `payment_orders.order_id`는 `VARCHAR`이므로, `transaction_ledger.related_id`는 **문자열 표준**으로 취급한다.
- `related_id`가 어떤 도메인(ORDER vs PAYMENT_ORDER 등)을 참조하는지 모호하면, 업스트림에서 `related_type`(또는 `reference_type`) 컬럼을 제공하는 것을 권장한다.

### 3.3 수집(ingestion) 옵션

- **옵션 A: 파일 덤프(권장, 개발/초기 운영)**: CSV/Parquet + `source_extracted_at`, `batch_id`
- **옵션 B: Read-only DB 연결**: 증분 기준은 `created_at/updated_at` 또는 배치 단위 snapshot
- **옵션 C: Kafka 이벤트 스트리밍(선택)**: 결제/원장 이벤트 토픽을 Structured Streaming으로 Bronze에 적재

### 3.4 향후 확장: CDC (Phase 2)

현재는 파일 덤프 방식으로 개발/검증 완료 후, 운영 단계에서 CDC 전환 검토:

- Kafka + Schema Registry 기반
- Structured Streaming으로 Bronze 실시간 적재
- 전환 조건: 소스 DB 안정화 및 Kafka 인프라 구축 완료

---

## 4) 레이어 설계(Bronze/Silver/Gold)

### 4.1 Bronze(원본 적재)

원칙: 원본을 최대한 보존, append-only, 재처리 가능

- `bronze.user_wallets_raw`
- `bronze.transaction_ledger_raw`
- `bronze.payment_orders_raw`
- `bronze.orders_raw`
- `bronze.order_items_raw`
- `bronze.products_raw`

공통 메타(권장):
- `ingested_at`(UTC), `source_extracted_at`, `batch_id`, `source_system`

Bronze 스키마(컬럼/타입/필수 여부)는 `.specs/data_contract.md`의
2장(OLTP → Bronze 계약)을 SSOT로 사용한다.

### 4.2 Silver(계약/정규화 + 검증)

#### 4.2.1 Silver 계약 핵심(원장/관리자)

- `silver.wallet_snapshot`
  - 목적: reconciliation을 위한 “시점 스냅샷” 구성
  - 핵심 컬럼(예시)
    - `snapshot_ts`(UTC), `snapshot_date_kst`
    - `user_id`
    - `balance_available`(= `user_wallets.balance`)
    - `balance_frozen`(= `user_wallets.frozen_amount`)
    - `balance_total`(= available + frozen)
    - `source_updated_at`(= `user_wallets.updated_at`), `run_id`, `rule_id`

- `silver.ledger_entries`
  - 목적: 일일 대사/총량 검증을 위한 원장 엔트리 표준화
  - 핵심 컬럼(예시)
    - `tx_id`(PK 후보), `event_time`(= `transaction_ledger.created_at`)
    - `wallet_id`(= `transaction_ledger.wallet_id`)
    - `entry_type`(= `transaction_ledger.type`)
    - `amount`(decimal), `amount_signed`(필수: +/−)
    - `related_id`(주문/결제/정산 등 외부참조)
    - `status`(가능하면 `payment_orders.status` 등에서 조인/파생)
    - `run_id`, `rule_id`
  - **중요(소스 요구사항)**: 대사 가능성을 위해 `amount_signed` 또는 `(debit/credit role)`이 반드시 결정 가능해야 한다.
    - 소스가 이를 제공하지 않으면 Bronze→Silver 변환 단계에서 룰로 파생(타입 매핑)하되, 파생 불가 시 bad_records로 격리한다.

- `silver.dq_status` / `silver.bad_records_*`: 계약 위반/품질 이슈

#### 4.2.2 Silver 계약(Analytics)

- `silver.order_events`: orders + payment_orders 정규화
- `silver.order_items` / `silver.products`: 분석 차원/팩트 구성

PII 제거 원칙:
- `users`, `accounts` 등 PII/credential 테이블은 기본적으로 분석 레이어에 적재하지 않는다.
- 분석용 user key는 `sha2(user_id + salt)`로 pseudonymization 한다(Secret Scope/Key Vault에서 salt 관리).

### 4.3 Gold(통제 결과 + 마트)

#### 4.3.1 공통 테이블(고정)

- `gold.exception_ledger`: 단일 예외 원장(dq/ledger/analytics)
- `gold.pipeline_state`: 실행 상태(state store)
- `gold.dim_rule_scd2`: 룰/임계치 SCD2(하드코딩 금지)

#### 4.3.2 원장/관리자 산출물(2.3)

- `gold.ledger_supply_balance_daily`
  - `date_kst`, `issued_supply`, `wallet_total_balance`, `diff_amount`, `is_ok`, `run_id`, `rule_id`
  - FR-ADM-01 대응

- `gold.recon_daily_snapshot_flow`
  - `date_kst`, `user_id`, `delta_balance_total`, `net_flow_total`, `drift_abs`, `drift_pct`, `dq_tag`, `run_id`, `rule_id`
  - FR-ADM-03 대응

- (옵션) `gold.admin_tx_search`
  - `tx_id` 기준 조회를 위한 “배치 인덱스(감사/분석용)” 뷰/테이블
  - FR-ADM-02의 **초단위 Serving**은 Backoffice DB + Admin API가 SSOT(본 테이블은 보조 경로)

- `gold.ops_payment_failure_daily`
  - `date_kst`, `merchant_name`, `total_cnt`, `failed_cnt`, `failure_rate`, `run_id`, `rule_id`
  - 운영 지표(추가): 결제 실패율(실패 정의는 룰/합의로 고정)

- `gold.ops_ledger_pairing_quality_daily`
  - `date_kst`, `entry_cnt`, `related_id_null_rate`, `pair_candidate_rate`, `join_payment_orders_rate`, `run_id`, `rule_id`
  - 운영 지표(추가): `related_id` 기반 PAYMENT/RECEIVE 페어링 품질(방법2 가정)

#### 4.3.3 분석 산출물(2.4)

- `gold.fact_payment_anonymized`
  - `date_kst`, `user_key`, `merchant_name`, `amount`, `status`, `category`, `run_id`
  - FR-ANA-01 대응(P3)

- (옵션) `gold.fact_market_price`
  - `symbol`, `ts`, `price`, `source`
  - FR-ANA-02 대응(P3)

### 4.4 Delta Lake 최적화 전략

#### 4.4.1 Hive 스타일 파티셔닝

- Silver/Gold 테이블은 `date_kst` 기준 Hive 스타일 파티셔닝 적용
- 예: `PARTITIONED BY (date_kst DATE)`
- 쿼리 성능 최적화 및 백필 시 파티션 단위 덮어쓰기 지원
- Bronze는 파티셔닝 없이 append-only 유지 (원본 보존)

#### 4.4.2 스키마 에볼루션

- Bronze 계층: `mergeSchema = true` 옵션으로 스키마 자동 확장 허용
  - 소스 스키마 변경 시 자동 반영 (컬럼 추가)
  - 감사 목적으로 원본 형태 최대한 보존
- Silver/Gold 계층: 스키마 변경은 **명시적 마이그레이션** 필요
  - 계약(Contract) 기반이므로 임의 확장 금지
  - 변경 시 data_contract.md 버전업 + 마이그레이션 스크립트

#### 4.4.3 Databricks 캐시

- 자주 조인되는 차원 테이블에 Delta Cache 적용
  - `gold.dim_rule_scd2` (룰/임계치)
  - (향후) 사용자 차원, 가맹점 차원
- 캐시 힌트: `spark.conf.set("spark.databricks.io.cache.enabled", "true")`
- 주의: 대용량 팩트 테이블은 캐시 대상에서 제외

---

## 5) 파이프라인(Workflows/Jobs)

### 5.1 공통 실행 파라미터(표준)

- `run_mode`: `incremental | backfill`
- `start_ts`, `end_ts`: timestamp window(UTC)
- `date_kst_start`, `date_kst_end`: 일 단위 backfill
- `run_id`: 모든 출력/예외/상태에 기록

### 5.2 Pipeline A — Guardrail(DQ, 10분)

목적: 후속 통제(대사/총량)의 “해석 가능성” 확보

- 대상 소스: `transaction_ledger`, `user_wallets`, `payment_orders`, `orders`(필요 시)
- 메트릭
  - freshness: `now - max(ingested_at)` / `now - max(source_updated_at)`
  - completeness: 윈도우별 event_count, 0건 지속
  - duplicates: `tx_id`/결정키 중복률
  - contract: 필수키 NULL, amount 범위, status 값 등
- 산출
  - `silver.dq_status`
  - `gold.exception_ledger`에 `SOURCE_STALE`, `EVENT_DROP_SUSPECTED`, `DUP_SUSPECTED` 등 기록

### 5.3 Pipeline B — Ledger & Admin Controls(일일 자정)

목적: FR-ADM-01/03 자동 검증

- 스케줄: 매일 **KST 00:00 기준** (실행은 00:05~00:15 허용), 대상 날짜 `date_kst = D`
- 입력
  - `silver.wallet_snapshot`(D 시작/끝 스냅샷 선택 규칙 적용)
  - `silver.ledger_entries`(event_time을 KST day로 버킷)
- 처리(핵심 통제)
  1) **일일 대사(Δ잔고 = 순흐름)**
     - `delta_balance_total = balance_total_end - balance_total_start`
     - `net_flow_total = SUM(amount_signed)` (동일 day, 동일 user 기준)
     - `drift = delta - net_flow`
  2) **총량 정합성(발행량 ↔ 잔액 합)**
     - `issued_supply` 산정
       - 1차: 원장 타입 기반 합산(예: MINT/CHARGE는 +, BURN/WITHDRAW는 −)
       - 2차(권장): OLTP가 제공하는 “발행량 스냅샷 테이블”이 있으면 이를 SSOT로 사용
     - `wallet_total_balance = SUM(balance_total_end)`
- 게이팅
  - Pipeline A가 stale/drop이면 예외 severity 하향 또는 알림 억제(계산은 수행)
- 산출
  - `gold.recon_daily_snapshot_flow`
  - `gold.ledger_supply_balance_daily`
  - `gold.exception_ledger`에 `RECON_DRIFT_HIGH`, `SUPPLY_MISMATCH` 등 기록
  - (운영 지표) `gold.ops_payment_failure_daily`
  - (운영 지표) `gold.ops_ledger_pairing_quality_daily`
  - (옵션/보조 경로) `gold.admin_tx_search`

### 5.4 Pipeline C — Analytics(익명화 적재)

목적: FR-ANA-01(P3) 지원

- 스케줄: 일배치(기본) 또는 필요 시 스트리밍
- 처리
  - 주문/결제 이벤트를 익명화(`user_key`)하여 Gold-mart 생성
  - PII/credential 컬럼 제거 및 스키마 고정
- 산출
  - `gold.fact_payment_anonymized` 등

### 5.5 (옵션) Market Price Ingestion

FR-ANA-02(P3). 외부 API(업비트 등) → Bronze 적재 → Gold 집계.

### 5.6 재시도 및 알림 정책

#### 5.6.1 재시도 정책

- Databricks Workflow 레벨에서 재시도 설정
- 최대 재시도: 2회, 간격: 5분
- 재시도 대상: 일시적 오류(네트워크, 클러스터 시작 등)
- 재시도 제외: 데이터 품질 오류, 스키마 불일치 등 논리적 오류

#### 5.6.2 알림 정책

- `gold.exception_ledger`에 `severity = CRITICAL` 기록 시 알림 트리거
- 채널: Slack/Email (환경 설정으로 관리)
- 알림 억제: Pipeline A가 `SOURCE_STALE` 감지 시 Pipeline B/C 알림 억제 (게이팅)

---

## 6) 요구사항 매핑(Traceability)

| SRS ID | 요구사항 | Databricks 산출물 | 상태/비고 |
|---|---|---|---|
| FR-ADM-01 | 전체 원장 조회(총 발행량 vs 잔액 총합) | `gold.ledger_supply_balance_daily` | P1 / 일배치 |
| FR-ADM-02 | 거래 내역 추적(tx_id) | `gold.admin_tx_search`(옵션) | P2 / Serving(초단위)=BO DB+Admin API, Lakehouse=배치 인덱스(보조) |
| FR-ADM-03 | 일일 대사(거래 로그 합 vs 최종 잔액) | `gold.recon_daily_snapshot_flow` | P2 / KST day |
| FR-ANA-01 | 결제 패턴 수집(익명화) | `gold.fact_payment_anonymized` | P3 / 스코프 포함(옵션) |
| FR-ANA-02 | 실시간 시세 모니터링 | `gold.fact_market_price`(옵션) | P3 / 추후 |

---

## 7) Decision Lock(초기 고정값)

> 운영 중 변경은 `gold.dim_rule_scd2` 버전업으로만 관리(코드/문서 하드코딩 금지)

### 7.1 시간/경계

- 저장/계산: UTC
- 일일 기준: KST (`date_kst`)
- 윈도우: `[start, end)` (start 포함, end 미포함)

### 7.2 금액 타입/반올림

- Databricks 금액 컬럼은 `DECIMAL(38, 2)`(KRW) 또는 자산별 스케일 정책을 명시한다.
- 집계 시 반올림 규칙을 고정한다(필요 시 룰로 관리).

### 7.3 원장 엔트리 부호 규칙

- `amount_signed`는 필수이다.
- 타입 매핑 예시(초기 가정, 확정 시 룰 테이블로 관리)
  - `MINT`/`CHARGE`: `+amount`
  - `BURN`/`WITHDRAW`: `-amount`
  - `PAYMENT`: 송신자 `-amount`, 수신자 `+amount`(double-entry 페어링 필요)
  - `HOLD`/`RELEASE`: balance_available ↔ balance_frozen 이동(총량 0)

---

## 8) 룰/임계치/버전 관리

- 모든 임계치(예: drift 경보 기준, stale 기준, dup_rate)는 `gold.dim_rule_scd2`에서 관리한다.
- 모든 산출물/예외에는 `rule_id`를 기록한다.
- 변경 = 룰 버전업(SCD2)

---

## 9) 실행 상태/멱등성/백필

### 9.1 state store

- `gold.pipeline_state(pipeline_name, last_success_ts, last_processed_end, last_run_id, updated_at)`

### 9.2 멱등성

Silver/Gold는 MERGE 키를 명확히 정의한다.

- `silver.wallet_snapshot`: `(snapshot_ts, user_id)`
- `silver.ledger_entries`: `(tx_id, wallet_id)` 또는 `(tx_id, entry_seq)`
- `gold.recon_daily_snapshot_flow`: `(date_kst, user_id)`
- `gold.ledger_supply_balance_daily`: `(date_kst)`

### 9.3 백필

- `date_kst_start~end` 지정 시 해당 구간 재계산(필요 시 최근 N일 재계산 옵션)

---

## 10) 테스트/검증

### 10.1 테스트 레벨

#### 10.1.1 단위 테스트 (Unit)

- 대상: `src/transforms/` 순수 함수
- 도구: pytest + mock DataFrames
- 실행: 로컬 (Spark 세션 불필요)
- 예시:
  - `test_derive_amount_signed()`: entry_type → 부호 변환
  - `test_calculate_net_flow()`: 일별 순흐름 계산
  - `test_validate_wallet_snapshot()`: 스키마 검증

#### 10.1.2 통합 테스트 (Integration)

- 대상: `src/io/` + `src/transforms/` 연동
- 도구: pytest + PySpark (로컬 Spark 세션)
- 실행: 로컬 또는 CI 환경
- 예시:
  - `test_bronze_to_silver_transform()`: 계층 간 변환
  - `test_bad_records_quarantine()`: 격리 테이블 적재

#### 10.1.3 E2E 테스트 (End-to-End)

- 대상: 전체 파이프라인 (`src/jobs/`)
- 도구: Databricks Dev 클러스터
- 실행: 원격 (Delta Lake, Unity Catalog)
- 예시:
  - `test_pipeline_a_guardrail()`: DQ 메트릭 생성 검증
  - `test_pipeline_b_recon()`: 대사 결과 정합성
  - `test_idempotency()`: 동일 입력 재실행 시 결과 수렴

### 10.2 테스트 케이스 유형

| 유형 | 설명 | 예시 |
|------|------|------|
| **정상 (Happy Path)** | 기대 입력 → 기대 출력 | 정상 거래 → drift = 0 |
| **엣지 (Edge Case)** | 경계값, 빈 데이터 | 거래 0건 날짜, 잔액 0원 |
| **오류 (Error Case)** | bad records, 스키마 불일치 | NULL tx_id → 격리 |
| **멱등성 (Idempotency)** | 재실행 시 결과 동일 | MERGE 후 중복 없음 |

### 10.3 Mock 데이터 전략

#### 10.3.1 저장 위치

```
mock_data/
├── bronze/
│   ├── user_wallets_raw/
│   ├── transaction_ledger_raw/
│   └── payment_orders_raw/
├── scenarios/
│   ├── happy_path/          # 정상 케이스
│   ├── edge_cases/          # 경계값 케이스
│   └── error_cases/         # 오류 케이스
└── fixtures/
    └── dim_rule_scd2.json   # 룰 테이블 시딩
```

#### 10.3.2 생성 원칙

- 최소 데이터: 테스트 목적에 필요한 최소 레코드만
- 결정적 데이터: 랜덤 값 대신 고정 시드 또는 하드코딩
- 시나리오별 분리: 독립 실행 가능한 데이터셋

#### 10.3.3 주요 시나리오

| 시나리오 | 설명 | 검증 포인트 |
|----------|------|-------------|
| `one_day_normal` | 1일치 정상 거래 | drift = 0, 예외 없음 |
| `stale_source` | 오래된 ingested_at | SOURCE_STALE 예외 |
| `duplicate_tx` | 중복 tx_id | DUP_SUSPECTED 예외 |
| `bad_amount` | amount = NULL | bad_records 격리 |
| `multi_day_backfill` | 3일치 백필 | 파티션별 멱등성 |

### 10.4 품질 게이트

#### 10.4.1 커버리지 목표

| 레벨 | 목표 | 필수 |
|------|------|------|
| Unit | ≥ 80% | ✅ |
| Integration | ≥ 60% | ⭕️ |
| E2E | 주요 시나리오 통과 | ✅ |

#### 10.4.2 필수 통과 기준

- PR 머지 전: 모든 Unit 테스트 통과
- main 머지 후: E2E 스모크 테스트 통과
- 배포 전: 멱등성 테스트 통과

#### 10.4.3 테스트 실패 시

- Unit 실패: PR 머지 차단
- E2E 실패: 롤백 또는 수동 검토
- 알림: Slack/Email (섹션 5.6 정책 적용)

---

## 11) CI/CD 파이프라인

### 11.1 PR 게이트

- 플랫폼: GitHub Actions / Azure DevOps
- 트리거: PR 생성/업데이트
- 실행: `pytest tests/unit/` (로컬 mock 테스트)
- 통과 조건: 모든 테스트 성공

### 11.2 Merge 게이트

- 트리거: main 브랜치 머지
- 실행: Dev 클러스터에서 `tests/integration/` 스모크 테스트
- 통과 조건: E2E 파이프라인 정상 완료
- 실패 시: 롤백 또는 수동 검토

### 11.3 배포 (선택)

- 도구: Databricks Asset Bundles 또는 dbx
- 환경: dev → prod 순차 배포
- 배포 전략: Blue-Green 또는 Canary (향후)

---

## 12) 개발 환경 전략

### 12.1 개발 방식 개요

**단계적 접근**: 로컬 IDE 개발 → Databricks Connect 원격 테스트 → Databricks 웹플랫폼 운영

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Phase 1        │    │  Phase 2        │    │  Phase 3        │
│  로컬 개발       │ →  │  원격 테스트     │ →  │  플랫폼 운영     │
│                 │    │                 │    │                 │
│ • VSCode/PyCharm│    │ • DB Connect    │    │ • Databricks UI │
│ • pytest + mock │    │ • Dev 클러스터   │    │ • Workflows     │
│ • 로컬 Spark    │    │ • Delta Lake    │    │ • Asset Bundles │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 12.2 Phase 1: 로컬 개발 (현재 단계)

**목적**: 빠른 반복 개발, transform 로직 검증

| 항목 | 설정 |
|------|------|
| IDE | VSCode / PyCharm |
| Python | 3.10+ (venv 또는 conda) |
| 테스트 | pytest + mock DataFrames |
| Spark | 로컬 PySpark (통합 테스트 시) |
| 데이터 | `mock_data/` 폴더 |

**로컬에서 가능한 작업**:
- `src/transforms/` 순수 함수 개발 및 단위 테스트
- 스키마 검증, 데이터 변환 로직
- 로컬 PySpark로 통합 테스트 (Delta Lake 미사용)

**로컬에서 불가능한 작업**:
- Delta Lake MERGE/Time Travel
- Unity Catalog 접근
- Databricks 전용 기능 (Auto Loader, Delta Live Tables 등)

### 12.3 Phase 2: Databricks Connect 원격 테스트

**목적**: Delta Lake, Unity Catalog 등 Databricks 전용 기능 검증

#### 12.3.1 Databricks Connect 설정

```bash
# 설치
pip install databricks-connect

# 설정 (databricks.yml 또는 환경변수)
databricks configure --profile dev
```

필수 설정:
- `DATABRICKS_HOST`: 워크스페이스 URL
- `DATABRICKS_TOKEN`: PAT (Personal Access Token)
- `DATABRICKS_CLUSTER_ID`: Dev 클러스터 ID

#### 12.3.2 Dev 클러스터 요구사항

- DBR 13.3 LTS 이상 (Databricks Connect 호환)
- Unity Catalog 활성화
- Single User 또는 Shared 모드
- Auto-termination: 30분 (비용 절감)

#### 12.3.3 Dev 카탈로그 구조

```
dev_catalog/
├── bronze/
│   ├── user_wallets_raw
│   ├── transaction_ledger_raw
│   └── payment_orders_raw
├── silver/
│   ├── wallet_snapshot
│   ├── ledger_entries
│   └── dq_status
└── gold/
    ├── recon_daily_snapshot_flow
    └── exception_ledger
```

#### 12.3.4 Mock 데이터 업로드

로컬 `mock_data/` → `dev_catalog.bronze` 업로드 스크립트 제공 (`scripts/upload_mock_data.py`)

### 12.4 Phase 3: Databricks 웹플랫폼 이전

**목적**: 운영 환경 배포, 스케줄링, 모니터링

#### 12.4.1 코드 동기화 방식

| 옵션 | 설명 | 권장 |
|------|------|------|
| **Databricks Repos** | Git 연동, 웹 UI에서 편집 가능 | 초기 개발 |
| **Asset Bundles (DAB)** | IaC 방식, CI/CD 친화적 | 운영 배포 |

#### 12.4.2 Workflows 정의

- YAML 기반 Job 정의 (`databricks.yml`)
- 환경별 파라미터 오버라이드 (dev/prod)
- 클러스터 정책 적용

#### 12.4.3 이전 체크리스트

**Phase 2 진입 전**:
- [ ] Databricks 워크스페이스 접근 권한 확인
- [ ] PAT 발급 및 Secret 저장
- [ ] Dev 클러스터 생성/할당
- [ ] Databricks Connect 연결 테스트

**Phase 3 진입 전**:
- [ ] E2E 테스트 전체 통과
- [ ] Unity Catalog 스키마 생성 (prod_catalog)
- [ ] Asset Bundles 또는 Repos 설정
- [ ] Workflow 정의 및 테스트 실행
- [ ] 알림 채널 연동 (Slack/Email)
- [ ] 운영팀 리뷰 및 승인

### 12.5 환경별 설정 관리

```
configs/
├── dev.yaml      # 로컬/Dev 클러스터
├── prod.yaml     # 운영 환경
└── common.yaml   # 공통 설정
```

**환경 변수 우선순위**: 환경변수 > configs/{env}.yaml > configs/common.yaml

**Secrets 관리**:
- 로컬: `.env` (gitignore)
- Databricks: Secret Scope (Azure Key Vault 연동)

### 12.6 제약사항 및 고려사항

| 항목 | 로컬 | Databricks Connect | 웹플랫폼 |
|------|------|-------------------|----------|
| Delta Lake | ❌ (OSS Delta만) | ✅ | ✅ |
| Unity Catalog | ❌ | ✅ | ✅ |
| Auto Loader | ❌ | ⚠️ 제한적 | ✅ |
| Photon | ❌ | ✅ | ✅ |
| Structured Streaming | ⚠️ 로컬만 | ⚠️ 제한적 | ✅ |
| 디버깅 | ✅ 풀 지원 | ⚠️ 제한적 | ❌ |

**Databricks Connect 제한사항**:
- 일부 RDD 연산 미지원
- Structured Streaming 제한적 지원
- 클러스터 시작 대기 시간 (cold start)

---

## Appendix: dim_rule_scd2 초기 시딩 예시(초안)

| rule_id | domain | metric | threshold | severity_map | comment |
|---|---|---|---:|---|---|
| `dq_freshness_default` | dq | freshness_sec | 300 | `{"warn":300,"crit":600}` | 소스별 SLO로 조정 |
| `dq_dup_txid_default` | dq | dup_rate_tx_id | 0.001 | `{"warn":0.001,"crit":0.01}` | tx_id 중복률 |
| `ledger_recon_abs_default` | ledger | drift_abs | 0 | `{"crit":0}` | 0 이외는 모두 불일치(초안) |
| `ledger_supply_diff_default` | ledger | supply_diff_abs | 0 | `{"crit":0}` | 총량 불일치 허용 0 |
| `silver_bad_records_default` | silver | bad_records_rate | 0.01 | `{"fail":0.01}` | 1% 초과 시 fail-fast |
