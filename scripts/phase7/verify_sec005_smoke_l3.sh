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

usage() {
  cat <<'EOF'
Usage:
  bash scripts/phase7/verify_sec005_smoke_l3.sh --target <dev|prod-secure> --run-id <logical-run-id> [--poll-seconds 20] [--timeout-seconds 600]
EOF
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

PIPELINE_KEYS=(
  "pipeline_a_guardrail"
  "pipeline_silver_materialization"
  "pipeline_b_controls"
  "pipeline_c_analytics"
)
PIPELINE_JOB_NAMES=(
  "data-pipeline-a-${TARGET_SUFFIX}"
  "data-pipeline-silver-${TARGET_SUFFIX}"
  "data-pipeline-b-${TARGET_SUFFIX}"
  "data-pipeline-c-${TARGET_SUFFIX}"
)

START_EPOCH="$(date +%s)"
START_MS="$((START_EPOCH * 1000))"
DEADLINE="$((START_EPOCH + TIMEOUT_SECONDS))"
SAFE_RUN_ID="$(printf '%s' "${RUN_ID}" | tr -c 'A-Za-z0-9._-' '_')"
SUMMARY_JSON="${LOG_DIR}/20260223_sec005_smoke_status_${SAFE_RUN_ID}.json"

log "SEC-005 smoke verifier start target=${TARGET} run_id=${RUN_ID} poll_seconds=${POLL_SECONDS} timeout_seconds=${TIMEOUT_SECONDS}"

JOBS_JSON="$(databricks jobs list -o json)"
declare -A JOB_IDS_BY_KEY=()
declare -A RUN_IDS_BY_KEY=()

for i in "${!PIPELINE_KEYS[@]}"; do
  key="${PIPELINE_KEYS[$i]}"
  name="${PIPELINE_JOB_NAMES[$i]}"
  job_id="$(echo "${JOBS_JSON}" | jq -r --arg name "${name}" '.[] | select(.settings.name == $name) | .job_id' | head -n 1)"
  if [[ -z "${job_id}" || "${job_id}" == "null" ]]; then
    echo "missing job for key=${key} name=${name}" >&2
    exit 1
  fi
  JOB_IDS_BY_KEY["${key}"]="${job_id}"
done

resolve_workspace_run_id() {
  local key="$1"
  local job_id="$2"
  local run_list_json
  run_list_json="$(databricks jobs list-runs --job-id "${job_id}" --limit 25 -o json)"

  mapfile -t candidate_ids < <(echo "${run_list_json}" | jq -r --argjson start_ms "${START_MS}" '.[] | select((.start_time // 0) >= $start_ms) | .run_id')
  if [[ "${#candidate_ids[@]}" -eq 0 ]]; then
    mapfile -t candidate_ids < <(echo "${run_list_json}" | jq -r '.[0:5] | .[] | .run_id')
  fi

  for run_id in "${candidate_ids[@]}"; do
    run_json="$(databricks jobs get-run "${run_id}" -o json)"
    if echo "${run_json}" | jq -e --arg logical_run_id "${RUN_ID}" 'tostring | contains($logical_run_id)' >/dev/null; then
      printf '%s' "${run_id}"
      return 0
    fi
  done

  for run_id in "${candidate_ids[@]}"; do
    run_json="$(databricks jobs get-run "${run_id}" -o json)"
    trigger="$(echo "${run_json}" | jq -r '.trigger // empty')"
    if [[ "${trigger}" != "PERIODIC" ]]; then
      printf '%s' "${run_id}"
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

for key in "${PIPELINE_KEYS[@]}"; do
  run_id="$(resolve_workspace_run_id "${key}" "${JOB_IDS_BY_KEY[${key}]}")"
  RUN_IDS_BY_KEY["${key}"]="${run_id}"
  log "resolved_run_id pipeline=${key} job_id=${JOB_IDS_BY_KEY[${key}]} run_id=${run_id}"
done

FINAL_ROWS="[]"
while true; do
  now_epoch="$(date +%s)"
  rows_json="[]"
  all_finished=1
  all_success=1

  for key in "${PIPELINE_KEYS[@]}"; do
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
  done

  FINAL_ROWS="${rows_json}"

  if [[ "${all_finished}" -eq 1 ]]; then
    break
  fi

  if [[ "${now_epoch}" -ge "${DEADLINE}" ]]; then
    log "timeout reached before all runs completed"
    all_success=0
    break
  fi

  sleep "${POLL_SECONDS}"
done

jq -n \
  --arg ts_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg target "${TARGET}" \
  --arg logical_run_id "${RUN_ID}" \
  --argjson poll_seconds "${POLL_SECONDS}" \
  --argjson timeout_seconds "${TIMEOUT_SECONDS}" \
  --argjson results "${FINAL_ROWS}" \
  '{
    ts_utc: $ts_utc,
    target: $target,
    logical_run_id: $logical_run_id,
    poll_seconds: $poll_seconds,
    timeout_seconds: $timeout_seconds,
    results: $results
  }' > "${SUMMARY_JSON}"

log "summary_written path=${SUMMARY_JSON}"
cat "${SUMMARY_JSON}"

if jq -e 'all(.results[]; .life_cycle_state == "TERMINATED" and .result_state == "SUCCESS")' "${SUMMARY_JSON}" >/dev/null; then
  exit 0
fi

exit 1
