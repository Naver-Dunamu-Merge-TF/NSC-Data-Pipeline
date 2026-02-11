from __future__ import annotations

from datetime import datetime, timezone

from src.common.window_defaults import inject_default_daily_backfill


def test_inject_default_daily_backfill_when_window_and_mode_blank() -> None:
    payload = {
        "run_mode": "",
        "start_ts": "",
        "end_ts": "",
        "date_kst_start": "",
        "date_kst_end": "",
    }
    resolved = inject_default_daily_backfill(
        payload,
        now_ts=datetime(2026, 2, 12, 1, 0, tzinfo=timezone.utc),
    )
    assert resolved["run_mode"] == "backfill"
    assert resolved["date_kst_start"] == "2026-02-11"
    assert resolved["date_kst_end"] == "2026-02-11"


def test_inject_default_daily_backfill_keeps_explicit_run_mode() -> None:
    payload = {
        "run_mode": "incremental",
        "start_ts": None,
        "end_ts": None,
        "date_kst_start": "",
        "date_kst_end": "",
    }
    resolved = inject_default_daily_backfill(payload)
    assert resolved == payload


def test_inject_default_daily_backfill_keeps_explicit_window() -> None:
    payload = {
        "run_mode": "incremental",
        "start_ts": "2026-02-11T00:00:00Z",
        "end_ts": "2026-02-11T00:10:00Z",
        "date_kst_start": "",
        "date_kst_end": "",
    }
    resolved = inject_default_daily_backfill(payload)
    assert resolved == payload


def test_inject_default_daily_backfill_keeps_invalid_mode_for_validation() -> None:
    payload = {
        "run_mode": "nightly",
        "start_ts": "",
        "end_ts": "",
        "date_kst_start": "",
        "date_kst_end": "",
    }
    resolved = inject_default_daily_backfill(payload)
    assert resolved == payload
