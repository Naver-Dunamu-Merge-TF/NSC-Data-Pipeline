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

### (선택) 로컬 PySpark 통합 테스트

Databricks 런타임에서는 PySpark가 기본 제공되지만, 로컬에서 `tests/integration/`의 PySpark 스모크 테스트를
실행하려면 Java(JVM)와 PySpark를 설치해야 합니다.

Ubuntu/WSL 예시:

```
sudo apt-get update
sudo apt-get install -y openjdk-17-jre-headless
python -m pip install -r requirements-dev.txt -r requirements-spark.txt
python -m pytest tests/integration/ -v
```

### 로컬 Mock 데이터 확인

- 로컬 Bronze mock 데이터는 `mock_data/bronze/*`에 저장됩니다.
- 로컬에서 Bronze 로딩/메타 부여는 `src/io/bronze_io.py`를 사용합니다.

---

## 향후 확장

현재 미구현 기능:
- **FR-ANA-02 (실시간 시세 모니터링)**: 실제로 들어갈지 팀원들과 협의 필요

새로운 OLAP 분석 요구사항이 생기면 Gold 레이어에 테이블을 추가하여 확장할 수 있습니다.
Bronze/Silver 레이어는 범용적으로 설계되어 있어 추가 파이프라인 개발이 용이합니다.
