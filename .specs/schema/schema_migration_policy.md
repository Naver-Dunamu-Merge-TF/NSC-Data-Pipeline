# Schema Migration Policy (Bronze/Silver/Gold)

Last updated: 2026-02-06

## 1. Principles

1. Bronze:
- append-only
- `mergeSchema=true` 허용 (컬럼 추가 중심)

2. Silver/Gold:
- 계약 기반 명시적 변경만 허용
- 임의 컬럼 추가/타입 변경 금지
- 변경 전후 멱등성/백필 검증 필수

## 2. Change Types

1. Minor (호환):
- nullable 컬럼 추가
- 허용값 집합 확장(룰 테이블)

2. Major (비호환):
- 키 변경
- 타입 축소/의미 변경
- 필수 컬럼 추가

## 3. Required Steps

1. 계약 문서 갱신:
- `.specs/data_contract.md`
- 필요한 경우 `.specs/project_specs.md`

2. 코드 변경:
- `src/common/contracts.py`
- `src/common/table_metadata.py`
- 변환/IO/잡 로직

3. 테스트:
- Unit + Integration (최소 L2)
- 대상이 대사/룰이면 L3 계획 수립

4. 운영 전 검토:
- backfill 영향 범위
- partition overwrite/MERGE 충돌 여부
- 롤백 절차 확인

## 4. Migration Execution Template

1. 대상 테이블:
2. 변경 유형(Minor/Major):
3. 대상 기간(`date_kst_start~end`):
4. 실행 순서:
- schema apply
- backfill
- incremental 재개
5. 검증 쿼리:
6. 롤백 기준:

## 5. Rollback Rule

1. 실패 시 Bronze 기준 재처리 가능해야 한다.
2. `gold.pipeline_state`의 `last_processed_end`는 마지막 성공 지점으로 유지한다.
3. 롤백 후 동일 윈도우 재실행 결과가 수렴해야 한다.
