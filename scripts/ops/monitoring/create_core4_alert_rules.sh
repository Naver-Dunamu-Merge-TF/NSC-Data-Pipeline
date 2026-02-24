#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
KQL_DIR="${ROOT_DIR}/scripts/ops/monitoring/kql"

ENV=""
RESOURCE_GROUP=""
DBW_RESOURCE_ID=""
LAW_RESOURCE_ID=""
LAW_GUID=""
LOCATION=""
EVALUATION_FREQUENCY="5m"
WINDOW_SIZE="5m"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/ops/monitoring/create_core4_alert_rules.sh \
    --env <dev|prod> \
    --resource-group <resource-group> \
    --dbw-resource-id <databricks-workspace-resource-id> \
    --law-resource-id <log-analytics-resource-id> \
    --law-guid <log-analytics-workspace-guid> \
    [--location <azure-location>] \
    [--evaluation-frequency <5m>] \
    [--window-size <5m>]

Notes:
- Core4 cardinality is fixed to 4 rules (D-051).
- Scope is pinned to LAW resource and queries are filtered by DBW resource id.
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

render_query() {
  local file_path="$1"
  local query
  query="$(cat "${file_path}")"
  query="${query//__DBW_RESOURCE_ID__/${DBW_RESOURCE_ID}}"
  query="${query//__ENV__/${ENV}}"
  printf '%s' "${query}" | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ *//' -e 's/ *$//'
}

upsert_rule() {
  local rule_name="$1"
  local description="$2"
  local severity="$3"
  local placeholder="$4"
  local kql_file="$5"
  local query
  local condition
  local condition_query

  query="$(render_query "${kql_file}")"
  condition="count '${placeholder}' > 0 at least 1 violations out of 1 aggregated points"
  condition_query="${placeholder}=${query}"

  if az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${rule_name}" >/dev/null 2>&1; then
    log "updating rule=${rule_name}"
    az monitor scheduled-query update \
      -g "${RESOURCE_GROUP}" \
      -n "${rule_name}" \
      --description "${description}" \
      --severity "${severity}" \
      --evaluation-frequency "${EVALUATION_FREQUENCY}" \
      --window-size "${WINDOW_SIZE}" \
      --condition "${condition}" \
      --condition-query "${condition_query}" \
      --disabled false \
      --tags "bundle=G2-2" "env=${ENV}" "task=MON-003" "core=core4" >/dev/null
  else
    log "creating rule=${rule_name}"
    az monitor scheduled-query create \
      -g "${RESOURCE_GROUP}" \
      -n "${rule_name}" \
      --location "${LOCATION}" \
      --scopes "${LAW_RESOURCE_ID}" \
      --description "${description}" \
      --severity "${severity}" \
      --evaluation-frequency "${EVALUATION_FREQUENCY}" \
      --window-size "${WINDOW_SIZE}" \
      --condition "${condition}" \
      --condition-query "${condition_query}" \
      --auto-mitigate true \
      --disabled false \
      --tags "bundle=G2-2" "env=${ENV}" "task=MON-003" "core=core4" >/dev/null
  fi

  local enabled
  enabled="$(az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${rule_name}" --query enabled -o tsv)"
  echo "rule=${rule_name} enabled=${enabled}"
  test "${enabled}" = "true"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV="${2:-}"
      shift 2
      ;;
    --resource-group)
      RESOURCE_GROUP="${2:-}"
      shift 2
      ;;
    --dbw-resource-id)
      DBW_RESOURCE_ID="${2:-}"
      shift 2
      ;;
    --law-resource-id)
      LAW_RESOURCE_ID="${2:-}"
      shift 2
      ;;
    --law-guid)
      LAW_GUID="${2:-}"
      shift 2
      ;;
    --location)
      LOCATION="${2:-}"
      shift 2
      ;;
    --evaluation-frequency)
      EVALUATION_FREQUENCY="${2:-}"
      shift 2
      ;;
    --window-size)
      WINDOW_SIZE="${2:-}"
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

if [[ -z "${ENV}" || -z "${RESOURCE_GROUP}" || -z "${DBW_RESOURCE_ID}" || -z "${LAW_RESOURCE_ID}" || -z "${LAW_GUID}" ]]; then
  echo "required arguments are missing" >&2
  usage
  exit 1
fi

if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "--env must be one of: dev, prod" >&2
  exit 1
fi

require_cmd az
require_cmd sed
require_cmd tr

if [[ -z "${LOCATION}" ]]; then
  LOCATION="$(az resource show --ids "${LAW_RESOURCE_ID}" --query location -o tsv)"
fi

if [[ -z "${LOCATION}" ]]; then
  echo "failed to resolve location from LAW resource" >&2
  exit 1
fi

log "core4_upsert_start env=${ENV} rg=${RESOURCE_GROUP} location=${LOCATION} law_guid=${LAW_GUID}"

RULE_A_JOB_FAILURE="${ENV}-dp-pipeline-a-job-failure-alert"
RULE_A_SUCCESS_DELAY="${ENV}-dp-pipeline-a-success-delay-alert"
RULE_B_RETRY_EXHAUSTED="${ENV}-dp-pipeline-b-retry-exhausted-alert"
RULE_C_CLUSTER_TIMEOUT="${ENV}-dp-pipeline-c-cluster-timeout-alert"

declare -a CORE4_RULES=(
  "${RULE_A_JOB_FAILURE}"
  "${RULE_A_SUCCESS_DELAY}"
  "${RULE_B_RETRY_EXHAUSTED}"
  "${RULE_C_CLUSTER_TIMEOUT}"
)

UNIQUE_COUNT="$(printf '%s\n' "${CORE4_RULES[@]}" | sort -u | wc -l | tr -d ' ')"
if [[ "${UNIQUE_COUNT}" != "4" ]]; then
  echo "core4 cardinality check failed: expected 4 unique names, got ${UNIQUE_COUNT}" >&2
  exit 1
fi

upsert_rule \
  "${RULE_A_JOB_FAILURE}" \
  "MON-003 Core4: pipeline A run failure detection" \
  "1" \
  "A_JOB_FAILURE_QUERY" \
  "${KQL_DIR}/core4_job_failure.kql"

upsert_rule \
  "${RULE_A_SUCCESS_DELAY}" \
  "MON-003 Core4: pipeline A recent success delay (>20m)" \
  "2" \
  "A_SUCCESS_DELAY_QUERY" \
  "${KQL_DIR}/core4_success_delay.kql"

upsert_rule \
  "${RULE_B_RETRY_EXHAUSTED}" \
  "MON-003 Core4: pipeline B retry exhausted after max retries" \
  "1" \
  "B_RETRY_EXHAUSTED_QUERY" \
  "${KQL_DIR}/core4_retry_exhausted.kql"

upsert_rule \
  "${RULE_C_CLUSTER_TIMEOUT}" \
  "MON-003 Core4: pipeline C cluster start failure or timeout" \
  "1" \
  "C_CLUSTER_TIMEOUT_QUERY" \
  "${KQL_DIR}/core4_cluster_start_timeout.kql"

log "core4_upsert_done count=4"
