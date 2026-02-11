# L3 Databricks Dev E2E Runbook

Last updated: 2026-02-09  
Planned run date: 2026-02-10

## 0. 범위/비범위 (중요)

이 문서는 **기존 Databricks Workspace/Unity Catalog가 이미 준비되어 있다는 전제**에서, mock data 기반으로 A/B/C를 E2E로 실행하고 테이블을 정리(drop)하는 절차를 다룹니다.

- 범위: UC 스키마/테이블 생성, mock bronze 적재, silver materialize, A/B/C 실행, 테이블 정리
- 비범위: **Azure 리소스 생성/폐기(새 Databricks Workspace 생성, ADLS Storage Account/Container 생성/삭제)**  
  이 단계는 권한/시간/비용이 크고, 현재 리포에는 IaC(테라폼/바이스프) 자동화가 없습니다. 필요하면 `.specs/cloud/cloud_migration_rebuild_plan.md`를 먼저 기준으로 삼고, 별도 인프라 런북을 준비해야 합니다.

## 1. 목적 (왜 L3가 필요한가)

로컬 L1/L2(Unit/Integration)는 변환 로직과 일부 PySpark 동작을 검증하지만, 아래 항목은 Databricks Dev E2E(L3)에서만 현실적으로 검증됩니다.

- Unity Catalog 권한/스키마/테이블 생성 및 참조
- Delta `MERGE`/파티션 overwrite(`replaceWhere`) 동작
- Job 파라미터 전달(`run_mode`, `date_kst_*`, `run_id`)과 실제 테이블 업데이트
- Secret Scope 기반 salt 주입(파이프라인 C)
- (가능하면) 동일 입력 재실행 시 결과가 안정적인지(특히 B/C)

## 2. 역할 분담 (너 vs Codex)

| 항목 | 네가 준비/실행 | Codex가 준비 |
|---|---|---|
| 인증 | `DATABRICKS_HOST/TOKEN` 또는 CLI profile 준비 | runbook/명령어 제공 |
| UC 권한 | 대상 `catalog`에 `USE CATALOG/SCHEMA`, `CREATE`, `SELECT`, `MODIFY` 확인 | 검증 쿼리 제공 |
| Secret | Scope/Key 준비(또는 생성/삭제) | 필요한 Scope/Key 명시 |
| 실행 | Setup → A/B/C 실행 → 검증 → Cleanup 수행 | Setup/Cleanup 스크립트 및 실행 순서 문서화 |
| 증적 | `.agents/logs/verification/`에 로그/결과 남김 | 증적 템플릿/체크리스트 제공 |

## 3. 사전 준비 체크리스트 (2026-02-10 실행 전)

- [ ] Databricks CLI 설치 확인: `databricks --version`
- [ ] 인증 정보 준비(둘 중 하나):
- [ ] 환경변수: `export DATABRICKS_HOST=...` + `export DATABRICKS_TOKEN=...`
- [ ] 또는 profile: `databricks auth login --host https://...` (토큰은 로컬에만 저장, 커밋 금지)
- [ ] 인증 확인: `databricks auth describe -o json`
- [ ] (선택) ADLS/External Location까지 구성된 환경에서만: `scripts/phase7/audit_cloud_state.sh` 실행  
  ADLS가 없는 환경이면 이 단계는 건너뛰고, 아래 최소 점검으로 대체합니다.
- [ ] 최소 점검(ADLS 없어도 가능):
- [ ] `databricks current-user me -o json`
- [ ] `databricks secrets list-scopes -o json`
- [ ] `databricks cluster-policies list -o json` (워크스페이스에서 policy 강제하는지 확인)
- [ ] Bundle 타겟 확인: `databricks bundle validate -t dev`
- [ ] 대상 UC 카탈로그 결정(기본 dev): `databricks.yml`의 `targets.dev.variables.catalog`
- [ ] (권장) 가능하면 “테스트 전용 카탈로그”를 사용(테이블 drop/overwrite 안전)
- [ ] Secret Scope 확인(파이프라인 C) 기본값: scope=`ledger-analytics-dev`, key=`salt_user_key`
- [ ] Scope 존재 확인: `databricks secrets list-scopes`
- [ ] Scope 내 secret 키 확인: `databricks secrets list-secrets ledger-analytics-dev`
- [ ] (선택) `jq` 설치: `scripts/e2e/run_databricks_smoke.sh`에서 `SMOKE_WAIT=1` 사용 시 필요

## 4. 실행 파라미터 (권장값)

Mock 데이터의 기준일이 `2026-02-01`인 케이스가 많아서, L3는 **backfill**로 돌리는 게 가장 재현성이 좋습니다.

- `run_mode=backfill`
- `date_kst_start=2026-02-01`
- `date_kst_end=2026-02-01`
- `run_id=l3_e2e_20260210` (idempotency 확인을 위해 재실행 시 동일하게 사용)

## 5. 실행 절차 (Step-by-step)

### 5.0 실행 계획표

| Step | Owner | Action | Evidence |
|---|---|---|---|
| 1 | You | Bundle deploy (필요 시) | `.agents/logs/verification/L3_bundle_deploy_20260210.txt` |
| 2 | You | Setup: UC 스키마 + mock bronze + silver materialize | `.agents/logs/verification/L3_setup_20260210.txt` |
| 3 | You | Secret 준비(scope/key) | (CLI 출력 로그) |
| 4 | You | Pipeline A 실행(backfill) | `.agents/logs/verification/L3_pipeline_a_20260210.txt` |
| 5 | You | Pipeline B 실행(backfill) | `.agents/logs/verification/L3_pipeline_b_20260210.txt` |
| 6 | You | Pipeline C 실행(backfill) | `.agents/logs/verification/L3_pipeline_c_20260210.txt` |
| 7 | You | Idempotency: B/C 재실행 | `.agents/logs/verification/L3_pipeline_b_rerun_20260210.txt`, `.agents/logs/verification/L3_pipeline_c_rerun_20260210.txt` |
| 8 | You | Cleanup: 테이블 drop | `.agents/logs/verification/L3_cleanup_20260210.txt` |

### 5.1 Bundle Deploy (필요 시)

변경사항이 있었거나, Dev에 아직 배포가 안 되어 있으면:

```bash
databricks bundle validate -t dev
databricks bundle deploy -t dev --auto-approve | tee .agents/logs/verification/L3_bundle_deploy_20260210.txt
```

### 5.2 테스트 리소스 생성 + Mock 데이터 적재 (Setup)

번들에 포함된 Setup Job(`e2e_setup_mock_data`)가 아래를 수행합니다.

- UC 스키마 생성: `${catalog}.bronze/.silver/.gold`
- 기존 테이블 drop (기본: enabled)
- Mock bronze 적재
- Silver 필수 테이블 materialize: `silver.wallet_snapshot`, `silver.ledger_entries`, `silver.order_events`, `silver.order_items`, `silver.products`

권장 실행:

```bash
databricks bundle run e2e_setup_mock_data -t dev --params run_id=l3_setup_20260210 \
  | tee .agents/logs/verification/L3_setup_20260210.txt
```

시나리오를 특정하고 싶으면 `--params scenario=one_day_normal,run_id=l3_setup_20260210` 처럼 넣습니다. (기본은 `mock_data/bronze/*/data.jsonl` 사용)

### 5.3 Secret 준비 (파이프라인 C 필수)

파이프라인 C는 Databricks 런타임에서 로컬 fallback을 허용하지 않으므로, 아래 둘 중 하나가 필요합니다.

1) Secret Scope 방식(기본):

```bash
databricks secrets create-scope ledger-analytics-dev --initial-manage-principal users || true
databricks secrets put-secret ledger-analytics-dev salt_user_key --string-value "test-salt-20260210"
```

2) (대안) Job에 `ANON_USER_KEY_SALT` env var 주입:
현재 `databricks.yml`에는 설정되어 있지 않으므로, 이 방식은 추가 작업이 필요합니다.

### 5.4 Pipeline A/B/C 실행 (L3 본 실행)

#### A: Guardrail (Pipeline A)

```bash
databricks bundle run pipeline_a_guardrail -t dev \
  --params run_mode=backfill,date_kst_start=2026-02-01,date_kst_end=2026-02-01,run_id=l3_e2e_20260210 \
  | tee .agents/logs/verification/L3_pipeline_a_20260210.txt
```

#### B: Recon/Controls (Pipeline B)

```bash
databricks bundle run pipeline_b_controls -t dev \
  --params run_mode=backfill,date_kst_start=2026-02-01,date_kst_end=2026-02-01,run_id=l3_e2e_20260210 \
  | tee .agents/logs/verification/L3_pipeline_b_20260210.txt
```

#### C: Analytics (Pipeline C)

```bash
databricks bundle run pipeline_c_analytics -t dev \
  --params run_mode=backfill,date_kst_start=2026-02-01,date_kst_end=2026-02-01,run_id=l3_e2e_20260210 \
  | tee .agents/logs/verification/L3_pipeline_c_20260210.txt
```

### 5.5 Idempotency 확인 (최소: B/C)

동일 파라미터(특히 동일 `run_id`)로 B/C를 1회 더 실행하고 결과가 동일한지 확인합니다.

- Pipeline B: merge 전략이므로 동일 키 upsert로 안정적이어야 함
- Pipeline C: `overwrite_partitions + replaceWhere`로 동일 날짜 파티션이 안정적이어야 함

```bash
databricks bundle run pipeline_b_controls -t dev --params run_mode=backfill,date_kst_start=2026-02-01,date_kst_end=2026-02-01,run_id=l3_e2e_20260210 \
  | tee .agents/logs/verification/L3_pipeline_b_rerun_20260210.txt

databricks bundle run pipeline_c_analytics -t dev --params run_mode=backfill,date_kst_start=2026-02-01,date_kst_end=2026-02-01,run_id=l3_e2e_20260210 \
  | tee .agents/logs/verification/L3_pipeline_c_rerun_20260210.txt
```

참고: Pipeline A의 `silver.dq_status`는 현재 append라서 “동일 run_id 재실행” 시 중복이 생길 수 있습니다. (A의 idempotency는 별도 개선 과제로 분리 권장)

## 6. 검증 쿼리 (Databricks SQL / Notebook)

아래는 예시입니다. `${catalog}`는 실제 카탈로그로 치환합니다.

```sql
-- 상태/예외
SELECT * FROM ${catalog}.gold.pipeline_state;
SELECT severity, count(*) AS cnt
FROM ${catalog}.gold.exception_ledger
GROUP BY severity
ORDER BY severity;

-- 핵심 결과(일자 범위로 필터)
SELECT count(*) FROM ${catalog}.gold.recon_daily_snapshot_flow WHERE date_kst BETWEEN '2026-02-01' AND '2026-02-01';
SELECT * FROM ${catalog}.gold.ledger_supply_balance_daily WHERE date_kst = '2026-02-01';
SELECT count(*) FROM ${catalog}.gold.fact_payment_anonymized WHERE date_kst = '2026-02-01';
```

## 7. 증적(Evidence) 남기기

- 로그 파일은 항상 `.agents/logs/verification/` 아래로 저장합니다.
- 템플릿: `.agents/logs/verification/templates/e2e_evidence_template.md`

### 7.1 최소 증적 (필수)

- 실행 날짜(UTC)
- Workspace host
- 사용한 catalog
- `run_mode/date_kst_start/date_kst_end/run_id`
- A/B/C 실행 로그(`tee` 출력)
- 검증 쿼리 결과(스크린샷 또는 텍스트)

## 8. 정리(Cleanup)

번들에 포함된 Cleanup Job(`e2e_cleanup_mock_data`)는 E2E로 생성된 테이블을 drop 합니다.

```bash
databricks bundle run e2e_cleanup_mock_data -t dev --params drop_schemas=0 \
  | tee .agents/logs/verification/L3_cleanup_20260210.txt
```

Secret Scope를 이번 테스트를 위해 새로 만들었다면(공유가 아니라면) 정리:

```bash
# (주의) 공유 scope라면 삭제하면 안 됩니다.
databricks secrets delete-scope ledger-analytics-dev
```

## 9. 실패 시 빠른 진단 포인트

- Pipeline C 실패: Secret scope/key 권한 또는 값 누락 가능성 높음 (`ledger-analytics-dev/salt_user_key`)
- Pipeline B/C가 “table not found(silver.*)”: Setup job 실행 누락 또는 UC 스키마/테이블 권한 문제
- UC 권한 오류: `USE CATALOG/SCHEMA`, `CREATE`, `MODIFY` 권한 재확인
