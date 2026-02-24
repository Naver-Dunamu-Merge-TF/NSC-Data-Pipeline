#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

TARGET="dev"
DATE_KST=""
RUN_ID=""
RUN_AS_PRINCIPAL=""
CATALOG_NAME=""
POLL_SECONDS=20
TIMEOUT_SECONDS=600
OUTPUT_JSON=""

SCHEDULE_PAUSED=0
STAGE_A_SILVER_STATUS="NOT_RUN"
STAGE_B_C_STATUS="NOT_RUN"
FAILURE_REASON=""

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/phase7/run_sec005_smoke_recovery.sh --target <dev|prod-secure> --date-kst <YYYY-MM-DD> --run-id <logical-run-id> --run-as-principal <sp-app-id> [--catalog <catalog-name>] [--poll-seconds 20] [--timeout-seconds 600] [--output-json <path>]

Options:
  --target <dev|prod-secure>
  --date-kst <YYYY-MM-DD>
  --run-id <logical-run-id>
  --run-as-principal <sp-app-id>
  --catalog <catalog-name>
  --poll-seconds <seconds>
  --timeout-seconds <seconds>
  --output-json <path>
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

write_summary() {
  local summary_path="$1"
  local preflight_json="$2"
  local stage1_json="$3"
  local stage2_json="$4"

  jq -n \
    --arg ts_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg target "${TARGET}" \
    --arg date_kst "${DATE_KST}" \
    --arg logical_run_id "${RUN_ID}" \
    --arg run_as_principal "${RUN_AS_PRINCIPAL}" \
    --arg catalog "${CATALOG_NAME}" \
    --arg stage_a_silver_status "${STAGE_A_SILVER_STATUS}" \
    --arg stage_b_c_status "${STAGE_B_C_STATUS}" \
    --arg failure_reason "${FAILURE_REASON}" \
    --arg preflight_json "${preflight_json}" \
    --arg stage1_json "${stage1_json}" \
    --arg stage2_json "${stage2_json}" \
    --argjson poll_seconds "${POLL_SECONDS}" \
    --argjson timeout_seconds "${TIMEOUT_SECONDS}" \
    '{
      ts_utc: $ts_utc,
      target: $target,
      date_kst: $date_kst,
      logical_run_id: $logical_run_id,
      run_as_principal: $run_as_principal,
      catalog: $catalog,
      poll_seconds: $poll_seconds,
      timeout_seconds: $timeout_seconds,
      stage_a_silver_status: $stage_a_silver_status,
      stage_b_c_status: $stage_b_c_status,
      failure_reason: $failure_reason,
      preflight_json: $preflight_json,
      stage1_json: $stage1_json,
      stage2_json: $stage2_json
    }' > "${summary_path}"

  log "smoke_recovery_summary path=${summary_path}"
  cat "${summary_path}"
}

cleanup() {
  if [[ "${SCHEDULE_PAUSED}" -eq 1 ]]; then
    log "resuming core pipeline schedules"
    bash "${ROOT_DIR}/scripts/phase7/toggle_core_pipeline_schedules.sh" --target "${TARGET}" --resume || true
    SCHEDULE_PAUSED=0
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --date-kst)
      DATE_KST="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --run-as-principal)
      RUN_AS_PRINCIPAL="${2:-}"
      shift 2
      ;;
    --catalog)
      CATALOG_NAME="${2:-}"
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

if [[ -z "${DATE_KST}" ]]; then
  echo "--date-kst is required" >&2
  exit 1
fi

if [[ -z "${RUN_ID}" ]]; then
  echo "--run-id is required" >&2
  exit 1
fi

if [[ -z "${RUN_AS_PRINCIPAL}" ]]; then
  echo "--run-as-principal is required" >&2
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

SAFE_RUN_ID="$(printf '%s' "${RUN_ID}" | tr -c 'A-Za-z0-9._-' '_')"
if [[ -z "${OUTPUT_JSON}" ]]; then
  OUTPUT_JSON="${LOG_DIR}/20260224_d046_smoke_recovery_summary_${SAFE_RUN_ID}.json"
fi
PRECHECK_JSON="${LOG_DIR}/20260224_d046_smoke_preflight_${SAFE_RUN_ID}.json"
STAGE1_JSON="${LOG_DIR}/20260224_d046_smoke_stage_as_${SAFE_RUN_ID}.json"
STAGE2_JSON="${LOG_DIR}/20260224_d046_smoke_stage_bc_${SAFE_RUN_ID}.json"

trap cleanup EXIT

log "stage0 pause schedules"
bash "${ROOT_DIR}/scripts/phase7/toggle_core_pipeline_schedules.sh" --target "${TARGET}" --pause
SCHEDULE_PAUSED=1

log "stage1 rule+acl preflight"
bash "${ROOT_DIR}/scripts/phase7/verify_sec005_rule_preflight.sh" \
  --target "${TARGET}" \
  --catalog "${CATALOG_NAME}" \
  --run-as-principal "${RUN_AS_PRINCIPAL}" \
  --output-json "${PRECHECK_JSON}"

log "stage2 sync dim_rule_scd2"
databricks bundle run sync_dim_rule_scd2 -t "${TARGET}" \
  --params "seed_path=mock_data/fixtures/dim_rule_scd2.json,table_name=gold.dim_rule_scd2"

log "stage3 submit A/Silver"
databricks bundle run pipeline_a_guardrail -t "${TARGET}" --no-wait \
  --params "run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}"
databricks bundle run pipeline_silver_materialization -t "${TARGET}" --no-wait \
  --params "run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}"

log "stage4 verify A/Silver"
if bash "${ROOT_DIR}/scripts/phase7/verify_sec005_smoke_l3.sh" \
  --target "${TARGET}" \
  --run-id "${RUN_ID}" \
  --pipelines pipeline_a_guardrail,pipeline_silver_materialization \
  --fail-fast-deterministic on \
  --poll-seconds "${POLL_SECONDS}" \
  --timeout-seconds "${TIMEOUT_SECONDS}" \
  --output-json "${STAGE1_JSON}"; then
  STAGE_A_SILVER_STATUS="PASS"
else
  STAGE_A_SILVER_STATUS="FAIL"
  FAILURE_REASON="stage_a_silver_failed"
  write_summary "${OUTPUT_JSON}" "${PRECHECK_JSON}" "${STAGE1_JSON}" "${STAGE2_JSON}"
  exit 1
fi

log "stage5 submit B/C"
databricks bundle run pipeline_b_controls -t "${TARGET}" --no-wait \
  --params "run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}"
databricks bundle run pipeline_c_analytics -t "${TARGET}" --no-wait \
  --params "run_mode=backfill,date_kst_start=${DATE_KST},date_kst_end=${DATE_KST},run_id=${RUN_ID}"

log "stage6 verify B/C"
if bash "${ROOT_DIR}/scripts/phase7/verify_sec005_smoke_l3.sh" \
  --target "${TARGET}" \
  --run-id "${RUN_ID}" \
  --pipelines pipeline_b_controls,pipeline_c_analytics \
  --fail-fast-deterministic on \
  --poll-seconds "${POLL_SECONDS}" \
  --timeout-seconds "${TIMEOUT_SECONDS}" \
  --output-json "${STAGE2_JSON}"; then
  STAGE_B_C_STATUS="PASS"
else
  STAGE_B_C_STATUS="FAIL"
  FAILURE_REASON="stage_b_c_failed"
  write_summary "${OUTPUT_JSON}" "${PRECHECK_JSON}" "${STAGE1_JSON}" "${STAGE2_JSON}"
  exit 1
fi

write_summary "${OUTPUT_JSON}" "${PRECHECK_JSON}" "${STAGE1_JSON}" "${STAGE2_JSON}"

exit 0
