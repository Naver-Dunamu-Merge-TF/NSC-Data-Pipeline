# D-038 전체 구현 계획 (최종 재작성본)

작성일: 2026-02-12
업데이트: 2026-02-12 (PR5 구현 반영)

## 1) 요약

1. 목표는 `A/B/C/Silver` 런타임 경로의 대용량 `collect()` 제거다.
2. 방식은 `legacy + spark` 병행 전환 후 `PR5`에서 legacy 제거로 고정한다.
3. 실행 순서는 `PR0 -> PR1(Silver) -> PR2(B) -> PR3(C) -> PR4(A) -> PR5(정리)`로 고정한다.
4. 배포 안전장치는 `--engine-mode legacy|spark`로 제공하고, 전환 완료 후 `PR5`에서 제거한다.
5. 완료 조건은 기능 동등성, 멱등성, L3 검증, 문서/증적 업데이트까지 포함한다.

## 2) Decision Lock

1. `src/transforms/*`는 `PR1~PR4` 동안 oracle(비교 기준)로 유지하고 `PR5`에서 삭제한다.
2. `engine_mode`는 `PR0~PR4` 필수, `PR5`에서 spark-only로 정리한다.
3. `collect()` 정책은 `unbounded 금지 / bounded 허용`으로 고정한다.
4. 숫자 정밀도는 Decimal 컬럼 exact parity를 원칙으로 한다.
5. parity 테스트는 `PR1~PR4`까지만 운영하고 `PR5`에서 spark 기대값 테스트로 교체한다.

## 3) 공개 인터페이스/타입 변경

1. CLI 인자 추가:
   - `scripts/run_pipeline_a.py`
   - `scripts/run_pipeline_b.py`
   - `scripts/run_pipeline_c.py`
   - `scripts/run_pipeline_silver.py`
   - 추가: `--engine-mode` (`legacy|spark`)
2. `databricks.yml` 변경:
   - job parameter에 `engine_mode` 추가
   - dev/prod 기본값 제어
3. 신규 모듈:
   - `src/io/spark_safety.py`
   - `src/jobs/pipeline_silver_spark.py`
   - `src/jobs/pipeline_b_spark.py`
   - `src/jobs/pipeline_c_spark.py`
   - `src/jobs/pipeline_a_spark.py`
4. `PR5` 삭제 대상(legacy 경로):
   - `src/transforms/dq_guardrail.py`의 list 기반 주 경로
   - `src/transforms/ledger_controls.py`의 list 기반 주 경로
   - `src/transforms/analytics.py`의 list 기반 주 경로
   - parity 전용 테스트 파일들

## 4) collect 정책

### 4.1 금지

- raw/대용량 테이블 전체 `collect()` (`wallet`, `ledger`, `orders`, `payment_orders`, `dq_status` 전체 등)

### 4.2 허용

- `pipeline_state` 1행 조회
- `upstream_readiness` 1행 조회
- `rule_loader` 소형 룰 테이블 조회(행 수 cap 적용)
- A의 window/source 메트릭 결과(작은 메타데이터 집합) 조회

### 4.3 강제

- 허용 경로는 `safe_collect(df, max_rows=...)` 사용
- `tests/unit/test_collect_usage_policy.py`로 정책 회귀 방지

## 5) PR 실행 계획

### PR0 공통 기반

1. `--engine-mode` 파라미터와 런타임 분기 추가
2. `src/io/spark_safety.py` 추가(`safe_collect`, `assert_max_rows`)
3. collect 정책 테스트 추가
4. 문서 초안 업데이트(`D-038 진행중`, 정책 명시)
5. 검증: L0, L1, L2

### PR1 Silver Spark 전환

1. `src/jobs/pipeline_silver_spark.py` 구현
2. Bronze -> Silver 변환을 DataFrame으로 수행하고 list 변환 제거
3. `bad_records` append 후 threshold 평가, fail-fast 순서 보장
4. `scripts/run_pipeline_silver.py`에서 `engine_mode=spark` 분기 연결
5. parity 테스트 추가: `tests/integration/test_pipeline_silver_spark_parity.py`
6. 검증: L0, L1, L2

### PR2 Pipeline B Spark 전환 (핵심)

1. `src/jobs/pipeline_b_spark.py` 구현
2. 날짜 루프 제거:
   - 대상 날짜 범위를 한 번에 처리하는 `groupBy/window` 방식으로 재구성
3. `dq_tags` 로딩 전환:
   - `silver.dq_status` 대상 날짜 필터 + 집계
4. `exception_ledger` key 안정성 유지:
   - `(date_kst, domain, exception_type, run_id, metric, message)` 고정
   - `message` 직렬화 필드 순서 고정
5. `scripts/run_pipeline_b.py` spark 분기 연결
6. parity 테스트 추가: `tests/integration/test_pipeline_b_spark_parity.py`
7. 검증: L0, L1, L2

### PR3 Pipeline C Spark 전환

1. `src/jobs/pipeline_c_spark.py` 구현
2. category 대표 아이템 선택을 Spark window로 구현
3. 익명화 키 생성/필터/조인을 DataFrame으로 유지
4. `scripts/run_pipeline_c.py` spark 분기 연결
5. parity 테스트 추가: `tests/integration/test_pipeline_c_spark_parity.py`
6. 검증: L0, L1, L2

### PR4 Pipeline A Spark 전환

1. `src/jobs/pipeline_a_spark.py` 구현
2. freshness/dup/bad_rate/event_count를 Spark 집계로 계산
3. `zero_window_count`는 메트릭 결과만 bounded collect 후 순차 누적
4. `scripts/run_pipeline_a.py` spark 분기 연결
5. parity 테스트 추가: `tests/integration/test_pipeline_a_spark_parity.py`
6. 검증: L0, L1, L2

### PR5 정리/삭제

1. legacy transforms 경로 삭제
2. parity 테스트 제거 후 spark 기준 기대값 테스트로 교체
3. `engine_mode`를 spark-only로 정리
4. D-038 문서 상태를 `결정됨`으로 업데이트
5. 검증: L0, L1, L2, L3
6. 진행상태(2026-02-12): 코드/테스트/L0~L2 완료, L3는 Databricks 토큰 오류로 실행 실패(증적 로그 기록)

## 6) 수치 정밀도/Parity 기준

1. Decimal 컬럼은 Spark `DecimalType(38,2|6)`로 고정
2. Decimal/Date/String/Int/Timestamp는 exact 비교
3. float/double 신규 도입 금지
4. timestamp 비교는 UTC normalize 후 수행

## 7) 테스트 시나리오 (필수)

1. Happy path:
   - 단일일/다중일 backfill 결과 동등성
2. Edge case:
   - 빈 윈도우, 빈 partition, NULL 키 처리
3. Error case:
   - Silver bad_records 임계치 초과 시 저장 후 실패
   - B/C readiness 실패 시 상태 업데이트 규칙 유지
4. Idempotency:
   - B 동일 `run_id` 재실행 수렴
   - C partition overwrite 격리 유지
   - A/Silver pipeline_state 규칙 유지

## 8) 검증/증적 계획

1. L0: `python -m py_compile <changed_files>`
2. L1: `pytest tests/unit/ -v -x`
3. L2: `pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80`
4. L3: Databricks run-now + 20초 polling + 10분 timeout
5. 로그 저장: `.agents/logs/verification/*_d038_prN_*.txt`

## 9) 롤아웃/롤백

1. PR0~PR4:
   - dev에서 `engine_mode=spark` 단계 전환
   - 장애 시 즉시 `engine_mode=legacy` 롤백
2. PR5:
   - legacy 제거 후 롤백은 git revert + 재배포

## 10) 문서 업데이트 계획

1. `.specs/decision_open_items.md`:
   - D-038 배경/결정/완료기준/허용 collect 정책 명시
2. `.specs/project_specs.md`:
   - Current 상태에 Spark 엔진 경로 반영
3. `.specs/ops/operations_runbook.md`:
   - 전환/롤백 절차(`engine_mode`)와 L3 증적 템플릿 반영

## 11) 완료 기준 (Definition of Done)

1. A/B/C/Silver 런타임에서 unbounded `collect()` 제거 완료
2. 모든 PR에서 L2 통과, PR2/PR4/PR5에서 L3 통과
3. 기능 동등성/멱등성 테스트 통과
4. D-038 문서 상태 `결정됨` 및 증적 링크 반영 완료

## 12) 가정/기본값

1. 테이블 계약/merge key/룰 의미는 변경하지 않는다.
2. D-040 예외 key 정책은 고정한다.
3. D-038 범위는 성능/안정성 개선이며 신규 비즈니스 규칙 추가는 제외한다.
