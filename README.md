# Controls-first Ledger Pipelines

이 시스템은 결제/지갑 원장의 **일일 정합성 검증, 운영 이상 감지, 익명화 분석**을 자동화하는
Azure Databricks 배치 파이프라인이다.

Last updated: 2026-02-12

## 프로젝트 개요

이 파이프라인은 OLTP 서비스에서 하루치 거래가 끝난 뒤 "원장이 틀리지 않았는가", "이상 신호가 있는가", "데이터를 감사·분석에 쓸 수 있는가"를 자동으로 확인한다.

세 가지를 다룬다:
- **원장 통제**: 잔액 드리프트 감지, 공급량 정합성, 운영 지표 산출
- **데이터 품질 감시**: Bronze 입력의 신선도·중복·누락을 실시간 감시하고 이상 감지 시 downstream을 차단
- **익명화 분석**: PII 없는 결제 팩트 적재

## 왜 이 파이프라인이 필요한가

금융 시스템에서 원장 데이터의 정합성은 서비스 운영의 기본 요건이다.
잔액이 실제와 다르거나 공급량이 보존되지 않으면 고객 신뢰와 규제 요건 모두에 문제가 생긴다.
결제가 완료된 이후에도 이 정합성을 매일 독립적으로 검증해야 하고, 이 파이프라인은 그 검증을 자동화한다.

**문제 1 — 수동 대사의 한계**
하루 수십만 건의 거래 환경에서 원장 정합성을 사람이 직접 확인하는 것은 불가능하다.
배치 이후에야 오류를 발견하면 고객 정산 신뢰, 금융 리스크, 복구 비용이 급격히 커진다.

**문제 2 — 이상 감지 지연**
원장 이상은 늦게 발견될수록 연쇄 영향이 커진다.
입력 데이터 품질이 저하된 상태에서 대사 결과를 신뢰하면 허위 경보나 놓친 오류가 생긴다.

**문제 3 — 감사 추적 불가**
"언제, 어떤 기준으로 이 결과가 만들어졌는가"를 재현할 수 없으면 감사 대응이 불가능하다.
임계값이 하드코딩되어 있으면 변경 때마다 배포가 필요하고, 어떤 룰이 적용됐는지 기록도 남지 않는다.

## 이 파이프라인은 문제를 어떻게 해결하는가

**해결 1 — 계층형 통제 아키텍처**
Bronze(원본 보존) → Silver(계약 검증/격리) → Gold(통제 결과/분석) 3단계를 나눠,
각 계층이 다음 계층에 나쁜 데이터를 전파하기 전에 차단한다.
Silver의 `bad_records_rate`가 임계값을 초과하면 B/C 파이프라인은 실행을 거부(fail-closed)한다.

**해결 2 — 조기 경보 시스템(Pipeline A)**
배치 대사가 시작되기 전에 Pipeline A가 Bronze 입력의 신선도·중복·이벤트 누락을 10분 주기로 감시한다.
감지된 `dq_tags`(SOURCE_STALE, DUP_SUSPECTED 등)는 Pipeline B의 대사 결과에 소프트 게이트로 전파되어,
데이터가 알려진 불량 상태일 때 허위 경보를 억제한다.

**해결 3 — 자동화된 일일 대사 + 예외 원장(Pipeline B)**
"Δ잔액 = 순 흐름 합계"가 성립하는지 매일 자동 검증하고,
공급 총량·운영 지표·원장 페어링 품질을 `gold.exception_ledger` 단일 뷰에 집중한다.
임계값은 `gold.dim_rule_scd2`에서 런타임에 로딩되어 코드 배포 없이 조정할 수 있다.

**해결 4 — run_id/rule_id 기반 감사 추적**
Silver·Gold의 모든 출력 행에 `run_id`가 기록되고, 어떤 룰이 어떤 판단을 내렸는지 `rule_id`로 추적된다.
`gold.pipeline_state`에 실행 이력이 쌓여, 재실행 멱등성과 사후 감사 재현이 모두 보장된다.

## 파이프라인 구성

| 파이프라인 | 역할 | 운영 기준 |
|---|---|---|
| A (Guardrail) | Bronze 입력 품질 감시(`silver.dq_status`, 예외 기록) | 10분 주기 |
| Silver (Materialization) | Bronze -> Silver 계약 검증/표준화 + quarantine | 일배치 |
| B (Ledger Controls) | 일일 대사/공급 정합성/운영 지표 산출 | Silver 준비 상태 충족 시 실행 |
| C (Analytics) | 익명화 결제 팩트 산출 | Silver 준비 상태 충족 시 실행 |

의존성:
- `A -> Silver -> (B, C)`
- B/C는 `pipeline_silver.last_processed_end` 미충족 시 fail-closed로 즉시 실패합니다.

## 아키텍처

```text
Source DB
  -> Bronze (원본 보존)
  -> A: Guardrail DQ (품질 상태/예외)
  -> Silver (계약 검증 + 표준화 + bad_records quarantine)
  -> B: Ledger/Admin Controls (Recon/Supply/Ops/Admin)
  -> C: Analytics (Anonymized Facts)
```

## 주요 산출물

Silver:
- `silver.wallet_snapshot`
- `silver.ledger_entries`
- `silver.order_events`
- `silver.order_items`
- `silver.products`
- `silver.bad_records`
- `silver.dq_status`

Gold:
- `gold.recon_daily_snapshot_flow`
- `gold.ledger_supply_balance_daily`
- `gold.ops_payment_failure_daily`
- `gold.ops_payment_refund_daily`
- `gold.ops_ledger_pairing_quality_daily`
- `gold.admin_tx_search`
- `gold.fact_payment_anonymized`
- `gold.exception_ledger`
- `gold.pipeline_state`
- `gold.dim_rule_scd2`

## 실행 인터페이스

공통 파라미터(A/Silver/B/C):
- `run_mode`: `incremental` | `backfill`
- `start_ts`, `end_ts`: UTC window
- `date_kst_start`, `date_kst_end`: KST day window
- `run_id`

파이프라인별 추가 파라미터:
- A/Silver/B: `rule_load_mode`, `rule_table`, `rule_seed_path`
- C: `secret_scope`, `secret_key`, `salt`
- B/C: `--skip-upstream-readiness-check` (비상/수동 실행 우회)

기본 윈도우 해석:
- A: `run_mode`가 공백 또는 `incremental`이고 윈도우 파라미터가 모두 공백이면 자동 incremental 윈도우로 해석
  - `end_ts = now_utc`
  - `start_ts = pipeline_a.last_processed_end` 또는 `now_utc - 10분`
- B/C/Silver: `run_mode/start_ts/end_ts/date_kst_start/date_kst_end`가 모두 공백이면 전일(KST) 1일 backfill로 해석

## Databricks 워크플로우 진입점

정기 스케줄 jobs:

| Job | 목적 | 스케줄(KST) | 예시 |
|---|---|---|---|
| `pipeline_a_guardrail` | DQ guardrail 실행 | 매 10분 | `databricks bundle run pipeline_a_guardrail -t dev --params run_mode=incremental,run_id=manual_a_20260212` |
| `pipeline_silver_materialization` | Silver 물질화/격리 처리 | 매일 00:00 | `databricks bundle run pipeline_silver_materialization -t dev --params run_mode=backfill,date_kst_start=2026-02-11,date_kst_end=2026-02-11,run_id=manual_silver_20260212` |
| `pipeline_b_controls` | Recon/Supply/Ops/Admin 통제 | 매일 00:20 | `databricks bundle run pipeline_b_controls -t dev --params run_mode=backfill,date_kst_start=2026-02-11,date_kst_end=2026-02-11,run_id=manual_b_20260212` |
| `pipeline_c_analytics` | 익명화 분석 팩트 산출 | 매일 00:35 | `databricks bundle run pipeline_c_analytics -t dev --params run_mode=backfill,date_kst_start=2026-02-11,date_kst_end=2026-02-11,run_id=manual_c_20260212` |
| `bad_records_retention_cleanup` | bad_records 보존정리 | 매월 1일 00:50 | `databricks bundle run bad_records_retention_cleanup -t dev --params dry_run=true,retention_days=180` |

온디맨드 운영 jobs:

| Job | 목적 | 예시 |
|---|---|---|
| `bootstrap_catalog` | UC schema/table bootstrap | `databricks bundle run bootstrap_catalog -t dev` |
| `sync_dim_rule_scd2` | 룰 seed -> `gold.dim_rule_scd2` 반영 | `databricks bundle run sync_dim_rule_scd2 -t dev --params seed_path=mock_data/fixtures/dim_rule_scd2.json,table_name=gold.dim_rule_scd2` |

E2E jobs:

| Job | 목적 | 예시 |
|---|---|---|
| `e2e_setup_mock_data` | E2E용 mock data/테이블 준비 | `databricks bundle run e2e_setup_mock_data -t dev --params scenario=one_day_normal,run_id=e2e_setup_20260212` |
| `e2e_full_pipeline` | full workflow smoke | `databricks bundle run e2e_full_pipeline -t dev --params run_mode=backfill,date_kst_start=2026-02-11,date_kst_end=2026-02-11,run_id=e2e_full_20260212` |
| `e2e_cleanup_mock_data` | E2E 리소스 정리 | `databricks bundle run e2e_cleanup_mock_data -t dev --params drop_schemas=0` |

운영 장애 대응/복구 절차는 `.specs/ops/operations_runbook.md`를 SSOT로 사용합니다.

## 개발 및 검증 (Quickstart)

로컬 환경 준비:

```bash
python -m venv .venv
source .venv/bin/activate
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements-dev.txt
```

Unit 테스트:

```bash
.venv/bin/python -m pytest tests/unit/ -v -x
```

Integration 테스트(PySpark):

```bash
.venv/bin/python -m pip install -r requirements-spark.txt
.venv/bin/python -m pytest tests/integration/ -v
```

CI 게이트(`.github/workflows/ci.yml`):
- Unit coverage: `--cov-fail-under=80`
- Integration smoke coverage: `--cov-fail-under=60`

검증 증적 저장 경로:
- `.agents/logs/verification/`

참고:
- 문서 전용 변경은 정책상 L0-L2 생략 가능(AGENTS.md의 Exceptions 기준).

## 설정 및 보안

설정 우선순위:
- `CLI args > env vars > configs/{env}.yaml > configs/common.yaml`

환경변수 override:
- 패턴: `PIPELINE_CFG__<NESTED__KEY>`
- 존재하지 않는 키는 fail-fast로 오류 처리

룰 로딩 정책:
- A/B/Silver는 `rule_load_mode` 사용(`strict | fallback`)
- prod 문맥(`PIPELINE_ENV=prod`, `prod catalog` 등)에서는 `strict`만 허용

익명화 salt 해석 우선순위:
1. `ANON_USER_KEY_SALT`
2. Databricks Secret Scope (`analytics.secret_scope` + `analytics.secret_key`)
3. 로컬 fallback `local-salt-v1` (Databricks 런타임 외에서만 허용)

Databricks 런타임에서는 env/secret 모두 실패 시 fail-closed로 종료합니다.

## 참고 문서 (SSOT)

- `.specs/architecture_guide.md` — 팀 온보딩용 아키텍처 가이드
- `.specs/project_specs.md`
- `.specs/data_contract.md`
- `.specs/ops/operations_runbook.md`
- `.specs/ops/azure_monitoring_integration_plan.md`
- `tests/e2e/README.md`
