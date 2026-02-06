from __future__ import annotations

from datetime import date
import hashlib

from src.io.secret_loader import LOCAL_DUMMY_SALT
from src.jobs.pipeline_c import build_pipeline_c_fact_rows


def _sample_order_events():
    return [
        {
            "order_ref": "101",
            "order_source": "PAYMENT_ORDERS",
            "user_id": "user-1",
            "merchant_name": "CoffeeLab",
            "amount": "120.00",
            "status": "PAID",
            "event_date_kst": date(2026, 2, 1),
        }
    ]


def _sample_order_items():
    return [
        {
            "item_id": 1,
            "order_ref": "101",
            "product_id": 10,
            "quantity": 1,
            "price_at_purchase": "120.00",
        }
    ]


def _sample_products():
    return [{"product_id": 10, "category": "BEANS"}]


def test_build_pipeline_c_fact_rows_uses_local_fallback_salt() -> None:
    rows = build_pipeline_c_fact_rows(
        _sample_order_events(),
        _sample_order_items(),
        _sample_products(),
        run_id="run-c",
        env={},
        dbutils=None,
    )

    assert len(rows) == 1
    expected = hashlib.sha256(f"user-1{LOCAL_DUMMY_SALT}".encode("utf-8")).hexdigest()
    assert rows[0]["user_key"] == expected


def test_build_pipeline_c_fact_rows_prefers_explicit_salt() -> None:
    rows = build_pipeline_c_fact_rows(
        _sample_order_events(),
        _sample_order_items(),
        _sample_products(),
        run_id="run-c",
        salt="explicit-salt",
        env={"ANON_USER_KEY_SALT": "env-salt"},
    )

    expected = hashlib.sha256("user-1explicit-salt".encode("utf-8")).hexdigest()
    assert rows[0]["user_key"] == expected
