Data-pipeline LLM coding agent instructions
============================================

This file contains instructions for LLM coding agents working with the
Controls-first Ledger Pipelines codebase.


Project overview
----------------

Controls-first Ledger Pipelines on Azure Databricks for data quality and
reconciliation (controls-first, not analytics).

Pipelines:
- A (Guardrail): freshness/completeness/duplicates, 10-min micro-batch
- B (Ledger/Admin): daily recon (`delta = net_flow`) + supply checks
- C (Analytics): anonymized payment marts

Key principle: Pipeline A gates B/C (stale/drop suppresses alerts).
Current phase: mock data-based development.


Development environment
-----------------------

Local IDE + remote Databricks execution (Option B), Python (PySpark),
pytest locally, Databricks Dev E2E, Delta Lake on Azure.


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

Data layers: Bronze (raw), Silver (contract + validation), Gold (stable).
Schemas, mappings, and table definitions live in `.specs/data_contract.md`.


Code patterns and principles
----------------------------

- Transform/IO/Jobs separation (pure transforms; IO handles Delta/DB; jobs wire both)
- Idempotency required: MERGE keys, overwrite partitions; Silver/Gold partition by `date_kst`
- Contract validation + quarantine (`silver.bad_records_*`), fail-fast on bad rate
- Rule versioning via `gold.dim_rule_scd2` (no hardcoded thresholds), outputs include `rule_id`
- Run tracking: `run_id` propagated, update `gold.pipeline_state`


Common job parameters
---------------------

All pipelines accept these standard parameters:

 -  `run_mode`: `incremental` | `backfill`
 -  `start_ts`, `end_ts`: Timestamp window (UTC)
 -  `date_kst_start`, `date_kst_end`: Day-level backfill range
 -  `run_id`: Unique execution ID (recorded in all outputs)


Pipelines overview
------------------

Pipeline A: Guardrail DQ → `silver.dq_status` + exceptions  
Pipeline B: Recon/supply checks → `gold.recon_daily_snapshot_flow`, `gold.ledger_supply_balance_daily`  
Pipeline C: Anonymized analytics → `gold.fact_payment_anonymized`  
Details: `.specs/project_specs.md` sections 5-6.


Key tables and decision defaults live in `.specs/data_contract.md` and
`.specs/project_specs.md` (section 7).


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

### L3 execution standard

 -  Poll Databricks run status every 20 seconds.
 -  Use a 10-minute timeout for L3 verification runs.

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
| `.specs/decision_open_items.md` | Open decisions and implementation assumptions |

Decision hygiene
----------------

- If any part of the implementation is unclear or handled as an assumption,
  add it to `.specs/decision_open_items.md` immediately and update its status
  once a decision is made.
