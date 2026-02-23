#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

ASSERTION_FILE="${LOG_DIR}/20260223_sec005_acl_assertions.json"
LOG_FILE="${LOG_DIR}/20260223_sec005_run_as_acl_apply.log"

TARGET="dev"
MODE="dry-run"
RUN_AS_PRINCIPAL=""
CATALOG_NAME=""
SCHEMAS=(bronze silver gold)

usage() {
  cat <<'EOF'
Usage:
  bash scripts/phase7/sec005_run_as_acl_apply.sh --target <dev|prod-secure> --run-as-principal <service-principal-name-or-app-id> [--dry-run|--apply] [--catalog <catalog>]

Options:
  --target <dev|prod-secure>
  --run-as-principal <service-principal-name-or-app-id>
  --dry-run
  --apply
  --catalog <catalog-name>
EOF
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
parts = key.split(".")
cur = cfg
for part in parts:
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
    'any(.privilege_assignments[]?;
      .principal == $principal
      and any(.privileges[]?; . == $privilege or . == "ALL_PRIVILEGES")
    )' >/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --run-as-principal)
      RUN_AS_PRINCIPAL="${2:-}"
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
    --catalog)
      CATALOG_NAME="${2:-}"
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
  TARGET_SUFFIX="dev"
  if [[ -z "${DATABRICKS_HOST:-}" ]]; then
    DEV_HOST="$(resolve_dev_config_value "databricks.workspace_host")"
    if [[ -n "${DEV_HOST}" ]]; then
      export DATABRICKS_HOST="${DEV_HOST}"
    fi
  fi
  if [[ -z "${CATALOG_NAME}" ]]; then
    CATALOG_NAME="$(resolve_dev_config_value "databricks.catalog")"
  fi
else
  TARGET_SUFFIX="prod"
fi

if [[ -z "${CATALOG_NAME}" ]]; then
  echo "catalog is required (provide --catalog or ensure configs/dev.yaml has databricks.catalog)" >&2
  exit 1
fi

log "SEC-005 run_as/ACL start target=${TARGET} mode=${MODE} run_as_principal=${RUN_AS_PRINCIPAL} catalog=${CATALOG_NAME}"

JOB_NAMES=(
  "data-pipeline-a-${TARGET_SUFFIX}"
  "data-pipeline-silver-${TARGET_SUFFIX}"
  "data-pipeline-b-${TARGET_SUFFIX}"
  "data-pipeline-c-${TARGET_SUFFIX}"
)

JOBS_JSON="$(databricks jobs list -o json)"
JOB_IDS=()
MISSING_JOBS=()
CHANGED_JOBS=()

for job_name in "${JOB_NAMES[@]}"; do
  job_id="$(echo "${JOBS_JSON}" | jq -r --arg name "${job_name}" '.[] | select(.settings.name == $name) | .job_id' | head -n 1)"
  if [[ -z "${job_id}" || "${job_id}" == "null" ]]; then
    MISSING_JOBS+=("${job_name}")
    log "job_missing name=${job_name}"
    continue
  fi
  JOB_IDS+=("${job_id}")

  job_json="$(databricks jobs get "${job_id}" -o json)"
  current_principal="$(echo "${job_json}" | jq -r '.settings.run_as.service_principal_name // .settings.run_as.user_name // .run_as_user_name // empty')"
  log "job_run_as_before job_id=${job_id} name=${job_name} principal=${current_principal:-<none>}"

  if [[ "${MODE}" == "apply" && "${current_principal}" != "${RUN_AS_PRINCIPAL}" ]]; then
    payload_file="$(mktemp)"
    echo "${job_json}" | jq \
      --arg sp "${RUN_AS_PRINCIPAL}" \
      '{job_id: .job_id, new_settings: (.settings + {run_as: {service_principal_name: $sp}})}' \
      > "${payload_file}"
    databricks jobs reset --json @"${payload_file}" >/dev/null
    rm -f "${payload_file}"
    CHANGED_JOBS+=("${job_name}")
    log "job_run_as_updated job_id=${job_id} name=${job_name} principal=${RUN_AS_PRINCIPAL}"
  elif [[ "${MODE}" == "dry-run" ]]; then
    log "job_run_as_dryrun job_id=${job_id} name=${job_name} target_principal=${RUN_AS_PRINCIPAL}"
  fi
done

if [[ "${MODE}" == "apply" ]]; then
  apply_grant catalog "${CATALOG_NAME}" "${RUN_AS_PRINCIPAL}" USE_CATALOG
  for schema_name in "${SCHEMAS[@]}"; do
    apply_grant schema "${CATALOG_NAME}.${schema_name}" "${RUN_AS_PRINCIPAL}" USE_SCHEMA SELECT MODIFY
  done
  log "uc_grants_applied principal=${RUN_AS_PRINCIPAL}"
else
  log "uc_grants_dryrun catalog=${CATALOG_NAME} principal=${RUN_AS_PRINCIPAL} privileges=USE_CATALOG,USE_SCHEMA,SELECT,MODIFY"
fi

RUN_AS_OK=1
if [[ "${#JOB_IDS[@]}" -eq 0 ]]; then
  RUN_AS_OK=0
fi

for job_id in "${JOB_IDS[@]}"; do
  effective_sp="$(databricks jobs get "${job_id}" -o json | jq -r '.settings.run_as.service_principal_name // empty')"
  if [[ "${effective_sp}" != "${RUN_AS_PRINCIPAL}" ]]; then
    RUN_AS_OK=0
  fi
done

USE_CATALOG_OK=0
USE_SCHEMA_OK=1
SELECT_OK=1
MODIFY_OK=1

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

JOB_NAMES_JSON="$(printf '%s\n' "${JOB_NAMES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
JOB_IDS_JSON="$(printf '%s\n' "${JOB_IDS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0) | tonumber)')"
MISSING_JOBS_JSON="$(printf '%s\n' "${MISSING_JOBS[@]:-}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
CHANGED_JOBS_JSON="$(printf '%s\n' "${CHANGED_JOBS[@]:-}" | jq -Rsc 'split("\n") | map(select(length > 0))')"

jq -n \
  --arg ts_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg target "${TARGET}" \
  --arg mode "${MODE}" \
  --arg run_as_principal "${RUN_AS_PRINCIPAL}" \
  --arg catalog "${CATALOG_NAME}" \
  --argjson job_names "${JOB_NAMES_JSON}" \
  --argjson job_ids "${JOB_IDS_JSON}" \
  --argjson missing_jobs "${MISSING_JOBS_JSON}" \
  --argjson changed_jobs "${CHANGED_JOBS_JSON}" \
  --argjson run_as_ok "$(bool_json "${RUN_AS_OK}")" \
  --argjson use_catalog_ok "$(bool_json "${USE_CATALOG_OK}")" \
  --argjson use_schema_ok "$(bool_json "${USE_SCHEMA_OK}")" \
  --argjson select_ok "$(bool_json "${SELECT_OK}")" \
  --argjson modify_ok "$(bool_json "${MODIFY_OK}")" \
  '{
    ts_utc: $ts_utc,
    target: $target,
    mode: $mode,
    run_as_principal: $run_as_principal,
    catalog: $catalog,
    job_names: $job_names,
    job_ids: $job_ids,
    missing_jobs: $missing_jobs,
    changed_jobs: $changed_jobs,
    run_as_ok: $run_as_ok,
    use_catalog_ok: $use_catalog_ok,
    use_schema_ok: $use_schema_ok,
    select_ok: $select_ok,
    modify_ok: $modify_ok
  }' > "${ASSERTION_FILE}"

log "assertions_written path=${ASSERTION_FILE}"
cat "${ASSERTION_FILE}"
