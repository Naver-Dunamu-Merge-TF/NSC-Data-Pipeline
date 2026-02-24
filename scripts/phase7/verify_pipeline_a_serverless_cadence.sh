#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${ROOT_DIR}/.agents/logs/verification"
mkdir -p "${LOG_DIR}"

TARGET="dev"
WINDOW_HOURS=24
MIN_SAMPLES=6
MAX_TOTAL_SECONDS=600
MAX_QUEUE_SECONDS=120
OUTPUT_JSON="${LOG_DIR}/20260223_pipeline_a_serverless_cadence.json"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/phase7/verify_pipeline_a_serverless_cadence.sh \
    --target <dev|prod-secure> \
    --window-hours <hours> \
    --min-samples <n> \
    --max-total-seconds <seconds> \
    --max-queue-seconds <seconds> \
    [--output-json <path>]
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

is_positive_int() {
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --window-hours)
      WINDOW_HOURS="${2:-}"
      shift 2
      ;;
    --min-samples)
      MIN_SAMPLES="${2:-}"
      shift 2
      ;;
    --max-total-seconds)
      MAX_TOTAL_SECONDS="${2:-}"
      shift 2
      ;;
    --max-queue-seconds)
      MAX_QUEUE_SECONDS="${2:-}"
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

if ! is_positive_int "${WINDOW_HOURS}" || ! is_positive_int "${MIN_SAMPLES}" || ! is_positive_int "${MAX_TOTAL_SECONDS}" || ! is_positive_int "${MAX_QUEUE_SECONDS}"; then
  echo "window/min-samples/max-total-seconds/max-queue-seconds must be positive integers" >&2
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

JOB_NAME="data-pipeline-a-${TARGET_SUFFIX}"
JOBS_JSON="$(databricks jobs list -o json)"
JOB_ID="$(echo "${JOBS_JSON}" | jq -r --arg name "${JOB_NAME}" '.[] | select(.settings.name == $name) | .job_id' | head -n 1)"

if [[ -z "${JOB_ID}" || "${JOB_ID}" == "null" ]]; then
  jq -n \
    --arg ts_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg target "${TARGET}" \
    --arg job_name "${JOB_NAME}" \
    --arg status "BLOCKED" \
    --arg reason "pipeline_a_job_not_found" \
    '{
      ts_utc: $ts_utc,
      target: $target,
      job_name: $job_name,
      status: $status,
      reason: $reason
    }' > "${OUTPUT_JSON}"
  cat "${OUTPUT_JSON}"
  exit 1
fi

RUNS_JSON="$(databricks jobs list-runs --job-id "${JOB_ID}" --limit 25 -o json)"
RUNS_JSON_FILE="$(mktemp)"
printf '%s' "${RUNS_JSON}" > "${RUNS_JSON_FILE}"
cleanup_tmp() {
  rm -f "${RUNS_JSON_FILE}"
}
trap cleanup_tmp EXIT

mkdir -p "$(dirname "${OUTPUT_JSON}")"
python - <<'PY' "${RUNS_JSON_FILE}" "${OUTPUT_JSON}" "${TARGET}" "${JOB_NAME}" "${JOB_ID}" "${WINDOW_HOURS}" "${MIN_SAMPLES}" "${MAX_TOTAL_SECONDS}" "${MAX_QUEUE_SECONDS}"
import json
import math
import time
import sys
from datetime import datetime, timezone
from pathlib import Path

raw_runs = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
output_json = sys.argv[2]
target = sys.argv[3]
job_name = sys.argv[4]
job_id = int(sys.argv[5])
window_hours = int(sys.argv[6])
min_samples = int(sys.argv[7])
max_total_seconds = int(sys.argv[8])
max_queue_seconds = int(sys.argv[9])

if isinstance(raw_runs, dict) and "runs" in raw_runs:
    runs = raw_runs.get("runs", [])
elif isinstance(raw_runs, list):
    runs = raw_runs
else:
    runs = []

now_ms = int(time.time() * 1000)
window_ms = window_hours * 3600 * 1000
cutoff_ms = now_ms - window_ms

samples = []
for run in runs:
    state = run.get("state", {})
    if state.get("life_cycle_state") != "TERMINATED":
        continue
    if state.get("result_state") != "SUCCESS":
        continue

    start_ms = run.get("start_time") or 0
    if start_ms < cutoff_ms:
        continue

    created_ms = run.get("created_time") or start_ms
    end_ms = run.get("end_time") or 0
    if end_ms <= start_ms:
        run_duration_ms = run.get("run_duration") or 0
        if run_duration_ms <= 0:
            continue
        total_seconds = run_duration_ms / 1000.0
    else:
        total_seconds = (end_ms - start_ms) / 1000.0

    queue_seconds = 0.0
    if created_ms and created_ms <= start_ms:
        queue_seconds = (start_ms - created_ms) / 1000.0

    samples.append(
        {
            "run_id": run.get("run_id"),
            "created_time": created_ms,
            "start_time": start_ms,
            "end_time": end_ms,
            "queue_seconds": round(queue_seconds, 3),
            "total_seconds": round(total_seconds, 3),
        }
    )

samples.sort(key=lambda row: row["start_time"], reverse=True)


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    if len(values) == 1:
        return float(values[0])
    k = (len(values) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return float(values[int(k)])
    return float(values[f] + (values[c] - values[f]) * (k - f))

queue_values = [row["queue_seconds"] for row in samples]
total_values = [row["total_seconds"] for row in samples]

queue_p50 = percentile(queue_values, 50)
queue_p95 = percentile(queue_values, 95)
total_p50 = percentile(total_values, 50)
total_p95 = percentile(total_values, 95)

sample_count = len(samples)
status = "PASS"
reason = ""

if sample_count < min_samples:
    status = "BLOCKED"
    reason = f"insufficient_samples:{sample_count}<{min_samples}"
elif (queue_p95 is not None and queue_p95 > max_queue_seconds) or (
    total_p95 is not None and total_p95 > max_total_seconds
):
    status = "BLOCKED"
    reason = (
        "threshold_exceeded:"
        f"queue_p95={queue_p95:.3f}/{max_queue_seconds},"
        f"total_p95={total_p95:.3f}/{max_total_seconds}"
    )

summary = {
    "ts_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "target": target,
    "pipeline": "pipeline_a_guardrail",
    "job_name": job_name,
    "job_id": job_id,
    "window_hours": window_hours,
    "min_samples": min_samples,
    "thresholds": {
        "max_total_seconds": max_total_seconds,
        "max_queue_seconds": max_queue_seconds,
    },
    "sample_count": sample_count,
    "percentiles": {
        "queue_seconds": {
            "p50": queue_p50,
            "p95": queue_p95,
            "max": max(queue_values) if queue_values else None,
        },
        "total_seconds": {
            "p50": total_p50,
            "p95": total_p95,
            "max": max(total_values) if total_values else None,
        },
    },
    "status": status,
    "reason": reason,
    "samples": samples,
}

with open(output_json, "w", encoding="utf-8") as f:
    json.dump(summary, f, ensure_ascii=False, indent=2)

print(json.dumps(summary, ensure_ascii=False, indent=2))

if status != "PASS":
    raise SystemExit(1)
PY
