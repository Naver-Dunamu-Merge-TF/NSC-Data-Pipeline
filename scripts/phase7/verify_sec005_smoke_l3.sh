#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

POLL_SECONDS_DEFAULT=20
TIMEOUT_SECONDS_DEFAULT=600

TARGET="dev"
RUN_ID=""
POLL_SECONDS="${POLL_SECONDS_DEFAULT}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS_DEFAULT}"
PIPELINES=""
FAIL_FAST_DETERMINISTIC="off"
OUTPUT_JSON=""

usage() {
  cat <<'EOF_USAGE'
Usage:
  bash scripts/phase7/verify_sec005_smoke_l3.sh --target <dev|prod-secure> --run-id <logical-run-id> [--pipelines <comma-separated-keys>] [--fail-fast-deterministic <on|off>] [--poll-seconds 20] [--timeout-seconds 600] [--output-json <path>]
EOF_USAGE
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

normalize_fail_fast_flag() {
  local raw="$1"
  case "${raw,,}" in
    on|true|1)
      echo "on"
      ;;
    off|false|0|"")
      echo "off"
      ;;
    *)
      return 1
      ;;
  esac
}

ALL_PIPELINE_KEYS=(
  "pipeline_a_guardrail"
  "pipeline_silver_materialization"
  "pipeline_b_controls"
  "pipeline_c_analytics"
)

is_valid_pipeline_key() {
  local key="$1"
  local allowed
  for allowed in "${ALL_PIPELINE_KEYS[@]}"; do
    if [[ "${key}" == "${allowed}" ]]; then
      return 0
    fi
  done
  return 1
}

resolve_selected_pipeline_keys() {
  local pipelines_arg="$1"
  local -a selected=()
  declare -A seen=()

  if [[ -z "${pipelines_arg}" ]]; then
    selected=("${ALL_PIPELINE_KEYS[@]}")
  else
    local token
    IFS=',' read -ra raw_tokens <<< "${pipelines_arg}"
    for token in "${raw_tokens[@]}"; do
      token="$(echo "${token}" | xargs)"
      if [[ -z "${token}" ]]; then
        continue
      fi
      if ! is_valid_pipeline_key "${token}"; then
        echo "invalid pipeline key in --pipelines: ${token}" >&2
        return 1
      fi
      if [[ -z "${seen[${token}]:-}" ]]; then
        seen["${token}"]=1
        selected+=("${token}")
      fi
    done
  fi

  if [[ "${#selected[@]}" -eq 0 ]]; then
    echo "no pipeline keys resolved" >&2
    return 1
  fi

  printf '%s\n' "${selected[@]}"
}

resolve_workspace_run_id() {
  local key="$1"
  local job_id="$2"
  local run_list_json

  run_list_json="$(databricks jobs list-runs --job-id "${job_id}" --limit 25 -o json)"

  mapfile -t candidate_ids < <(echo "${run_list_json}" | jq -r --argjson start_ms "${START_MS}" '.[] | select((.start_time // 0) >= $start_ms) | .run_id')
  if [[ "${#candidate_ids[@]}" -eq 0 ]]; then
    mapfile -t candidate_ids < <(echo "${run_list_json}" | jq -r '.[0:5] | .[] | .run_id')
  fi

  local workspace_run_id
  local run_json
  local trigger

  for workspace_run_id in "${candidate_ids[@]}"; do
    run_json="$(databricks jobs get-run "${workspace_run_id}" -o json)"
    if echo "${run_json}" | jq -e --arg logical_run_id "${RUN_ID}" 'tostring | contains($logical_run_id)' >/dev/null; then
      printf '%s' "${workspace_run_id}"
      return 0
    fi
  done

  for workspace_run_id in "${candidate_ids[@]}"; do
    run_json="$(databricks jobs get-run "${workspace_run_id}" -o json)"
    trigger="$(echo "${run_json}" | jq -r '.trigger // empty')"
    if [[ "${trigger}" != "PERIODIC" ]]; then
      printf '%s' "${workspace_run_id}"
      return 0
    fi
  done

  if [[ "${#candidate_ids[@]}" -gt 0 ]]; then
    printf '%s' "${candidate_ids[0]}"
    return 0
  fi

  echo "unable to resolve run id for ${key}" >&2
  return 1
}

detect_deterministic_failure_and_retry_pending() {
  local pipeline_key="$1"
  local parent_run_id="$2"
  local parent_run_json="$3"

  local -A deterministic_failed_by_task=()
  local -A pending_waiting_by_task=()
  local task_errors="[]"

  local task_entry
  while IFS= read -r task_entry; do
    local task_key
    local task_run_id
    local task_run_json
    local output_json
    local output_payload_text
    local life_cycle_state
    local result_state
    local state_message
    local deterministic_signature=""

    task_key="$(echo "${task_entry}" | jq -r '.task_key // ""')"
    task_run_id="$(echo "${task_entry}" | jq -r '.run_id // empty')"

    if [[ -z "${task_key}" || -z "${task_run_id}" || "${task_run_id}" == "null" ]]; then
      continue
    fi

    task_run_json="$(databricks jobs get-run "${task_run_id}" -o json)"
    output_json="$(databricks jobs get-run-output "${task_run_id}" -o json 2>/dev/null || true)"

    life_cycle_state="$(echo "${task_run_json}" | jq -r '.state.life_cycle_state // ""')"
    result_state="$(echo "${task_run_json}" | jq -r '.state.result_state // ""')"
    state_message="$(echo "${task_run_json}" | jq -r '.state.state_message // ""')"

    output_payload_text="$(printf '%s\n%s' "${state_message}" "${output_json}")"

    if [[ "${output_payload_text}" == *"Failed to load runtime rules from table"* ]]; then
      deterministic_signature="Failed to load runtime rules from table"
    elif [[ "${output_payload_text}" == *"UpstreamReadinessError"* ]]; then
      deterministic_signature="UpstreamReadinessError"
    fi

    if [[ -n "${deterministic_signature}" ]]; then
      if [[ "${life_cycle_state}" == "TERMINATED" || "${life_cycle_state}" == "SKIPPED" || "${life_cycle_state}" == "INTERNAL_ERROR" ]]; then
        if [[ "${result_state}" != "SUCCESS" ]]; then
          deterministic_failed_by_task["${task_key}"]=1
          task_errors="$(echo "${task_errors}" | jq \
            --arg pipeline "${pipeline_key}" \
            --arg pipeline_run_id "${parent_run_id}" \
            --arg task_key "${task_key}" \
            --arg task_run_id "${task_run_id}" \
            --arg life_cycle_state "${life_cycle_state}" \
            --arg result_state "${result_state}" \
            --arg signature "${deterministic_signature}" \
            '. + [{
              pipeline: $pipeline,
              pipeline_run_id: $pipeline_run_id,
              task_key: $task_key,
              task_run_id: $task_run_id,
              life_cycle_state: $life_cycle_state,
              result_state: $result_state,
              signature: $signature
            }]')"
        fi
      fi
    fi

    if [[ "${life_cycle_state}" == "PENDING" && "${state_message}" == *"Waiting for cluster"* ]]; then
      pending_waiting_by_task["${task_key}"]=1
    fi
  done < <(echo "${parent_run_json}" | jq -c '.tasks[]? | {task_key:(.task_key // ""), run_id:(.run_id // empty)}')

  local triggered=0
  local task_key
  for task_key in "${!deterministic_failed_by_task[@]}"; do
    if [[ "${pending_waiting_by_task[${task_key}]:-0}" == "1" ]]; then
      triggered=1
      task_errors="$(echo "${task_errors}" | jq \
        --arg pipeline "${pipeline_key}" \
        --arg pipeline_run_id "${parent_run_id}" \
        --arg task_key "${task_key}" \
        '. + [{
          pipeline: $pipeline,
          pipeline_run_id: $pipeline_run_id,
          task_key: $task_key,
          reason: "deterministic_failure_with_retry_pending_waiting_for_cluster"
        }]')"
    fi
  done

  jq -n \
    --argjson triggered "$(bool_json "${triggered}")" \
    --argjson errors "${task_errors}" \
    '{triggered: $triggered, errors: $errors}'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --poll-seconds)
      POLL_SECONDS="${2:-}"
      shift 2
      ;;
    --timeout-seconds)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --pipelines)
      PIPELINES="${2:-}"
      shift 2
      ;;
    --fail-fast-deterministic)
      FAIL_FAST_DETERMINISTIC="${2:-}"
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

if [[ -z "${RUN_ID}" ]]; then
  echo "--run-id is required" >&2
  exit 1
fi

if ! [[ "${POLL_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${POLL_SECONDS}" -le 0 ]]; then
  echo "--poll-seconds must be positive integer" >&2
  exit 1
fi

if ! [[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${TIMEOUT_SECONDS}" -le 0 ]]; then
  echo "--timeout-seconds must be positive integer" >&2
  exit 1
fi

if ! FAIL_FAST_DETERMINISTIC="$(normalize_fail_fast_flag "${FAIL_FAST_DETERMINISTIC}")"; then
  echo "--fail-fast-deterministic must be one of: on, off" >&2
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
else
  TARGET_SUFFIX="prod"
fi

mapfile -t SELECTED_PIPELINE_KEYS < <(resolve_selected_pipeline_keys "${PIPELINES}")
SELECTED_PIPELINES_JSON="$(printf '%s\n' "${SELECTED_PIPELINE_KEYS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"

declare -A PIPELINE_JOB_NAMES=()
PIPELINE_JOB_NAMES["pipeline_a_guardrail"]="data-pipeline-a-${TARGET_SUFFIX}"
PIPELINE_JOB_NAMES["pipeline_silver_materialization"]="data-pipeline-silver-${TARGET_SUFFIX}"
PIPELINE_JOB_NAMES["pipeline_b_controls"]="data-pipeline-b-${TARGET_SUFFIX}"
PIPELINE_JOB_NAMES["pipeline_c_analytics"]="data-pipeline-c-${TARGET_SUFFIX}"

START_EPOCH="$(date +%s)"
START_MS="$((START_EPOCH * 1000))"
DEADLINE="$((START_EPOCH + TIMEOUT_SECONDS))"
SAFE_RUN_ID="$(printf '%s' "${RUN_ID}" | tr -c 'A-Za-z0-9._-' '_')"
if [[ -n "${OUTPUT_JSON}" ]]; then
  SUMMARY_JSON="${OUTPUT_JSON}"
else
  SUMMARY_JSON="${LOG_DIR}/20260223_sec005_smoke_status_${SAFE_RUN_ID}.json"
fi
mkdir -p "$(dirname "${SUMMARY_JSON}")"

log "SEC-005 smoke verifier start target=${TARGET} run_id=${RUN_ID} poll_seconds=${POLL_SECONDS} timeout_seconds=${TIMEOUT_SECONDS} pipelines=$(IFS=','; echo "${SELECTED_PIPELINE_KEYS[*]}") fail_fast_deterministic=${FAIL_FAST_DETERMINISTIC}"

JOBS_JSON="$(databricks jobs list -o json)"
declare -A JOB_IDS_BY_KEY=()
declare -A RUN_IDS_BY_KEY=()

for key in "${SELECTED_PIPELINE_KEYS[@]}"; do
  name="${PIPELINE_JOB_NAMES[${key}]}"
  job_id="$(echo "${JOBS_JSON}" | jq -r --arg name "${name}" '.[] | select(.settings.name == $name) | .job_id' | head -n 1)"
  if [[ -z "${job_id}" || "${job_id}" == "null" ]]; then
    echo "missing job for key=${key} name=${name}" >&2
    exit 1
  fi
  JOB_IDS_BY_KEY["${key}"]="${job_id}"
done

for key in "${SELECTED_PIPELINE_KEYS[@]}"; do
  run_id="$(resolve_workspace_run_id "${key}" "${JOB_IDS_BY_KEY[${key}]}")"
  RUN_IDS_BY_KEY["${key}"]="${run_id}"
  log "resolved_run_id pipeline=${key} job_id=${JOB_IDS_BY_KEY[${key}]} run_id=${run_id}"
done

FINAL_ROWS="[]"
CANCELLED_RUN_IDS="[]"
DETECTED_ERRORS="[]"
FAILURE_REASON=""
FAIL_FAST_TRIGGERED=0

while true; do
  now_epoch="$(date +%s)"
  rows_json="[]"
  all_finished=1
  all_success=1
  break_polling=0

  for key in "${SELECTED_PIPELINE_KEYS[@]}"; do
    run_id="${RUN_IDS_BY_KEY[${key}]}"
    run_json="$(databricks jobs get-run "${run_id}" -o json)"
    life_cycle_state="$(echo "${run_json}" | jq -r '.state.life_cycle_state // ""')"
    result_state="$(echo "${run_json}" | jq -r '.state.result_state // ""')"
    state_message="$(echo "${run_json}" | jq -r '.state.state_message // ""')"

    log "poll pipeline=${key} run_id=${run_id} state=${life_cycle_state}/${result_state}"

    rows_json="$(echo "${rows_json}" | jq \
      --arg pipeline "${key}" \
      --arg run_id "${run_id}" \
      --arg life_cycle_state "${life_cycle_state}" \
      --arg result_state "${result_state}" \
      --arg state_message "${state_message}" \
      '. + [{
        pipeline: $pipeline,
        run_id: $run_id,
        life_cycle_state: $life_cycle_state,
        result_state: $result_state,
        state_message: $state_message
      }]')"

    case "${life_cycle_state}" in
      TERMINATED)
        if [[ "${result_state}" != "SUCCESS" ]]; then
          all_success=0
        fi
        ;;
      SKIPPED|INTERNAL_ERROR)
        all_success=0
        ;;
      *)
        all_finished=0
        ;;
    esac

    if [[ "${FAIL_FAST_DETERMINISTIC}" == "on" ]]; then
      detection_json="$(detect_deterministic_failure_and_retry_pending "${key}" "${run_id}" "${run_json}")"
      if [[ "$(echo "${detection_json}" | jq -r '.triggered')" == "true" ]]; then
        FAIL_FAST_TRIGGERED=1
        all_success=0
        break_polling=1
        if [[ -z "${FAILURE_REASON}" ]]; then
          FAILURE_REASON="deterministic_failure_retry_pending_waiting_for_cluster"
        fi

        log "deterministic_failure_retry_pending_detected pipeline=${key} run_id=${run_id}; cancelling run"
        databricks jobs cancel-run "${run_id}" --no-wait >/dev/null || true

        CANCELLED_RUN_IDS="$(echo "${CANCELLED_RUN_IDS}" | jq --arg run_id "${run_id}" '. + [$run_id] | unique')"
        DETECTED_ERRORS="$(jq -n --argjson left "${DETECTED_ERRORS}" --argjson right "$(echo "${detection_json}" | jq '.errors')" '$left + $right')"
        break
      fi
    fi
  done

  FINAL_ROWS="${rows_json}"

  if [[ "${break_polling}" -eq 1 ]]; then
    break
  fi

  if [[ "${all_finished}" -eq 1 ]]; then
    break
  fi

  if [[ "${now_epoch}" -ge "${DEADLINE}" ]]; then
    log "timeout reached before all runs completed"
    all_success=0
    if [[ -z "${FAILURE_REASON}" ]]; then
      FAILURE_REASON="timeout"
    fi
    break
  fi

  sleep "${POLL_SECONDS}"
done

jq -n \
  --arg ts_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg target "${TARGET}" \
  --arg logical_run_id "${RUN_ID}" \
  --arg fail_fast_deterministic "${FAIL_FAST_DETERMINISTIC}" \
  --arg failure_reason "${FAILURE_REASON}" \
  --argjson selected_pipelines "${SELECTED_PIPELINES_JSON}" \
  --argjson poll_seconds "${POLL_SECONDS}" \
  --argjson timeout_seconds "${TIMEOUT_SECONDS}" \
  --argjson fail_fast_triggered "$(bool_json "${FAIL_FAST_TRIGGERED}")" \
  --argjson cancelled_run_ids "${CANCELLED_RUN_IDS}" \
  --argjson detected_errors "${DETECTED_ERRORS}" \
  --argjson results "${FINAL_ROWS}" \
  '{
    ts_utc: $ts_utc,
    target: $target,
    logical_run_id: $logical_run_id,
    selected_pipelines: $selected_pipelines,
    fail_fast_deterministic: $fail_fast_deterministic,
    fail_fast_triggered: $fail_fast_triggered,
    failure_reason: $failure_reason,
    cancelled_run_ids: $cancelled_run_ids,
    detected_errors: $detected_errors,
    poll_seconds: $poll_seconds,
    timeout_seconds: $timeout_seconds,
    results: $results
  }' > "${SUMMARY_JSON}"

log "summary_written path=${SUMMARY_JSON}"
cat "${SUMMARY_JSON}"

if [[ -n "${FAILURE_REASON}" ]]; then
  exit 1
fi

if jq -e 'all(.results[]; .life_cycle_state == "TERMINATED" and .result_state == "SUCCESS")' "${SUMMARY_JSON}" >/dev/null; then
  exit 0
fi

exit 1
