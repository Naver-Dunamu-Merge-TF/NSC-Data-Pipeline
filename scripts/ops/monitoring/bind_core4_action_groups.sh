#!/usr/bin/env bash
set -euo pipefail

ENV=""
RESOURCE_GROUP=""
PLATFORM_ACTION_GROUP_ID=""
OPS_ACTION_GROUP_ID=""

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/ops/monitoring/bind_core4_action_groups.sh \
    --env <dev|prod> \
    --resource-group <resource-group> \
    --platform-action-group-id <action-group-id-platform> \
    --ops-action-group-id <action-group-id-ops>
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

expected_action_group_for_rule() {
  local rule_name="$1"
  case "${rule_name}" in
    *"job-failure-alert"|*"cluster-timeout-alert")
      printf '%s' "${PLATFORM_ACTION_GROUP_ID}"
      ;;
    *)
      printf '%s' "${OPS_ACTION_GROUP_ID}"
      ;;
  esac
}

collect_action_group_ids() {
  local rule_name="$1"
  az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${rule_name}" --query "actions.actionGroups" -o json \
    | jq -r '
      if . == null then empty
      elif type == "array" then
        .[] | if type == "string" then . else (.actionGroupId // empty) end
      else empty end
    '
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
    --platform-action-group-id)
      PLATFORM_ACTION_GROUP_ID="${2:-}"
      shift 2
      ;;
    --ops-action-group-id)
      OPS_ACTION_GROUP_ID="${2:-}"
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

if [[ -z "${ENV}" || -z "${RESOURCE_GROUP}" || -z "${PLATFORM_ACTION_GROUP_ID}" || -z "${OPS_ACTION_GROUP_ID}" ]]; then
  echo "required arguments are missing" >&2
  usage
  exit 1
fi

if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "--env must be one of: dev, prod" >&2
  exit 1
fi

require_cmd az
require_cmd jq
require_cmd rg

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

log "core4_action_group_binding_start env=${ENV} rg=${RESOURCE_GROUP}"

for rule_name in "${CORE4_RULES[@]}"; do
  if ! az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${rule_name}" >/dev/null 2>&1; then
    echo "missing scheduled query rule: ${rule_name}" >&2
    exit 1
  fi

  expected_ag_id="$(expected_action_group_for_rule "${rule_name}")"

  log "binding rule=${rule_name} expected_ag=${expected_ag_id}"
  az monitor scheduled-query update \
    -g "${RESOURCE_GROUP}" \
    -n "${rule_name}" \
    --action-groups "${expected_ag_id}" >/dev/null

  actual_ag_ids="$(collect_action_group_ids "${rule_name}")"
  echo "rule=${rule_name} expected_ag=${expected_ag_id} actual_ag=${actual_ag_ids}"

  expected_lower="$(printf '%s' "${expected_ag_id}" | tr '[:upper:]' '[:lower:]')"
  actual_lower_lines="$(printf '%s\n' "${actual_ag_ids}" | tr '[:upper:]' '[:lower:]')"

  if ! printf '%s\n' "${actual_lower_lines}" | rg -q -F "${expected_lower}"; then
    echo "action group binding mismatch for ${rule_name}" >&2
    exit 1
  fi

done

log "core4_action_group_binding_done count=4"
