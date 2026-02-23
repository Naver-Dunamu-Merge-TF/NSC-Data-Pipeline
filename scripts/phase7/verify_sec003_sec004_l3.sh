#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

DATE_TAG="$(date -u +%Y%m%d)"
TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RAW_LOG_FILE="${LOG_DIR}/${DATE_TAG}_sec003_sec004_l3_serverless.log"
SEC003_EVIDENCE_FILE="${LOG_DIR}/${DATE_TAG}_sec003_uc_external_location_serverless.md"
SEC004_EVIDENCE_FILE="${LOG_DIR}/${DATE_TAG}_sec004_kv_scope_rotation_serverless.md"
ESCALATION_FILE="${LOG_DIR}/${DATE_TAG}_sec003_sec004_l3_escalation.md"

POLL_SECONDS=20
TIMEOUT_SECONDS=600

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${RAW_LOG_FILE}" >&2
}

record_escalation() {
  local gate="$1"
  local detail="$2"
  cat > "${ESCALATION_FILE}" <<EOF
# SEC-003/SEC-004 L3 Escalation

- date_utc: ${TS_UTC}
- gate: ${gate}
- detail: ${detail}
- action: stop verification and escalate to Infra + Platform
- raw_log: ${RAW_LOG_FILE}
EOF
  log "escalation recorded: ${ESCALATION_FILE}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing required command: ${cmd}" >&2
    exit 1
  fi
}

build_payload() {
  local run_id="$1"
  jq -nc \
    --arg run_id "${run_id}" \
    --arg catalog "${CATALOG_NAME}" \
    --arg external_location "${EXTERNAL_LOCATION_NAME}" \
    --arg base_path "${BASE_PATH}" \
    --arg secret_scope "${SECRET_SCOPE}" \
    --arg secret_key "${SECRET_KEY}" \
    '{
      job_parameters: {
        run_id: $run_id,
        catalog: $catalog,
        external_location: $external_location,
        base_path: $base_path,
        secret_scope: $secret_scope,
        secret_key: $secret_key
      }
    }'
}

wait_for_run() {
  local run_id="$1"
  local deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))

  while true; do
    local run_json
    run_json="$(databricks jobs get-run "${run_id}" --output json)"
    local life_cycle_state
    local result_state
    local state_message
    life_cycle_state="$(echo "${run_json}" | jq -r '.state.life_cycle_state // ""')"
    result_state="$(echo "${run_json}" | jq -r '.state.result_state // ""')"
    state_message="$(echo "${run_json}" | jq -r '.state.state_message // ""')"

    log "poll run_id=${run_id} state=${life_cycle_state}/${result_state} msg=${state_message}"

    case "${life_cycle_state}" in
      TERMINATED|SKIPPED|INTERNAL_ERROR)
        if [[ "${life_cycle_state}" == "TERMINATED" && "${result_state}" == "SUCCESS" ]]; then
          return 0
        fi
        echo "${run_json}" > "${LOG_DIR}/${DATE_TAG}_sec003_sec004_run_${run_id}_failure.json"
        return 1
        ;;
      *) ;;
    esac

    if [[ "$(date +%s)" -ge "${deadline}" ]]; then
      echo "${run_json}" > "${LOG_DIR}/${DATE_TAG}_sec003_sec004_run_${run_id}_timeout.json"
      return 1
    fi

    sleep "${POLL_SECONDS}"
  done
}

extract_sec004_hash() {
  local parent_run_id="$1"
  local task_run_id
  task_run_id="$(databricks jobs get-run "${parent_run_id}" --output json | jq -r '.tasks[] | select(.task_key == "sec004_probe") | .run_id' | head -n 1)"

  if [[ -z "${task_run_id}" || "${task_run_id}" == "null" ]]; then
    echo "unable to find sec004_probe task run id (parent_run_id=${parent_run_id})" >&2
    return 1
  fi

  local output_json
  output_json="$(databricks jobs get-run-output "${task_run_id}" --output json || true)"
  echo "${output_json}" > "${LOG_DIR}/${DATE_TAG}_sec004_task_output_${task_run_id}.json"

  local secret_sha
  secret_sha="$(echo "${output_json}" | tr -d '\n' | sed -n 's/.*"secret_sha256":"\([0-9a-f]\{64\}\)".*/\1/p' | head -n 1)"

  if [[ -z "${secret_sha}" ]]; then
    echo "unable to parse secret_sha256 from sec004 task output (task_run_id=${task_run_id})" >&2
    return 1
  fi

  printf '%s' "${secret_sha}"
}

run_window_once() {
  local logical_run_id="$1"
  local payload
  payload="$(build_payload "${logical_run_id}")"

  local response
  response="$(databricks jobs run-now "${JOB_ID}" --no-wait --json "${payload}" --output json)"
  local run_id
  run_id="$(echo "${response}" | jq -r '.run_id // empty')"

  if [[ -z "${run_id}" ]]; then
    echo "failed to parse run_id from jobs run-now response" >&2
    return 1
  fi

  log "triggered ${JOB_NAME}: workspace_run_id=${run_id}, logical_run_id=${logical_run_id}"
  wait_for_run "${run_id}"

  local hash
  hash="$(extract_sec004_hash "${run_id}")"
  log "sec004 hash captured for run_id=${run_id}"

  printf '%s %s\n' "${run_id}" "${hash}"
}

run_with_retry() {
  local gate="$1"
  local logical_run_id_base="$2"
  local attempt=1
  local result=""

  while [[ "${attempt}" -le "${RETRY_MAX}" ]]; do
    log "gate=${gate} attempt=${attempt}/${RETRY_MAX}"
    if result="$(run_window_once "${logical_run_id_base}_a${attempt}")"; then
      log "gate=${gate} attempt=${attempt} success"
      printf '%s %s\n' "${result}" "${attempt}"
      return 0
    fi
    log "gate=${gate} attempt=${attempt} failed"
    attempt=$((attempt + 1))
  done

  record_escalation "${gate}" "failed after ${RETRY_MAX} attempts"
  return 1
}

rotate_secret_version() {
  local new_value="$1"
  az keyvault secret set \
    --vault-name "${KEYVAULT_NAME}" \
    --name "${KEYVAULT_SECRET_NAME}" \
    --value "${new_value}" \
    --output none
  log "key vault secret rotated: vault=${KEYVAULT_NAME}, secret=${KEYVAULT_SECRET_NAME}"
}

require_cmd databricks
require_cmd jq

TARGET="${TARGET:-dev}"
JOB_NAME="${JOB_NAME:-data-pipeline-sec-binding-${TARGET}}"
RUN_ID_PREFIX="${RUN_ID_PREFIX:-sec003_sec004_l3_$(date -u +%Y%m%dT%H%M%SZ)}"
CATALOG_NAME="${CATALOG_NAME:-nsc_dbw_dev_7405610275478542}"
EXTERNAL_LOCATION_NAME="${EXTERNAL_LOCATION_NAME:-team4_adls_test}"
BASE_PATH="${BASE_PATH:-abfss://2dt-final-team4-adls-test@nscstdevw4mlu8.dfs.core.windows.net}"
SECRET_SCOPE="${SECRET_SCOPE:-ledger-analytics-dev}"
SECRET_KEY="${SECRET_KEY:-salt_user_key}"
ROTATE_SECRET="${ROTATE_SECRET:-1}"
RETRY_MAX="${RETRY_MAX:-2}"
KEYVAULT_NAME="${KEYVAULT_NAME:-}"
KEYVAULT_SECRET_NAME="${KEYVAULT_SECRET_NAME:-${SECRET_KEY}}"

if ! [[ "${RETRY_MAX}" =~ ^[1-9][0-9]*$ ]]; then
  echo "RETRY_MAX must be a positive integer: ${RETRY_MAX}" >&2
  exit 1
fi

JOB_ID="$(databricks jobs list --output json | jq -r --arg name "${JOB_NAME}" '.[] | select(.settings.name == $name) | .job_id' | head -n 1)"
if [[ -z "${JOB_ID}" || "${JOB_ID}" == "null" ]]; then
  echo "unable to resolve job_id for ${JOB_NAME}" >&2
  exit 1
fi

log "starting L3 verification: job_name=${JOB_NAME}, job_id=${JOB_ID}"

PRE_RESULT="$(run_with_retry "pre_window" "${RUN_ID_PREFIX}_pre")"
PRE_RUN_ID="$(echo "${PRE_RESULT}" | awk '{print $1}')"
PRE_HASH="$(echo "${PRE_RESULT}" | awk '{print $2}')"
PRE_ATTEMPTS_USED="$(echo "${PRE_RESULT}" | awk '{print $3}')"

POST_RUN_ID=""
POST_HASH=""
POST_ATTEMPTS_USED=""
ROTATION_ATTEMPTS_USED=0
ROTATION_STATUS="skipped"

if [[ "${ROTATE_SECRET}" == "1" ]]; then
  require_cmd az
  if [[ -z "${KEYVAULT_NAME}" ]]; then
    echo "KEYVAULT_NAME is required when ROTATE_SECRET=1" >&2
    exit 1
  fi

  rotation_gate_ok=0
  for rotation_attempt in $(seq 1 "${RETRY_MAX}"); do
    NEW_SECRET_VALUE="${ROTATE_SECRET_VALUE:-sec-rot-$(date -u +%Y%m%dT%H%M%SZ)-${rotation_attempt}-$RANDOM}"
    rotate_secret_version "${NEW_SECRET_VALUE}"
    sleep 5

    POST_RESULT="$(run_with_retry "post_window_rotation_${rotation_attempt}" "${RUN_ID_PREFIX}_post_r${rotation_attempt}")"
    POST_RUN_ID="$(echo "${POST_RESULT}" | awk '{print $1}')"
    POST_HASH="$(echo "${POST_RESULT}" | awk '{print $2}')"
    POST_ATTEMPTS_USED="$(echo "${POST_RESULT}" | awk '{print $3}')"
    ROTATION_ATTEMPTS_USED="${rotation_attempt}"

    if [[ "${PRE_HASH}" != "${POST_HASH}" ]]; then
      rotation_gate_ok=1
      ROTATION_STATUS="success"
      break
    fi

    log "rotation hash compare mismatch attempt=${rotation_attempt}/${RETRY_MAX}: pre == post"
  done

  if [[ "${rotation_gate_ok}" -ne 1 ]]; then
    record_escalation "rotation_hash_compare" "rotation hash validation failed after ${RETRY_MAX} attempts"
    echo "rotation hash validation failed: pre == post after retries" >&2
    exit 1
  fi
fi

cat > "${SEC003_EVIDENCE_FILE}" <<EOF
# SEC-003 Serverless Verification

- date_utc: ${TS_UTC}
- target: ${TARGET}
- job_name: ${JOB_NAME}
- job_id: ${JOB_ID}
- run_id_pre: ${PRE_RUN_ID}
- catalog: ${CATALOG_NAME}
- external_location: ${EXTERNAL_LOCATION_NAME}
- base_path: ${BASE_PATH}
- poll_interval_seconds: ${POLL_SECONDS}
- timeout_seconds: ${TIMEOUT_SECONDS}
- retry_max: ${RETRY_MAX}
- pre_attempts_used: ${PRE_ATTEMPTS_USED}
- raw_log: ${RAW_LOG_FILE}
EOF

cat > "${SEC004_EVIDENCE_FILE}" <<EOF
# SEC-004 KV Scope Rotation Verification

- date_utc: ${TS_UTC}
- target: ${TARGET}
- job_name: ${JOB_NAME}
- secret_scope: ${SECRET_SCOPE}
- secret_key: ${SECRET_KEY}
- run_id_pre: ${PRE_RUN_ID}
- secret_sha256_pre: ${PRE_HASH}
- run_id_post: ${POST_RUN_ID}
- secret_sha256_post: ${POST_HASH}
- rotation_status: ${ROTATION_STATUS}
- retry_max: ${RETRY_MAX}
- post_attempts_used: ${POST_ATTEMPTS_USED}
- rotation_attempts_used: ${ROTATION_ATTEMPTS_USED}
- keyvault_name: ${KEYVAULT_NAME}
- keyvault_secret_name: ${KEYVAULT_SECRET_NAME}
- raw_log: ${RAW_LOG_FILE}
EOF

log "L3 verification completed"
log "SEC-003 evidence: ${SEC003_EVIDENCE_FILE}"
log "SEC-004 evidence: ${SEC004_EVIDENCE_FILE}"
