from __future__ import annotations

from datetime import datetime

import pytest

from src.io.pipeline_state_io import (
    PipelineStateRecord,
    apply_pipeline_state,
    parse_pipeline_state_record,
)


def test_apply_pipeline_state_success_sets_checkpoint_fields() -> None:
    updated = apply_pipeline_state(
        pipeline_name="pipeline_a",
        run_id="run-1",
        status="success",
        last_processed_end=datetime(2026, 2, 6, 0, 10, 0),
        event_ts=datetime(2026, 2, 6, 0, 11, 0),
    )
    assert updated.pipeline_name == "pipeline_a"
    assert updated.last_run_id == "run-1"
    assert updated.last_processed_end is not None
    assert updated.last_success_ts is not None


def test_apply_pipeline_state_failure_keeps_last_success_checkpoint() -> None:
    current = PipelineStateRecord(
        pipeline_name="pipeline_a",
        last_success_ts=datetime(2026, 2, 6, 0, 11, 0),
        last_processed_end=datetime(2026, 2, 6, 0, 10, 0),
        last_run_id="run-1",
        updated_at=datetime(2026, 2, 6, 0, 11, 0),
    )
    failed = apply_pipeline_state(
        pipeline_name="pipeline_a",
        run_id="run-2",
        status="failure",
        current_state=current,
        event_ts=datetime(2026, 2, 6, 0, 20, 0),
    )
    assert failed.last_success_ts == current.last_success_ts
    assert failed.last_processed_end == current.last_processed_end
    assert failed.last_run_id == "run-2"


def test_parse_pipeline_state_record_requires_pipeline_name() -> None:
    with pytest.raises(ValueError):
        parse_pipeline_state_record({})
