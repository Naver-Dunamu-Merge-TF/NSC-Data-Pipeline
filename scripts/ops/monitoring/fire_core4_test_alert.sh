#!/usr/bin/env bash
set -euo pipefail

ENV=""
RESOURCE_GROUP=""
TEST_RULE_NAME=""
POLL_INTERVAL_SEC=20
TIMEOUT_SEC=600
SUBSCRIPTION_ID=""
FORCE_SUCCESS_DELAY_THRESHOLD_MIN=""
ORIGINAL_RULE_QUERY=""
ORIGINAL_EVALUATION_FREQUENCY=""
ORIGINAL_WINDOW_SIZE=""

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/ops/monitoring/fire_core4_test_alert.sh \
    --env <dev|prod> \
    --resource-group <resource-group> \
    [--test-rule-name <scheduled-query-rule-name>] \
    [--poll-interval-sec 20] \
    [--timeout-sec 600] \
    [--subscription-id <subscription-id>] \
    [--force-success-delay-threshold-min <minutes>]

Default test rule name:
- <env>-dp-pipeline-a-success-delay-alert
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

resolve_action_group_ids() {
  local rule_name="$1"
  az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${rule_name}" --query "actions.actionGroups" -o json \
    | jq -r '
      if . == null then empty
      elif type == "array" then
        .[] | if type == "string" then . else (.actionGroupId // empty) end
      else empty end
    '
}

print_action_group_receivers() {
  local action_group_id="$1"
  az monitor action-group show --ids "${action_group_id}" -o json \
    | jq -r '
      . as $ag
      | [
          (.emailReceivers[]? | "email:" + .emailAddress),
          (.webhookReceivers[]? | "webhook:" + .name),
          (.smsReceivers[]? | "sms:" + (.countryCode|tostring) + .phoneNumber),
          (.azureFunctionReceivers[]? | "azure-function:" + .name),
          (.logicAppReceivers[]? | "logic-app:" + .name)
        ]
      | flatten
      | if length == 0 then "none" else join(",") end
      | "action_group_name=" + ($ag.name // "") + " action_group_id=" + ($ag.id // "") + " receivers=" + .
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
    --test-rule-name)
      TEST_RULE_NAME="${2:-}"
      shift 2
      ;;
    --poll-interval-sec)
      POLL_INTERVAL_SEC="${2:-}"
      shift 2
      ;;
    --timeout-sec)
      TIMEOUT_SEC="${2:-}"
      shift 2
      ;;
    --subscription-id)
      SUBSCRIPTION_ID="${2:-}"
      shift 2
      ;;
    --force-success-delay-threshold-min)
      FORCE_SUCCESS_DELAY_THRESHOLD_MIN="${2:-}"
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

if [[ -z "${ENV}" || -z "${RESOURCE_GROUP}" ]]; then
  echo "required arguments are missing" >&2
  usage
  exit 1
fi

if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "--env must be one of: dev, prod" >&2
  exit 1
fi

if ! [[ "${POLL_INTERVAL_SEC}" =~ ^[0-9]+$ ]] || [[ "${POLL_INTERVAL_SEC}" -le 0 ]]; then
  echo "--poll-interval-sec must be a positive integer" >&2
  exit 1
fi

if ! [[ "${TIMEOUT_SEC}" =~ ^[0-9]+$ ]] || [[ "${TIMEOUT_SEC}" -le 0 ]]; then
  echo "--timeout-sec must be a positive integer" >&2
  exit 1
fi

if [[ -n "${FORCE_SUCCESS_DELAY_THRESHOLD_MIN}" ]]; then
  if ! [[ "${FORCE_SUCCESS_DELAY_THRESHOLD_MIN}" =~ ^[0-9]+$ ]] || [[ "${FORCE_SUCCESS_DELAY_THRESHOLD_MIN}" -lt 0 ]]; then
    echo "--force-success-delay-threshold-min must be a non-negative integer" >&2
    exit 1
  fi
fi

require_cmd az
require_cmd jq

if [[ -z "${TEST_RULE_NAME}" ]]; then
  TEST_RULE_NAME="${ENV}-dp-pipeline-a-success-delay-alert"
fi

if [[ -z "${SUBSCRIPTION_ID}" ]]; then
  SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
fi

if [[ -z "${SUBSCRIPTION_ID}" ]]; then
  echo "failed to resolve subscription id" >&2
  exit 1
fi

RULE_ID="$(az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${TEST_RULE_NAME}" --query id -o tsv)"
if [[ -z "${RULE_ID}" ]]; then
  echo "failed to resolve rule id for ${TEST_RULE_NAME}" >&2
  exit 1
fi

RULE_ID_LOWER="$(printf '%s' "${RULE_ID}" | tr '[:upper:]' '[:lower:]')"
RESOURCE_GROUP_LOWER="$(printf '%s' "${RESOURCE_GROUP}" | tr '[:upper:]' '[:lower:]')"
START_TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DEADLINE_EPOCH="$(( $(date +%s) + TIMEOUT_SEC ))"

restore_query_if_needed() {
  if [[ -n "${ORIGINAL_RULE_QUERY}" ]]; then
    log "restoring original query for rule=${TEST_RULE_NAME}"
    az monitor scheduled-query update \
      -g "${RESOURCE_GROUP}" \
      -n "${TEST_RULE_NAME}" \
      --evaluation-frequency "${ORIGINAL_EVALUATION_FREQUENCY}" \
      --window-size "${ORIGINAL_WINDOW_SIZE}" \
      --set "criteria.allOf[0].query=${ORIGINAL_RULE_QUERY}" >/dev/null
  fi
}

trap restore_query_if_needed EXIT

if [[ -n "${FORCE_SUCCESS_DELAY_THRESHOLD_MIN}" ]]; then
  if [[ "${TEST_RULE_NAME}" != *"success-delay-alert" ]]; then
    echo "--force-success-delay-threshold-min is only supported for success-delay rules" >&2
    exit 1
  fi

  ORIGINAL_RULE_QUERY="$(az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${TEST_RULE_NAME}" --query "criteria.allOf[0].query" -o tsv)"
  ORIGINAL_EVALUATION_FREQUENCY="$(az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${TEST_RULE_NAME}" --query "evaluationFrequency" -o tsv)"
  ORIGINAL_WINDOW_SIZE="$(az monitor scheduled-query show -g "${RESOURCE_GROUP}" -n "${TEST_RULE_NAME}" --query "windowSize" -o tsv)"
  UPDATED_QUERY="$(printf '%s' "${ORIGINAL_RULE_QUERY}" | sed -E "s/ago\\([0-9]+m\\)/ago(${FORCE_SUCCESS_DELAY_THRESHOLD_MIN}m)/g")"

  if [[ "${UPDATED_QUERY}" == "${ORIGINAL_RULE_QUERY}" ]]; then
    echo "failed to update stale threshold in query for rule ${TEST_RULE_NAME}" >&2
    exit 1
  fi

  log "temporarily overriding success-delay threshold to ${FORCE_SUCCESS_DELAY_THRESHOLD_MIN}m and eval/window to 1m for rule=${TEST_RULE_NAME}"
  az monitor scheduled-query update \
    -g "${RESOURCE_GROUP}" \
    -n "${TEST_RULE_NAME}" \
    --evaluation-frequency "1m" \
    --window-size "1m" \
    --set "criteria.allOf[0].query=${UPDATED_QUERY}" >/dev/null
fi

log "core4_test_fire_start env=${ENV} rg=${RESOURCE_GROUP} rule=${TEST_RULE_NAME} poll=${POLL_INTERVAL_SEC}s timeout=${TIMEOUT_SEC}s"
echo "test_rule=${TEST_RULE_NAME}"
echo "rule_id=${RULE_ID}"
echo "start_ts_utc=${START_TS_UTC}"

ALERTS_URL="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.AlertsManagement/alerts?api-version=2019-03-01"

while true; do
  now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  alerts_json="$(az rest --method get --url "${ALERTS_URL}" -o json)"
  alert_payload="$(echo "${alerts_json}" | jq -c --arg rule_id "${RULE_ID_LOWER}" --arg start_ts "${START_TS_UTC}" --arg rg "${RESOURCE_GROUP_LOWER}" '
    .value[]?
    | select((.properties.essentials.targetResourceGroup // "" | ascii_downcase) == $rg)
    | select((.properties.essentials.alertRule // "" | ascii_downcase) == $rule_id)
    | select((.properties.essentials.monitorCondition // "") == "Fired")
    | select((.properties.essentials.startDateTime // "") >= $start_ts)
    | {
        alert_id: .id,
        alert_name: (.name // ""),
        startDateTime: (.properties.essentials.startDateTime // ""),
        monitorCondition: (.properties.essentials.monitorCondition // ""),
        alertState: (.properties.essentials.alertState // ""),
        severity: (.properties.essentials.severity // ""),
        monitorService: (.properties.essentials.monitorService // "")
      }
    | first
  ' 2>/dev/null || true)"

  if [[ -n "${alert_payload}" && "${alert_payload}" != "null" ]]; then
    echo "poll_ts_utc=${now_utc} fired=true"
    echo "alert_payload=${alert_payload}"

    action_group_ids="$(resolve_action_group_ids "${TEST_RULE_NAME}")"
    if [[ -n "${action_group_ids}" ]]; then
      while IFS= read -r action_group_id; do
        [[ -z "${action_group_id}" ]] && continue
        print_action_group_receivers "${action_group_id}"
      done <<< "${action_group_ids}"
    else
      echo "action_group_receivers=none"
    fi

    log "core4_test_fire_done fired=true"
    exit 0
  fi

  echo "poll_ts_utc=${now_utc} fired=false"

  if [[ "$(date +%s)" -ge "${DEADLINE_EPOCH}" ]]; then
    log "core4_test_fire_timeout rule=${TEST_RULE_NAME} timeout_sec=${TIMEOUT_SEC}"
    exit 1
  fi

  sleep "${POLL_INTERVAL_SEC}"
done
