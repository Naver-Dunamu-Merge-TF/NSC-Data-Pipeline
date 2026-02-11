from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Mapping

from src.common.time_utils import date_kst, now_utc

WINDOW_PARAM_KEYS = ("start_ts", "end_ts", "date_kst_start", "date_kst_end")


def _is_blank(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return value.strip() == ""
    return False


def inject_default_daily_backfill(
    payload: Mapping[str, Any],
    *,
    now_ts: datetime | None = None,
) -> dict[str, Any]:
    """Default empty window parameters to one-day KST backfill.

    If `run_mode/start_ts/end_ts/date_kst_start/date_kst_end` are all blank,
    this helper sets:
    - run_mode=backfill
    - date_kst_start=date_kst_end=yesterday(KST)
    """

    resolved = dict(payload)
    should_inject = _is_blank(resolved.get("run_mode")) and all(
        _is_blank(resolved.get(key)) for key in WINDOW_PARAM_KEYS
    )
    if not should_inject:
        return resolved

    baseline = now_ts or now_utc()
    target_date = date_kst(baseline) - timedelta(days=1)
    target_iso = target_date.isoformat()
    resolved["run_mode"] = "backfill"
    resolved["date_kst_start"] = target_iso
    resolved["date_kst_end"] = target_iso
    return resolved
