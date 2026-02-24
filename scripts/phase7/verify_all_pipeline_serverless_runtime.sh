#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

TARGET="dev"
OUTPUT_JSON="${LOG_DIR}/20260223_all_pipeline_serverless_runtime_assertions.json"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/phase7/verify_all_pipeline_serverless_runtime.sh --target <dev|prod-secure> [--output-json <path>]

Options:
  --target <dev|prod-secure>
  --output-json <path>
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

JOBS_JSON="$(databricks jobs list -o json)"
RESULTS="[]"

for i in "${!PIPELINE_KEYS[@]}"; do
  key="${PIPELINE_KEYS[$i]}"
  name="${PIPELINE_JOB_NAMES[$i]}"

  job_id="$(echo "${JOBS_JSON}" | jq -r --arg name "${name}" '.[] | select(.settings.name == $name) | .job_id' | head -n 1)"
  if [[ -z "${job_id}" || "${job_id}" == "null" ]]; then
    RESULTS="$(echo "${RESULTS}" | jq --arg key "${key}" --arg name "${name}" '. + [{pipeline:$key, job_name:$name, status:"FAIL", reason:"job_not_found"}]')"
    continue
  fi

  job_json="$(databricks jobs get "${job_id}" -o json)"
  checks="$(echo "${job_json}" | jq '{
    performance_target_present: ((.settings.performance_target // "") | length > 0),
    has_job_clusters: (.settings | has("job_clusters")),
    has_task_job_cluster_key: any(.settings.tasks[]?; has("job_cluster_key")),
    run_as_present: (((.settings.run_as.service_principal_name // "") | length > 0) or ((.settings.run_as.user_name // "") | length > 0)),
    performance_target_value: (.settings.performance_target // "")
  }')"

  status="PASS"
  reason=""

  if [[ "$(echo "${checks}" | jq -r '.performance_target_present')" != "true" ]]; then
    status="FAIL"
    reason="missing_performance_target"
  elif [[ "$(echo "${checks}" | jq -r '.has_job_clusters')" == "true" ]]; then
    status="FAIL"
    reason="job_clusters_present"
  elif [[ "$(echo "${checks}" | jq -r '.has_task_job_cluster_key')" == "true" ]]; then
    status="FAIL"
    reason="task_job_cluster_key_present"
  elif [[ "$(echo "${checks}" | jq -r '.run_as_present')" != "true" ]]; then
    status="FAIL"
    reason="run_as_missing"
  fi

  RESULTS="$(echo "${RESULTS}" | jq \
    --arg key "${key}" \
    --arg name "${name}" \
    --arg job_id "${job_id}" \
    --arg status "${status}" \
    --arg reason "${reason}" \
    --argjson checks "${checks}" \
    '. + [{pipeline:$key, job_name:$name, job_id:($job_id|tonumber), status:$status, reason:$reason, checks:$checks}]')"
done

mkdir -p "$(dirname "${OUTPUT_JSON}")"
echo "${RESULTS}" > "${OUTPUT_JSON}"
cat "${OUTPUT_JSON}"

if jq -e 'all(.[]; .status == "PASS")' "${OUTPUT_JSON}" >/dev/null; then
  exit 0
fi

exit 1
