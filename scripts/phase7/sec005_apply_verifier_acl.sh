#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

ASSERTION_FILE="${LOG_DIR}/20260223_sec005_verifier_acl_assertions.json"
LOG_FILE="${LOG_DIR}/20260223_sec005_verifier_acl_apply.log"

TARGET="dev"
MODE="dry-run"
CATALOG_NAME=""
PRINCIPAL=""
SCHEMAS=(bronze silver gold)

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/phase7/sec005_apply_verifier_acl.sh --target <dev|prod-secure> --catalog <catalog-name> --principal <principal> [--dry-run|--apply]

Options:
  --target <dev|prod-secure>
  --catalog <catalog-name>
  --principal <principal>
  --dry-run
  --apply
USAGE
}

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${LOG_FILE}" >&2
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
    --principal)
      PRINCIPAL="${2:-}"
      shift 2
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --apply)
      MODE="apply"
      shift
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

if [[ -z "${PRINCIPAL}" ]]; then
  echo "--principal is required" >&2
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

log "verifier_acl_start target=${TARGET} mode=${MODE} principal=${PRINCIPAL} catalog=${CATALOG_NAME}"

if [[ "${MODE}" == "apply" ]]; then
  apply_grant catalog "${CATALOG_NAME}" "${PRINCIPAL}" USE_CATALOG
  for schema_name in "${SCHEMAS[@]}"; do
    apply_grant schema "${CATALOG_NAME}.${schema_name}" "${PRINCIPAL}" USE_SCHEMA SELECT MODIFY
  done
  log "verifier_acl_applied principal=${PRINCIPAL} catalog=${CATALOG_NAME}"
else
  log "verifier_acl_dryrun principal=${PRINCIPAL} catalog=${CATALOG_NAME}"
fi

USE_CATALOG_OK=0
USE_SCHEMA_OK=1
SELECT_OK=1
MODIFY_OK=1

if has_privilege catalog "${CATALOG_NAME}" "${PRINCIPAL}" USE_CATALOG; then
  USE_CATALOG_OK=1
fi

for schema_name in "${SCHEMAS[@]}"; do
  full_schema="${CATALOG_NAME}.${schema_name}"
  if ! has_privilege schema "${full_schema}" "${PRINCIPAL}" USE_SCHEMA; then
    USE_SCHEMA_OK=0
  fi
  if ! has_privilege schema "${full_schema}" "${PRINCIPAL}" SELECT; then
    SELECT_OK=0
  fi
  if ! has_privilege schema "${full_schema}" "${PRINCIPAL}" MODIFY; then
    MODIFY_OK=0
  fi
done

jq -n \
  --arg ts_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg target "${TARGET}" \
  --arg mode "${MODE}" \
  --arg principal "${PRINCIPAL}" \
  --arg catalog "${CATALOG_NAME}" \
  --argjson use_catalog_ok "$(bool_json "${USE_CATALOG_OK}")" \
  --argjson use_schema_ok "$(bool_json "${USE_SCHEMA_OK}")" \
  --argjson select_ok "$(bool_json "${SELECT_OK}")" \
  --argjson modify_ok "$(bool_json "${MODIFY_OK}")" \
  '{
    ts_utc: $ts_utc,
    target: $target,
    mode: $mode,
    principal: $principal,
    catalog: $catalog,
    use_catalog_ok: $use_catalog_ok,
    use_schema_ok: $use_schema_ok,
    select_ok: $select_ok,
    modify_ok: $modify_ok
  }' > "${ASSERTION_FILE}"

log "verifier_acl_assertions_written path=${ASSERTION_FILE}"
cat "${ASSERTION_FILE}"
