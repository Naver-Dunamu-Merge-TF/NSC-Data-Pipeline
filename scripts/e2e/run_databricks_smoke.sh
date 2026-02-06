#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "missing required env: ${name}" >&2
    exit 1
  fi
}

require_env "DATABRICKS_HOST"
require_env "DATABRICKS_TOKEN"
require_env "DATABRICKS_PIPELINE_A_JOB_ID"
require_env "DATABRICKS_PIPELINE_B_JOB_ID"
require_env "DATABRICKS_PIPELINE_C_JOB_ID"

if ! command -v databricks >/dev/null 2>&1; then
  echo "databricks CLI not found in PATH" >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
log_file=".agents/logs/verification/e2e_smoke_${timestamp}.txt"
mkdir -p ".agents/logs/verification"

trigger_job() {
  local pipeline="$1"
  local job_id="$2"
  local run_id="e2e_${pipeline}_${timestamp}"
  local payload
  payload="$(cat <<JSON
{"job_parameters":{"run_mode":"incremental","run_id":"${run_id}"}}
JSON
)"

  echo "[${pipeline}] triggering job_id=${job_id} run_id=${run_id}" | tee -a "${log_file}"
  databricks jobs run-now --job-id "${job_id}" --json "${payload}" | tee -a "${log_file}"
}

trigger_job "pipeline_a" "${DATABRICKS_PIPELINE_A_JOB_ID}"
trigger_job "pipeline_b" "${DATABRICKS_PIPELINE_B_JOB_ID}"
trigger_job "pipeline_c" "${DATABRICKS_PIPELINE_C_JOB_ID}"

echo "Triggered all E2E smoke jobs. See ${log_file}" | tee -a "${log_file}"
