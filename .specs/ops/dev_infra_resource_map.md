# Dev Infra Resource Map (Data-pipeline)

Last updated: 2026-02-23 (UTC)  
Source of truth for observations: `.agents/logs/verification/20260223_infra_resource_selection.md`

## 1) 목적

이 문서는 Data-pipeline 팀이 dev 환경에서 반드시 알아야 하는 Azure/Databricks 리소스 종류, 실제 리소스 이름, 그리고 코드/설정과의 연관 정보를 한 곳에 정리한다.

우선순위 기준:
- `Tier 1`: 로컬/파이프라인 운영에서 즉시 필요한 핵심 리소스
- `Tier 2`: 파이프라인 입력/운영 검증을 위해 자주 필요한 연관 리소스
- `Tier 3`: 주로 인프라팀 관리 범위(참조용)

## 2) Tier 1: 핵심 리소스 (필수)

### 2.0 구독/환경 식별자

| 항목 | 값 |
|---|---|
| Subscription | `27db5ec6-d206-4028-b5e1-6004dca5eeef` |
| Environment | `dev` |
| Primary resource group | `2dt-final-team4` |

### 2.1 Databricks

| 항목 | 값 |
|---|---|
| Resource type | `Microsoft.Databricks/workspaces` |
| Resource group | `2dt-final-team4` |
| Workspace name | `nsc-dbw-dev` |
| Workspace host | `https://adb-7405610275478542.2.azuredatabricks.net` |
| Workspace ID | `7405610275478542` |
| UC catalog (active) | `nsc_dbw_dev_7405610275478542` |

코드/설정 연관:
- `configs/dev.yaml`의 `databricks.workspace_host`, `databricks.workspace_id`, `databricks.catalog`
- `scripts/run_pipeline_a.py`, `scripts/run_pipeline_b.py`, `scripts/run_pipeline_silver.py`, `scripts/run_pipeline_c.py`의 `--catalog` 기본값

운영 메모:
- `databricks bundle deploy -t dev` 기준 `data-pipeline-*-dev` 잡들이 생성되어 있음.
- Secret Scope `ledger-analytics-dev`가 생성되어 있고 key 조회 검증까지 완료됨.

### 2.1.1 Databricks-ADLS 연결 오브젝트

| 항목 | 현재 관측값 | 상태 |
|---|---|---|
| Azure access connector (기본) | `nsc-dbw-managed-rg-dev/unity-catalog-access-connector` | 존재 |
| UC storage credential (기본) | `nsc_dbw_dev_7405610275478542` | 존재 (기본 connector 참조) |
| UC external location (팀 데이터) | `team4_adls_test` | URL/credential 교정 완료 (`nscstdevw4mlu8` + `nsc_dbw_dev_7405610275478542`) |
| UC storage credential (팀 데이터, legacy) | `team4_adls_test_cred` | 존재하나 참조 connector가 Azure에서 미존재 (미사용 정리 대상) |

연관 정보:
- `team4_adls_test` URL: `abfss://2dt-final-team4-adls-test@nscstdevw4mlu8.dfs.core.windows.net/`
- 컨테이너 `2dt-final-team4-adls-test`는 `nscstdevw4mlu8`에 생성/존재 확인됨.
- 초기 검증 실패(403) 이후 access connector RBAC 부여 후 재검증(update without `--skip-validation`) 성공.
- `team4_adls_test_cred`가 참조하는 connector (`team4-txlookup-ac-2dt026-test`)는 Azure 리소스 미존재.

### 2.2 ADLS (Storage Account)

| 항목 | 값 |
|---|---|
| Resource type | `Microsoft.Storage/storageAccounts` |
| Resource group | `2dt-final-team4` |
| Storage account name | `nscstdevw4mlu8` |
| DFS endpoint | `https://nscstdevw4mlu8.dfs.core.windows.net/` |
| HNS | `true` |
| publicNetworkAccess | `Disabled` |

코드/설정 연관:
- `configs/dev.yaml`의 `storage.external_location`, `storage.base_path`
- Databricks UC external location / storage credential

운영 메모:
- 네트워크/권한 정책으로 로컬에서 컨테이너 목록 조회가 차단될 수 있음. Databricks 내부 경로로 검증 권장.

### 2.3 Key Vault

| 항목 | 값 |
|---|---|
| Resource type | `Microsoft.KeyVault/vaults` |
| Resource group | `2dt-final-team4` |
| Vault name | `nsc-kv-dev` |
| Vault URI | `https://nsc-kv-dev.vault.azure.net/` |
| RBAC auth | `Enabled` |
| publicNetworkAccess | `Disabled` |

코드/설정 연관:
- `configs/dev.yaml`의 `analytics.secret_scope`
- `src/io/secret_loader.py`에서 Databricks secret scope/key를 통해 salt 조회
- `scripts/run_pipeline_c.py`의 `--secret-scope`, `--secret-key`

운영 메모:
- 현재 사용자 권한으로는 Key Vault secret metadata 조회가 `ForbiddenByRbac`일 수 있음.

## 3) Tier 2: 연관 리소스 (파이프라인 입력/운영)

### 3.1 Event Hubs

| 항목 | 값 |
|---|---|
| Namespace | `nsc-evh-dev` |
| Endpoint | `https://nsc-evh-dev.servicebus.windows.net:443/` |
| Event hubs (observed) | `cdc-events`, `order-events`, `server.domain.events`, `wallet-create` |
| publicNetworkAccess | `Enabled` |

### 3.2 Azure SQL

| 항목 | 값 |
|---|---|
| SQL server | `nsc-sql-dev` |
| FQDN | `nsc-sql-dev.database.windows.net` |
| DB | `nsc-account-commerce-db` |
| AAD-only auth | `true` |
| publicNetworkAccess | `Disabled` |

### 3.3 PostgreSQL Flexible Server

| 항목 | 값 |
|---|---|
| Server | `nsc-pg-dev` |
| FQDN | `nsc-pg-dev.postgres.database.azure.com` |
| publicNetworkAccess | `Enabled` |
| Private endpoint | `nsc-pe-pg` 연결됨 |

## 4) Tier 3: 인프라 레이어 (참조)

Data-pipeline 개발자가 이름만 알아두면 되는 리소스:
- VNet: `nsc-vnet-dev`
- Private Endpoints: `nsc-pe-kv`, `nsc-pe-adls`, `nsc-pe-evh`, `nsc-pe-sqldb`, `nsc-pe-pg`, `nsc-pe-acr`
- Private DNS Zones: `privatelink.vaultcore.azure.net`, `privatelink.dfs.core.windows.net`, `privatelink.servicebus.windows.net`, `privatelink.database.windows.net`, `privatelink.postgres.database.azure.com`, `privatelink.azurecr.io`
- 보안/네트워크 제어: NSG/UDR/Firewall(`nsc-fw-dev`, `nsc-fwp-dev`), WAF(`nsc-waf-dev`)

## 5) Config 매핑 체크리스트 (현재 상태)

`configs/dev.yaml` 기준으로, 실제 리소스와 매칭 여부:

| Config key | 현재 값 | 실제 상태 | 판단 |
|---|---|---|---|
| `databricks.workspace_host` | `https://adb-7405610275478542.2.azuredatabricks.net` | 실제 host와 일치 | 일치 |
| `databricks.workspace_id` | `7405610275478542` | 실제 workspace_id와 일치 | 일치 |
| `databricks.catalog` | `nsc_dbw_dev_7405610275478542` | catalog 존재 확인 | 일치 |
| `databricks.cluster_policy_id` | `0004CF01E53A5F6F` | `Job Compute` policy 존재 | 일치 |
| `storage.external_location` | `team4_adls_test` | URL/credential 연결 교정 완료 | 일치 |
| `storage.base_path` | `abfss://2dt-final-team4-adls-test@nscstdevw4mlu8.dfs.core.windows.net` | 실제 external location URL과 일치 | 일치 |
| `analytics.secret_scope` | `ledger-analytics-dev` | workspace scope 존재 확인 | 일치 |
| `jobs.pipeline_a_job_id` | `502540498370580` | 현재 `data-pipeline-a-dev` job_id와 일치 | 일치 |

## 6) 오늘 기준 팀 실무 가이드

- "무엇을 알아야 하나?"에 대한 최소 셋:
  - Databricks: workspace host/id + catalog + (secret scope, policy, jobs) 유무
  - ADLS: 실제 storage account 이름/endpoint + external location 연결 상태
  - Key Vault: vault URI + Databricks와의 secret scope 연동 여부
- 여기에 입력 소스 점검이 필요하면 Event Hubs/SQL/Postgres를 추가 확인한다.

## 7) 빠른 점검 명령어

```bash
az databricks workspace show -g 2dt-final-team4 -n nsc-dbw-dev --query "{workspace: name, host: workspaceUrl, workspaceId: workspaceId}" -o table
az storage account show -g 2dt-final-team4 -n nscstdevw4mlu8 --query "{account:name,dfs:primaryEndpoints.dfs,publicNetwork:publicNetworkAccess}" -o table
az keyvault show -g 2dt-final-team4 -n nsc-kv-dev --query "{vault:name,uri:properties.vaultUri,rbac:properties.enableRbacAuthorization}" -o table
DATABRICKS_HOST=https://$(az databricks workspace show -g 2dt-final-team4 -n nsc-dbw-dev --query workspaceUrl -o tsv) DATABRICKS_AUTH_TYPE=azure-cli databricks catalogs list --output text
DATABRICKS_HOST=https://$(az databricks workspace show -g 2dt-final-team4 -n nsc-dbw-dev --query workspaceUrl -o tsv) DATABRICKS_AUTH_TYPE=azure-cli databricks external-locations list --output text
DATABRICKS_HOST=https://$(az databricks workspace show -g 2dt-final-team4 -n nsc-dbw-dev --query workspaceUrl -o tsv) DATABRICKS_AUTH_TYPE=azure-cli databricks secrets list-scopes --output json
```
