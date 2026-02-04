Data-pipeline LLM coding agent instructions
============================================

This file contains instructions for LLM coding agents working with the
Controls-first Ledger Pipelines codebase.


Project overview
----------------

Controls-first Ledger Pipelines on Azure Databricks is a data quality and
reconciliation system. The project builds **controls** (not analytics) to
detect data issues and verify ledger integrity.

**Pipelines:**
 -  **A (Guardrail)**: Data freshness/completeness (10-min micro-batch)
 -  **B (Ledger & Admin Controls)**: Snapshot-Flow reconciliation (`delta = net_flow`)
 -  **C (Analytics)**: Anonymized payment data loading

**Key principle:** Pipeline A detects data quality issues first, enabling
B/C results to be interpreted correctly (gating policy).

**Current phase:** Mock data-based development. Source DB under development.


Development environment
-----------------------

 -  Development: **Local IDE + remote Databricks execution** (Option B)
 -  Language: Python (PySpark)
 -  Local testing: pytest with mock DataFrames
 -  Remote testing: Databricks Dev cluster E2E
 -  Orchestration: Databricks Workflows (Jobs)
 -  Storage: Delta Lake on Azure


Repository structure
--------------------

```
├── src/
│   ├── transforms/         # Pure transform logic (DB-independent)
│   ├── io/                 # IO layer (readers/writers)
│   └── jobs/               # Databricks job definitions
├── tests/
│   ├── unit/               # Local pytest
│   └── integration/        # Remote smoke tests
├── configs/                # Environment configs (dev/prod)
├── mock_data/              # Mock datasets
└── .specs/                 # Specifications
```


Core domain concepts
--------------------

### Data layers

 -  **Bronze**: Flexible ingestion (raw, audit-ready)
 -  **Silver**: Contract enforcement (validation, fail-fast)
 -  **Gold**: Schema stability (operational consumption)

### Data contracts

See `.specs/data_contract.md` for full schemas:

**Ledger/Admin (Controls):**
 -  `user_wallets`: User wallet balance snapshots
 -  `transaction_ledger`: Ledger transaction events (flows)
 -  `payment_orders`: Payment order records

**Commerce (Analytics):**
 -  `orders`: Commerce orders
 -  `order_items`: Order line items
 -  `products`: Product catalog

### Source mapping

Source DB schema differs from contract schema. Bronze->Silver transform
applies mapping rules (column rename, derivation, type casting).
See `data_contract.md` section 5.


Code patterns and principles
----------------------------

### 1. Transform / IO / Jobs separation

 -  **Transforms**: Pure functions, no Spark session, testable locally
 -  **IO**: Readers/writers, Delta/DB connections
 -  **Jobs**: Wires transforms + IO

### 2. Idempotency (required)

 -  Use `MERGE` with defined keys for upserts
 -  Use `overwrite partition` for daily snapshots
 -  Same input -> same output
 -  Silver/Gold: partitioned by `date_kst` (Hive style)

### 3. Contract-based validation

Silver layer enforces data contracts. Bad records go to quarantine tables
(`silver.bad_records_*`). Fail-fast if bad rate exceeds threshold.

### 4. Rule versioning

All thresholds in `gold.dim_rule_scd2`. Never hardcode.
All outputs include `rule_id`. Changes = version bump.

### 5. Run tracking

Every execution: unique `run_id`, recorded in all outputs,
update `gold.pipeline_state` on success.


Common job parameters
---------------------

All pipelines accept these standard parameters:

 -  `run_mode`: `incremental` | `backfill`
 -  `start_ts`, `end_ts`: Timestamp window (UTC)
 -  `date_kst_start`, `date_kst_end`: Day-level backfill range
 -  `run_id`: Unique execution ID (recorded in all outputs)


Pipelines overview
------------------

### Pipeline A: Guardrail

10-minute micro-batch monitoring freshness, completeness, duplicates.
Output: `silver.dq_status`. Exceptions: `SOURCE_STALE`, `EVENT_DROP_SUSPECTED`.

### Pipeline B: Ledger & Admin Controls

Verifies `delta_balance = net_flow` per window. Tags results with A status.
If A shows issues, B alerts suppressed. Output: `gold.recon_daily_snapshot_flow`.
Also checks supply vs wallet balance: `gold.ledger_supply_balance_daily`.

### Pipeline C: Analytics

Daily anonymized data loading for analysis. Pseudonymization via user_key.
Output: `gold.fact_payment_anonymized`. PII excluded.

See `.specs/project_specs.md` sections 5-6 for pipeline specifications.


Key tables
----------

**Silver (Contract enforcement):**
 -  `silver.wallet_snapshot`: Point-in-time wallet balance snapshots
 -  `silver.ledger_entries`: Standardized ledger entries with amount_signed
 -  `silver.dq_status`: Data quality metrics
 -  `silver.order_events`: Standardized order/payment events
 -  `silver.order_items`: Order line items (analytics)
 -  `silver.products`: Product dimension (analytics)

**Gold (Controls output):**
 -  `gold.recon_daily_snapshot_flow`: Reconciliation results (delta = net_flow)
 -  `gold.ledger_supply_balance_daily`: Supply vs wallet balance check
 -  `gold.exception_ledger`: Unified exception log (domain: dq/recon/analytics)
 -  `gold.pipeline_state`: Execution state tracking
 -  `gold.dim_rule_scd2`: Rule/threshold versioning

**Gold (Operational metrics):**
 -  `gold.ops_payment_failure_daily`: Payment failure rate by merchant
 -  `gold.ops_ledger_pairing_quality_daily`: Ledger entry pairing quality

**Gold (Analytics):**
 -  `gold.fact_payment_anonymized`: Anonymized payment analytics
 -  `gold.admin_tx_search`: (Optional) tx_id batch index for audit


Decision defaults
-----------------

 -  **Time**: Storage/calc in UTC, day boundary in KST
 -  **Window**: `[start, end)` - start inclusive, end exclusive
 -  **Amount sign**: Derived from entry_type mapping (see `data_contract.md` section 5.2.1)

Full defaults and thresholds: `.specs/project_specs.md` section 7 and Appendix.


Testing strategy
----------------

**Test levels:**
 -  **Unit**: pytest + mock DataFrames (transforms only)
 -  **Integration**: pytest + local PySpark (transforms + IO)
 -  **E2E**: Databricks Dev cluster (Delta, UC, MERGE)

**Test case types:**
 -  **Happy path**: Normal input → expected output
 -  **Edge case**: Boundary values, empty data
 -  **Error case**: Bad records, schema mismatch → quarantine
 -  **Idempotency**: Re-run → same result

**Quality gates:**
 -  Unit coverage: ≥ 80%
 -  PR gate: All unit tests pass
 -  Merge gate: E2E smoke tests pass

See `.specs/project_specs.md` section 10-11 for test and CI/CD details.


Verification policy
-------------------

### Verification contract

 -  Verification is mandatory. Do not claim completion without running an
    appropriate verification level.
 -  Store evidence under `.agents/logs/verification/`.
 -  Do not encode verification level in commit messages.

### Verification ladder

| Level | When | Duration | Command | Pass Criteria |
|-------|------|----------|---------|---------------|
| L0 | Per edit | < 30s | `python -m py_compile` | No syntax errors |
| L1 | Pre-commit | < 2min | `pytest tests/unit/ -x` | All unit tests pass |
| L2 | Pre-PR | < 10min | `pytest --cov-fail-under=80` | 80%+ coverage |
| L3 | Pre-merge | < 30min | Databricks Dev E2E | Idempotency verified |

### Escalation triggers

 -  If in doubt, move up one level.
 -  `src/transforms/` changes: Minimum L1
 -  `src/io/`, `src/jobs/` changes: Minimum L2
 -  Reconciliation logic, rule table changes: L3 required
 -  `data_contract.md` changes: L3 + manual review

### Exceptions

 -  Documentation-only changes: May skip L0-L2
 -  Emergency hotfix: May skip L1, L2 with post-hoc L3 within 24h

### Toolbox

 -  L0: `python -m py_compile ${FILE}`
 -  L1: `pytest tests/unit/ -v -x`
 -  L2: `pytest tests/unit/ tests/integration/ -v --cov=src --cov-fail-under=80`
 -  L3: `databricks jobs run-now --job-id ${JOB_ID}`


Security
--------

 -  Secrets via Key Vault / Databricks Secret Scope
 -  All executions tracked via `run_id`
 -  Never commit credentials


Retry and alerting
------------------

 -  **Retry**: Max 2 retries, 5-min interval (transient errors only)
 -  **Alert trigger**: `gold.exception_ledger` with `severity = CRITICAL`
 -  **Alert suppression**: Pipeline A `SOURCE_STALE` suppresses B/C alerts (gating)


Documentation lookup
--------------------

When looking up official documentation for external libraries or frameworks, always use the Context7 MCP server.


Key references
--------------

**For requirements, thresholds, or design decisions, consult `.specs/` first (SSOT).**

| Document | Content |
|----------|---------|
| `.specs/project_specs.md` | Full development plan, Decision Lock, thresholds |
| `.specs/data_contract.md` | Data contracts, schemas, mapping rules |
