#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

DATE_TAG="$(date -u +%Y%m%d)"
TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="${LOG_DIR}/${DATE_TAG}_sec003_sec004_binding_window.log"
ESCALATION_FILE="${LOG_DIR}/${DATE_TAG}_sec003_sec004_escalation.md"
ACL_BACKUP_FILE="${LOG_DIR}/${DATE_TAG}_sec_scope_acl_backup_${RANDOM}.json"
SUMMARY_FILE="${LOG_DIR}/${DATE_TAG}_sec003_sec004_binding_window.md"

CURRENT_STAGE="init"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${LOG_FILE}"
}

record_escalation() {
  local stage="$1"
  local detail="$2"
  cat > "${ESCALATION_FILE}" <<EOF
# SEC-003/SEC-004 Binding Window Escalation

- date_utc: ${TS_UTC}
- stage: ${stage}
- detail: ${detail}
- action: stop execution and escalate to Infra + Platform
EOF
  log "escalation recorded: ${ESCALATION_FILE}"
}

on_error() {
  local lineno="$1"
  local cmd="$2"
  record_escalation "${CURRENT_STAGE}" "line=${lineno}, command=${cmd}"
}

trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

apply_grant() {
  local securable_type="$1"
  local full_name="$2"
  local principal="$3"
  shift 3
  local payload_file
  payload_file="$(mktemp)"

  jq -n \
    --arg principal "${principal}" \
    --argjson privileges "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
    '{changes:[{principal:$principal, add:$privileges}]}' > "${payload_file}"

  databricks grants update "${securable_type}" "${full_name}" --json @"${payload_file}" >/dev/null
  rm -f "${payload_file}"
}

create_kv_backed_scope() {
  local scope_name="$1"
  local payload_file
  payload_file="$(mktemp)"

  jq -n \
    --arg scope "${scope_name}" \
    --arg rid "${KV_RESOURCE_ID}" \
    --arg tid "${KV_TENANT_ID}" \
    --arg dns "${KV_DNS_NAME}" \
    '{
      scope: $scope,
      initial_manage_principal: "users",
      scope_backend_type: "AZURE_KEYVAULT",
      backend_azure_keyvault: {
        resource_id: $rid,
        tenant_id: $tid,
        dns_name: $dns
      }
    }' > "${payload_file}"

  databricks secrets create-scope "${scope_name}" --json @"${payload_file}" >/dev/null
  rm -f "${payload_file}"
}

read_scope_backend() {
  local scope_name="$1"
  databricks secrets list-scopes --output json | jq -r \
    --arg scope "${scope_name}" \
    '(if type == "array" then . else .scopes end) | map(select(.name == $scope))[0].backend_type // empty'
}

require_cmd databricks
require_cmd az
require_cmd jq

TARGET="${TARGET:-dev}"
RUN_ID="${RUN_ID:-sec003_sec004_$(date -u +%Y%m%dT%H%M%SZ)}"
CATALOG_NAME="${CATALOG_NAME:-nsc_dbw_dev_7405610275478542}"
EXTERNAL_LOCATION_NAME="${EXTERNAL_LOCATION_NAME:-team4_adls_test}"
SECRET_SCOPE="${SECRET_SCOPE:-ledger-analytics-dev}"
SECRET_KEY="${SECRET_KEY:-salt_user_key}"
UC_GROUP_PRINCIPAL="${UC_GROUP_PRINCIPAL:-_workspace_users_${CATALOG_NAME}}"
VERIFY_PRINCIPAL="${VERIFY_PRINCIPAL:-}"
KV_RESOURCE_ID="${KV_RESOURCE_ID:-}"
KV_DNS_NAME="${KV_DNS_NAME:-}"
KV_TENANT_ID="${KV_TENANT_ID:-$(az account show --query tenantId -o tsv)}"
KEYVAULT_NAME="${KEYVAULT_NAME:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"

if [[ -n "${KEYVAULT_NAME}" && ( -z "${KV_RESOURCE_ID}" || -z "${KV_DNS_NAME}" ) ]]; then
  if [[ -n "${RESOURCE_GROUP}" ]]; then
    KV_RESOURCE_ID="${KV_RESOURCE_ID:-$(az keyvault show -g "${RESOURCE_GROUP}" -n "${KEYVAULT_NAME}" --query id -o tsv)}"
    KV_DNS_NAME="${KV_DNS_NAME:-$(az keyvault show -g "${RESOURCE_GROUP}" -n "${KEYVAULT_NAME}" --query properties.vaultUri -o tsv)}"
  else
    KV_RESOURCE_ID="${KV_RESOURCE_ID:-$(az keyvault show -n "${KEYVAULT_NAME}" --query id -o tsv)}"
    KV_DNS_NAME="${KV_DNS_NAME:-$(az keyvault show -n "${KEYVAULT_NAME}" --query properties.vaultUri -o tsv)}"
  fi
fi

if [[ -z "${KV_RESOURCE_ID}" || -z "${KV_DNS_NAME}" || -z "${KV_TENANT_ID}" ]]; then
  echo "KV metadata is required. Set KV_RESOURCE_ID, KV_DNS_NAME, KV_TENANT_ID (or KEYVAULT_NAME)." >&2
  exit 1
fi

CURRENT_STAGE="preflight"
log "starting SEC-003/SEC-004 binding window"
log "target=${TARGET}, run_id=${RUN_ID}, catalog=${CATALOG_NAME}, external_location=${EXTERNAL_LOCATION_NAME}, scope=${SECRET_SCOPE}"

databricks auth describe >/dev/null
az account show >/dev/null

databricks catalogs get "${CATALOG_NAME}" --output json >/dev/null
for schema_name in bronze silver gold; do
  databricks schemas get "${CATALOG_NAME}.${schema_name}" --output json >/dev/null
done
databricks external-locations get "${EXTERNAL_LOCATION_NAME}" --output json >/dev/null

if [[ -z "${VERIFY_PRINCIPAL}" ]]; then
  VERIFY_PRINCIPAL="$(databricks current-user me --output json | jq -r '.userName')"
fi

CURRENT_STAGE="sec003_grants"
log "applying SEC-003 grant matrix"

mapfile -t PRINCIPALS < <(printf '%s\n%s\n' "${UC_GROUP_PRINCIPAL}" "${VERIFY_PRINCIPAL}" | awk 'NF && !seen[$0]++')

for principal in "${PRINCIPALS[@]}"; do
  apply_grant catalog "${CATALOG_NAME}" "${principal}" USE_CATALOG

  for schema_name in bronze silver gold; do
    apply_grant schema "${CATALOG_NAME}.${schema_name}" "${principal}" USE_SCHEMA SELECT MODIFY
  done

  apply_grant external_location "${EXTERNAL_LOCATION_NAME}" "${principal}" READ_FILES WRITE_FILES CREATE_EXTERNAL_TABLE
  log "grant applied: principal=${principal}"
done

CURRENT_STAGE="sec004_scope_transition"
log "evaluating secret scope backend"

SCOPE_BACKEND="$(read_scope_backend "${SECRET_SCOPE}")"
if [[ -z "${SCOPE_BACKEND}" ]]; then
  log "scope not found, creating KV-backed scope: ${SECRET_SCOPE}"
  create_kv_backed_scope "${SECRET_SCOPE}"
elif [[ "${SCOPE_BACKEND}" == "DATABRICKS" ]]; then
  log "scope backend is DATABRICKS, backing up ACL and recreating as AZURE_KEYVAULT"
  databricks secrets list-acls "${SECRET_SCOPE}" --output json > "${ACL_BACKUP_FILE}" || true
  databricks secrets delete-scope "${SECRET_SCOPE}" >/dev/null
  create_kv_backed_scope "${SECRET_SCOPE}"
elif [[ "${SCOPE_BACKEND}" == "AZURE_KEYVAULT" ]]; then
  log "scope already KV-backed: ${SECRET_SCOPE}"
else
  echo "unexpected scope backend type: ${SCOPE_BACKEND}" >&2
  exit 1
fi

CURRENT_STAGE="postcheck"
FINAL_BACKEND="$(read_scope_backend "${SECRET_SCOPE}")"
if [[ "${FINAL_BACKEND}" != "AZURE_KEYVAULT" ]]; then
  echo "scope backend validation failed: expected AZURE_KEYVAULT, got ${FINAL_BACKEND}" >&2
  exit 1
fi

cat > "${SUMMARY_FILE}" <<EOF
# SEC-003 + SEC-004 Binding Window Result

- date_utc: ${TS_UTC}
- target: ${TARGET}
- run_id: ${RUN_ID}
- catalog: ${CATALOG_NAME}
- external_location: ${EXTERNAL_LOCATION_NAME}
- secret_scope: ${SECRET_SCOPE}
- secret_key: ${SECRET_KEY}
- group_principal: ${UC_GROUP_PRINCIPAL}
- verify_principal: ${VERIFY_PRINCIPAL}
- final_scope_backend: ${FINAL_BACKEND}
- acl_backup_file: ${ACL_BACKUP_FILE}
- execution_log: ${LOG_FILE}
EOF

log "binding window completed successfully"
log "summary: ${SUMMARY_FILE}"
