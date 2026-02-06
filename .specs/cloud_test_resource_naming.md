# Cloud Test Resource Naming And Inventory (Cross-Repo)

Last updated: 2026-02-06

## 1. Purpose

This document defines a single naming policy and a current inventory for test resources
used by both:

1. `tx-lookup-service` repository (FR-ADM-02 serving path)
2. Databricks repository (controls/analytics path)

References:

- `.ref/SRS - Software Requirements Specification.md`
- `.ref/project_specs.md`
- `.specs/cloud_migration_rebuild_plan.md`

## 2. Scope

Azure scope used for this profile:

- Subscription: `27db5ec6-d206-4028-b5e1-6004dca5eeef`
- Primary resource group: `2dt-final-team4`
- Region: `koreacentral`
- Network policy: public endpoint allowed (test-only)

## 3. Naming Policy

### 3.1 Custom resources (directly created by team)

1. Hyphen-allowed resources:
- Pattern: `team4-txlookup-<resource>-<owner>-<env>`

2. Hyphen-disallowed resources (for example ACR, Storage):
- Pattern: `team4txlookup<resource><owner><env>`

3. Fixed tokens for current profile:
- `owner=2dt026`
- `env=test`

### 3.2 Databricks managed resources

Databricks managed resource group names and internal resource names are platform-generated.
These names are inventory-managed, not naming-policy-managed.

## 4. Current Inventory (Observed)

### 4.1 Team4 primary resource group

Resource group: `2dt-final-team4`

| Name | Type | Notes |
| --- | --- | --- |
| `team4-trade-data` | `Microsoft.EventHub/namespaces` | Existing Event Hubs namespace (legacy/shared naming) |
| `2dtfinalteam4storagetest` | `Microsoft.Storage/storageAccounts` | Existing storage account |
| `2dt-final-team4-databricks-test` | `Microsoft.Databricks/workspaces` | Databricks workspace used by Databricks repo |

### 4.2 Databricks managed resource group (team4 workspace)

Resource group: `databricks-rg-2dt-final-team4-databricks-test-i75zgjbs3ihjc`

| Name | Type |
| --- | --- |
| `unity-catalog-access-connector` | `Microsoft.Databricks/accessConnectors` |
| `dbstoragesgx3kg7f5lqrq` | `Microsoft.Storage/storageAccounts` |
| `dbmanagedidentity` | `Microsoft.ManagedIdentity/userAssignedIdentities` |
| `nat-gw-public-ip` | `Microsoft.Network/publicIPAddresses` |
| `workers-sg` | `Microsoft.Network/networkSecurityGroups` |
| `nat-gateway` | `Microsoft.Network/natGateways` |
| `workers-vnet` | `Microsoft.Network/virtualNetworks` |

## 5. Planned Phase 8 Names (tx-lookup test stack)

1. Event Hubs namespace:
- `team4-txlookup-2dt026-test`

2. Event hubs:
- `ledger.entry.upserted`
- `payment.order.upserted`

3. Consumer group:
- `bo-sync-test-2dt026-v1`

4. PostgreSQL Flexible Server:
- `team4-txlookup-pg-2dt026-test`

5. Azure Container Registry:
- `team4txlookup2dt026test`

6. Container Apps Environment:
- `team4-txlookup-caenv-2dt026-test`

7. Container App (API):
- `team4-txlookup-api-2dt026-test`

8. Container App (Consumer):
- `team4-txlookup-consumer-2dt026-test`

9. Log Analytics Workspace:
- `team4-txlookup-law-2dt026-test`

10. Application Insights:
- `team4-txlookup-ai-2dt026-test`

## 6. Shared Tag Policy (All Test Resources)

- `env=test`
- `owner=2dt026`
- `project=txlookup`
- `ttl=2026-02-28`

## 7. Guardrails

1. Keep Databricks managed resources untouched by manual rename/delete.
2. Use isolated Event Hubs namespace for tx-lookup test runs (no shared namespace dependency).
3. Treat this inventory as disposable; secure production naming may differ.
