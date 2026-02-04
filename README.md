# Controls-first Ledger Pipelines

원장 데이터 무결성 검증과 일일 정합성 점검을 위한 Azure Databricks 파이프라인입니다.

---

## 목적

- **FR-ADM-01**: 원장 총액을 조회합니다 (발행량 ↔ 지갑 잔액 합계)
- **FR-ADM-03**: 일일 정합성을 점검합니다 (잔액 변동 = 순 흐름)
- **FR-ANA-01**: 익명화된 결제 패턴을 수집합니다

---

## 구성 요소

| 파이프라인 | 역할 |
|-----------|------|
| **A (Guardrail)** | 데이터 품질을 모니터링합니다 (10분 주기) |
| **B (Ledger Controls)** | 일일 정합성을 점검합니다 (KST 00:00) |
| **C (Analytics)** | 익명화 데이터를 적재합니다 (일배치) |

---

## 아키텍처

```
Source DB → [Bronze] → [Silver] → [Gold] → Admin Dashboard
               ↓           ↓          ↓
           원본 보존    계약 검증    컨트롤 결과
```

---

## 주요 테이블

**Silver (계약 검증)**
- `silver.wallet_snapshot` — 시점별 지갑 잔액 스냅샷입니다
- `silver.ledger_entries` — 표준화된 원장 엔트리입니다
- `silver.dq_status` — 데이터 품질 상태입니다

**Gold (컨트롤 결과)**
- `gold.recon_daily_snapshot_flow` — 일일 정합성 점검 결과입니다
- `gold.ledger_supply_balance_daily` — 발행량 vs 잔액 합계입니다
- `gold.exception_ledger` — 통합 예외 로그입니다

---

## 기술 스택

- Azure Databricks, Delta Lake
- Python (PySpark)
- Unity Catalog

---

## 개발/테스트

테스트는 가상환경에서 실행합니다.

```
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
python -m pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80
```

`pytest-cov`는 커버리지 옵션(`--cov`, `--cov-fail-under`)에 필요합니다.

---

## 향후 확장

현재 미구현 기능:
- **FR-ANA-02 (실시간 시세 모니터링)**: 실시간 스트리밍 인프라 구축 후 추가 예정

새로운 OLAP 분석 요구사항이 생기면 Gold 레이어에 테이블을 추가하여 확장할 수 있습니다.
Bronze/Silver 레이어는 범용적으로 설계되어 있어 추가 파이프라인 개발이 용이합니다.
