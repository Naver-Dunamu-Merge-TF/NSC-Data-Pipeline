#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

TARGET="dev"
ACTION=""
OUTPUT_JSON="${LOG_DIR}/20260223_all_pipeline_serverless_schedule_states.json"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/phase7/toggle_core_pipeline_schedules.sh --target <dev|prod-secure> (--pause|--resume)

Options:
  --target <dev|prod-secure>
  --pause
  --resume
USAGE
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
cur = cfg
for part in key.split("."):
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
    --pause)
      ACTION="pause"
      shift
      ;;
    --resume)
      ACTION="resume"
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

if [[ -z "${ACTION}" ]]; then
  echo "exactly one of --pause or --resume is required" >&2
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

if [[ "${ACTION}" == "pause" ]]; then
  DESIRED_STATUS="PAUSED"
else
  DESIRED_STATUS="UNPAUSED"
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

JOBS_JSON="$(databricks jobs list -o json)"
RESULTS="[]"

for i in "${!PIPELINE_KEYS[@]}"; do
  key="${PIPELINE_KEYS[$i]}"
  name="${PIPELINE_JOB_NAMES[$i]}"
  job_id="$(echo "${JOBS_JSON}" | jq -r --arg name "${name}" '.[] | select(.settings.name == $name) | .job_id' | head -n 1)"

  if [[ -z "${job_id}" || "${job_id}" == "null" ]]; then
    RESULTS="$(echo "${RESULTS}" | jq --arg key "${key}" --arg name "${name}" --arg desired "${DESIRED_STATUS}" '. + [{pipeline:$key, job_name:$name, desired_pause_status:$desired, status:"FAIL", reason:"job_not_found"}]')"
    continue
  fi

  job_json="$(databricks jobs get "${job_id}" -o json)"
  current_status="$(echo "${job_json}" | jq -r '.settings.schedule.pause_status // "UNPAUSED"')"

  payload_file="$(mktemp)"
  echo "${job_json}" | jq \
    --arg status "${DESIRED_STATUS}" \
    '{job_id: .job_id, new_settings: (.settings | .schedule.pause_status = $status)}' \
    > "${payload_file}"

  databricks jobs reset --json @"${payload_file}" >/dev/null
  rm -f "${payload_file}"

  final_status="$(databricks jobs get "${job_id}" -o json | jq -r '.settings.schedule.pause_status // "UNPAUSED"')"
  status="PASS"
  reason=""

  if [[ "${final_status}" != "${DESIRED_STATUS}" ]]; then
    status="FAIL"
    reason="schedule_pause_status_mismatch"
  fi

  RESULTS="$(echo "${RESULTS}" | jq \
    --arg key "${key}" \
    --arg name "${name}" \
    --arg job_id "${job_id}" \
    --arg previous "${current_status}" \
    --arg final "${final_status}" \
    --arg desired "${DESIRED_STATUS}" \
    --arg status "${status}" \
    --arg reason "${reason}" \
    '. + [{
      pipeline: $key,
      job_name: $name,
      job_id: ($job_id|tonumber),
      previous_pause_status: $previous,
      desired_pause_status: $desired,
      final_pause_status: $final,
      status: $status,
      reason: $reason
    }]')"
done

jq -n \
  --arg ts_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg target "${TARGET}" \
  --arg action "${ACTION}" \
  --arg desired_pause_status "${DESIRED_STATUS}" \
  --argjson results "${RESULTS}" \
  '{
    ts_utc: $ts_utc,
    target: $target,
    action: $action,
    desired_pause_status: $desired_pause_status,
    results: $results
  }' > "${OUTPUT_JSON}"

cat "${OUTPUT_JSON}"

if jq -e 'all(.results[]; .status == "PASS")' "${OUTPUT_JSON}" >/dev/null; then
  exit 0
fi

exit 1
