# Monitoring Resource Naming Baseline (MON-002)

Last updated: 2026-02-24

## 1) Scope

본 문서는 Azure Monitoring v1 범위에서 dev/prod 공통으로 재사용할 명명 규칙과
리소스 매핑 baseline을 고정한다.

- Upstream evidence: `.agents/logs/verification/20260224_mon001_signal_wiring.md`
- Reference map: `.specs/ops/dev_infra_resource_map.md`
- SSOT parent: `.specs/ops/azure_monitoring_integration_plan.md` (M1)

## 2) Naming Grammar (v1)

| Resource | Pattern | Example (dev) |
|---|---|---|
| Alert Rule | `{env}-dp-{pipeline}-{signal}-alert` | `dev-dp-pipeline-a-job-failure-alert` |
| Action Group | `{env}-dp-{owner}-ag` | `dev-dp-platform-ag` |
| Workbook | `{env}-dp-monitoring-v1` | `dev-dp-monitoring-v1` |
| Evidence File | `YYYYMMDD_<taskid>_<artifact>.{md|log|json}` | `20260224_mon001_signal_wiring.md` |

규칙:
1. `env`는 `dev|prod`의 소문자 고정값을 사용한다.
2. pipeline token은 roadmap task 문맥과 정합성을 유지한다(`pipeline-a`, `pipeline-b`, `pipeline-c`, `pipeline-silver`).
3. signal token은 운영 triage에서 바로 구분 가능한 단어를 사용한다(`job-failure`, `retry-exhausted`, `success-delay`, `cluster-timeout`).

## 3) Resource Mapping Baseline

| Env | Databricks Workspace | Workspace Resource ID | LAW Resource ID | LAW GUID | Diagnostic Setting |
|---|---|---|---|---|---|
| dev | `nsc-dbw-dev` | `/subscriptions/27db5ec6-d206-4028-b5e1-6004dca5eeef/resourceGroups/2dt-final-team4/providers/Microsoft.Databricks/workspaces/nsc-dbw-dev` | `/subscriptions/27db5ec6-d206-4028-b5e1-6004dca5eeef/resourceGroups/2dt-final-team4/providers/Microsoft.OperationalInsights/workspaces/nsc-law-dev` | `748abb68-8c24-4075-9354-f21c34699dc2` | `diag-dbw-core-dev` |
| prod | `<prod-dbw-workspace>` | `<prod-dbw-resource-id>` | `<prod-law-resource-id>` | `<prod-law-guid>` | `diag-dbw-core-prod` |

Pipeline job name baseline:
- dev:
  - `data-pipeline-a-dev`
  - `data-pipeline-b-dev`
  - `data-pipeline-c-dev`
- prod:
  - `data-pipeline-a-prod`
  - `data-pipeline-b-prod`
  - `data-pipeline-c-prod`

## 4) Planned Name Reservation (v1)

| Env | Alert Names (Core 4) | Workbook |
|---|---|---|
| dev | `dev-dp-pipeline-a-job-failure-alert`, `dev-dp-pipeline-a-success-delay-alert`, `dev-dp-pipeline-b-retry-exhausted-alert`, `dev-dp-pipeline-c-cluster-timeout-alert` | `dev-dp-monitoring-v1` |
| prod | `prod-dp-pipeline-a-job-failure-alert`, `prod-dp-pipeline-a-success-delay-alert`, `prod-dp-pipeline-b-retry-exhausted-alert`, `prod-dp-pipeline-c-cluster-timeout-alert` | `prod-dp-monitoring-v1` |

## 5) Governance Notes

- prod 값이 미확정인 필드는 placeholder를 유지하되, 값 확정 시 본 문서를 먼저 갱신한다.
- MON-003~MON-008 구현 시 이 문서의 naming grammar를 primary rule로 사용한다.
