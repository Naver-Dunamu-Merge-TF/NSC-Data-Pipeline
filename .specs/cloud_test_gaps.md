# 클라우드 테스트 환경 부재로 인한 미검증/미산출 항목 (Phase 2~4)

작성일: 2026-02-05
업데이트: 2026-02-05 (Databricks Dev L3 실행 반영)

## 배경
현재 Databricks Dev(클라우드) 테스트 환경이 없어, 로컬에서만 검증 가능한 범위를 넘는 항목들은
미검증 상태로 남아 있다. 아래는 Phase 2~4에서 **클라우드 환경이 필요해 수행하지 못한 항목**과
**그 결과 산출되지 않은 테이블/산출물**을 정리한 것이다.

---

## Phase 2 — Bronze 적재 + Mock 데이터 로더

### 클라우드 검증 완료 항목(L3)
- `upload-mock-bronze` Job 실행 성공 (`job_id=973156460706745`, `run_id=1021135531501906`)
- Dev 카탈로그(`2dt_final_team4_databricks_test`)에 Bronze 테이블 생성 확인

### 잔여 미검증 항목
- Bronze 스키마 에볼루션 정책(`mergeSchema=true`)의 **실제 Delta 테이블 적용 확인**

---

## Phase 3 — Silver(Controls) 변환 + 계약 검증

### 클라우드 미검증 항목
- Silver 테이블 **`date_kst` 파티셔닝**의 실제 적용 확인
- Silver 테이블 **MERGE 키 기반 멱등성**(Delta MERGE) 실제 동작 확인
- 변환 로직의 **샘플 산출물**을 Databricks에서 실행 검증

### 미산출/미확인 산출물
- `silver.wallet_snapshot` Delta 테이블 생성/적재
- `silver.ledger_entries` Delta 테이블 생성/적재
- `silver.bad_records_*` 격리 테이블 생성/적재(실제 데이터 기반)

---

## Phase 4 — Pipeline A (Guardrail DQ)

### 클라우드 검증 완료 항목(L3)
- Pipeline A Job 실행 성공 (`job_id=57710310442212`, `run_id=230642718179694`)
- `silver.dq_status` 및 `gold.exception_ledger` 테이블 생성/기록 확인
- DQ 메트릭 계산 결과의 Databricks 실행 검증

### 잔여 미검증 항목
- 없음

---

## 요약
- Phase 2/4는 **Databricks Dev L3 실행 완료**로 핵심 산출물 생성/기록 확인됨.
- Phase 3는 Delta/UC 환경에서의 **파티셔닝/멱등성(MERGE) 검증**이 남아 있음.
- Bronze 스키마 에볼루션(`mergeSchema=true`)의 실제 적용 검증은 별도 확인 필요.

## 다음 단계
- Phase 3 L3 실행(파티셔닝/멱등성 포함)
- Bronze 스키마 에볼루션 검증(스키마 변경 데이터로 재적재 테스트)
