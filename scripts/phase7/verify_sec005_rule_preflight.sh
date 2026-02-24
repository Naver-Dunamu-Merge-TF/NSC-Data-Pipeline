#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

TARGET="dev"
CATALOG_NAME=""
RUN_AS_PRINCIPAL=""
WAREHOUSE_ID="${DATABRICKS_SQL_WAREHOUSE_ID:-}"
OUTPUT_JSON="${LOG_DIR}/20260224_sec005_rule_preflight.json"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/phase7/verify_sec005_rule_preflight.sh --target <dev|prod-secure> --catalog <catalog-name> --run-as-principal <sp-app-id> [--warehouse-id <warehouse-id>] [--output-json <path>]

Options:
  --target <dev|prod-secure>
  --catalog <catalog-name>
  --run-as-principal <sp-app-id>
  --warehouse-id <warehouse-id>
  --output-json <path>
USAGE
}

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

bool_json() {
  if [[ "$1" == "1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

resolve_dev_config_value() {
  local key="$1"
  python - "$ROOT_DIR" "$key" <<'PY'
import sys
from pathlib import Path
import yaml

root = Path(sys.argv[1])
key = sys.argv[2]
cfg = yaml.safe_load((root / "configs/dev.yaml").read_text(encoding="utf-8")) or {}
cur = cfg
for part in key.split("."):
    if not isinstance(cur, dict) or part not in cur:
        print("")
        raise SystemExit(0)
    cur = cur[part]
print("" if cur is None else str(cur))
PY
}

has_privilege() {
  local securable_type="$1"
  local full_name="$2"
  local principal="$3"
  local privilege="$4"

  local grants_json
  if ! grants_json="$(databricks grants get "${securable_type}" "${full_name}" -o json 2>/dev/null)"; then
    return 1
  fi

  echo "${grants_json}" | jq -e \
    --arg principal "${principal}" \
    --arg privilege "${privilege}" \
    'any(.privilege_assignments[]?; .principal == $principal and any(.privileges[]?; . == $privilege or . == "ALL_PRIVILEGES"))' >/dev/null
}

table_exists() {
  local full_name="$1"
  if databricks tables get "${full_name}" -o json >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

resolve_sql_warehouse_id() {
  if [[ -n "${WAREHOUSE_ID}" ]]; then
    return 0
  fi

  local warehouses_json
  if ! warehouses_json="$(databricks warehouses list -o json 2>/dev/null)"; then
    return 1
  fi

  WAREHOUSE_ID="$(echo "${warehouses_json}" | jq -r '
    (if type == "array" then .
     elif has("warehouses") then .warehouses
     else [] end)
    | (map(select((.state // "") == "RUNNING")) + .)
    | map(.id // .warehouse_id // .endpoint_id)
    | map(select(. != null and . != ""))
    | .[0] // ""
  ')"

  [[ -n "${WAREHOUSE_ID}" ]]
}

execute_sql_scalar() {
  local statement="$1"
  local response
  local statement_id
  local state

  response="$(databricks api post /api/2.0/sql/statements --json "$(jq -nc --arg statement "${statement}" --arg warehouse_id "${WAREHOUSE_ID}" '{statement:$statement, warehouse_id:$warehouse_id, disposition:"INLINE"}')" -o json)"
  statement_id="$(echo "${response}" | jq -r '.statement_id // empty')"
  if [[ -z "${statement_id}" ]]; then
    return 1
  fi

  state="$(echo "${response}" | jq -r '.status.state // ""')"
  while [[ "${state}" == "PENDING" || "${state}" == "RUNNING" ]]; do
    sleep 2
    response="$(databricks api get "/api/2.0/sql/statements/${statement_id}" -o json)"
    state="$(echo "${response}" | jq -r '.status.state // ""')"
  done

  if [[ "${state}" != "SUCCEEDED" ]]; then
    return 1
  fi

  echo "${response}" | jq -r '(.result.data_array[0][0] // "")'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --catalog)
      CATALOG_NAME="${2:-}"
      shift 2
      ;;
    --run-as-principal)
      RUN_AS_PRINCIPAL="${2:-}"
      shift 2
      ;;
    --warehouse-id)
      WAREHOUSE_ID="${2:-}"
      shift 2
      ;;
    --output-json)
      OUTPUT_JSON="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${TARGET}" != "dev" && "${TARGET}" != "prod-secure" ]]; then
  echo "invalid target: ${TARGET} (allowed: dev, prod-secure)" >&2
  exit 1
fi

if [[ -z "${RUN_AS_PRINCIPAL}" ]]; then
  echo "--run-as-principal is required" >&2
  exit 1
fi

require_cmd databricks
require_cmd jq
require_cmd python

if [[ -z "${DATABRICKS_AUTH_TYPE:-}" ]]; then
  export DATABRICKS_AUTH_TYPE="azure-cli"
fi

if [[ "${TARGET}" == "dev" ]]; then
  if [[ -z "${DATABRICKS_HOST:-}" ]]; then
    DEV_HOST="$(resolve_dev_config_value "databricks.workspace_host")"
    if [[ -n "${DEV_HOST}" ]]; then
      export DATABRICKS_HOST="${DEV_HOST}"
    fi
  fi
  if [[ -z "${CATALOG_NAME}" ]]; then
    CATALOG_NAME="$(resolve_dev_config_value "databricks.catalog")"
  fi
fi

if [[ -z "${CATALOG_NAME}" ]]; then
  echo "catalog is required (provide --catalog or ensure configs/dev.yaml has databricks.catalog)" >&2
  exit 1
fi

log "sec005_rule_preflight_start target=${TARGET} catalog=${CATALOG_NAME} run_as_principal=${RUN_AS_PRINCIPAL}"

USE_CATALOG_OK=0
USE_SCHEMA_OK=1
SELECT_OK=1
MODIFY_OK=1
SCHEMAS=(bronze silver gold)

if has_privilege catalog "${CATALOG_NAME}" "${RUN_AS_PRINCIPAL}" USE_CATALOG; then
  USE_CATALOG_OK=1
fi

for schema_name in "${SCHEMAS[@]}"; do
  full_schema="${CATALOG_NAME}.${schema_name}"
  if ! has_privilege schema "${full_schema}" "${RUN_AS_PRINCIPAL}" USE_SCHEMA; then
    USE_SCHEMA_OK=0
  fi
  if ! has_privilege schema "${full_schema}" "${RUN_AS_PRINCIPAL}" SELECT; then
    SELECT_OK=0
  fi
  if ! has_privilege schema "${full_schema}" "${RUN_AS_PRINCIPAL}" MODIFY; then
    MODIFY_OK=0
  fi
done

SP_ACL_OK=0
if [[ "${USE_CATALOG_OK}" -eq 1 && "${USE_SCHEMA_OK}" -eq 1 && "${SELECT_OK}" -eq 1 && "${MODIFY_OK}" -eq 1 ]]; then
  SP_ACL_OK=1
fi

RULE_TABLE_FQN="${CATALOG_NAME}.gold.dim_rule_scd2"
PIPELINE_STATE_FQN="${CATALOG_NAME}.gold.pipeline_state"
RULE_TABLE_EXISTS=0
PIPELINE_STATE_EXISTS=0
RULE_CURRENT_UNIQUENESS_OK=0
VIOLATING_CURRENT_METRIC_COUNT=-1
RULE_CURRENT_UNIQUENESS_ERROR=""

if table_exists "${RULE_TABLE_FQN}"; then
  RULE_TABLE_EXISTS=1
fi

if table_exists "${PIPELINE_STATE_FQN}"; then
  PIPELINE_STATE_EXISTS=1
fi

if [[ "${RULE_TABLE_EXISTS}" -eq 1 ]]; then
  if resolve_sql_warehouse_id; then
    duplicate_count_query="
SELECT COUNT(*)
FROM (
  SELECT domain, metric
  FROM ${RULE_TABLE_FQN}
  WHERE is_current = TRUE
  GROUP BY domain, metric
  HAVING COUNT(*) > 1
) t
"
    if duplicate_count="$(execute_sql_scalar "${duplicate_count_query}")"; then
      if [[ -z "${duplicate_count}" ]]; then
        duplicate_count="0"
      fi
      VIOLATING_CURRENT_METRIC_COUNT="${duplicate_count}"
      if [[ "${duplicate_count}" == "0" ]]; then
        RULE_CURRENT_UNIQUENESS_OK=1
      fi
    else
      RULE_CURRENT_UNIQUENESS_ERROR="failed_to_execute_sql_uniqueness_check"
    fi
  else
    RULE_CURRENT_UNIQUENESS_ERROR="sql_warehouse_id_unavailable"
  fi
fi

mkdir -p "$(dirname "${OUTPUT_JSON}")"

jq -n \
  --arg ts_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg target "${TARGET}" \
  --arg catalog "${CATALOG_NAME}" \
  --arg run_as_principal "${RUN_AS_PRINCIPAL}" \
  --arg warehouse_id "${WAREHOUSE_ID}" \
  --arg rule_table_fqn "${RULE_TABLE_FQN}" \
  --arg pipeline_state_fqn "${PIPELINE_STATE_FQN}" \
  --arg rule_current_uniqueness_error "${RULE_CURRENT_UNIQUENESS_ERROR}" \
  --argjson use_catalog_ok "$(bool_json "${USE_CATALOG_OK}")" \
  --argjson use_schema_ok "$(bool_json "${USE_SCHEMA_OK}")" \
  --argjson select_ok "$(bool_json "${SELECT_OK}")" \
  --argjson modify_ok "$(bool_json "${MODIFY_OK}")" \
  --argjson sp_acl_ok "$(bool_json "${SP_ACL_OK}")" \
  --argjson rule_table_exists "$(bool_json "${RULE_TABLE_EXISTS}")" \
  --argjson rule_current_uniqueness_ok "$(bool_json "${RULE_CURRENT_UNIQUENESS_OK}")" \
  --argjson violating_current_metric_count "${VIOLATING_CURRENT_METRIC_COUNT}" \
  --argjson pipeline_state_exists "$(bool_json "${PIPELINE_STATE_EXISTS}")" \
  '{
    ts_utc: $ts_utc,
    target: $target,
    catalog: $catalog,
    run_as_principal: $run_as_principal,
    warehouse_id: $warehouse_id,
    rule_table_fqn: $rule_table_fqn,
    pipeline_state_fqn: $pipeline_state_fqn,
    use_catalog_ok: $use_catalog_ok,
    use_schema_ok: $use_schema_ok,
    select_ok: $select_ok,
    modify_ok: $modify_ok,
    sp_acl_ok: $sp_acl_ok,
    rule_table_exists: $rule_table_exists,
    rule_current_uniqueness_ok: $rule_current_uniqueness_ok,
    violating_current_metric_count: $violating_current_metric_count,
    pipeline_state_exists: $pipeline_state_exists,
    rule_current_uniqueness_error: $rule_current_uniqueness_error
  }' > "${OUTPUT_JSON}"

log "sec005_rule_preflight_summary path=${OUTPUT_JSON}"
cat "${OUTPUT_JSON}"

if jq -e '.sp_acl_ok and .rule_table_exists and .rule_current_uniqueness_ok and .pipeline_state_exists' "${OUTPUT_JSON}" >/dev/null; then
  exit 0
fi

exit 1
