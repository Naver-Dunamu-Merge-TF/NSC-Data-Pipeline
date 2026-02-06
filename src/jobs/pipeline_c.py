from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

from src.io.secret_loader import (
    DEFAULT_SECRET_KEY,
    DEFAULT_SECRET_SCOPE,
    resolve_user_key_salt,
)
from src.transforms.analytics import build_fact_payment_anonymized


def build_pipeline_c_fact_rows(
    order_events: Iterable[Mapping[str, Any]],
    order_items: Iterable[Mapping[str, Any]],
    products: Iterable[Mapping[str, Any]],
    *,
    run_id: str,
    salt: str | None = None,
    secret_scope: str = DEFAULT_SECRET_SCOPE,
    secret_key: str = DEFAULT_SECRET_KEY,
    order_source_filter: str | None = "PAYMENT_ORDERS",
    env: Mapping[str, str] | None = None,
    dbutils=None,
) -> list[dict[str, Any]]:
    resolved_salt = salt or resolve_user_key_salt(
        secret_scope=secret_scope,
        secret_key=secret_key,
        env=env,
        dbutils=dbutils,
        allow_local_fallback=True,
    )
    return build_fact_payment_anonymized(
        order_events,
        order_items,
        products,
        run_id=run_id,
        salt=resolved_salt,
        order_source_filter=order_source_filter,
    )
