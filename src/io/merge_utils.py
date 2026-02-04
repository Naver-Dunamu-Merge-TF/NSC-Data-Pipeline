from __future__ import annotations

from typing import Iterable


def build_merge_condition(
    keys: Iterable[str],
    *,
    target_alias: str = "target",
    source_alias: str = "source",
) -> str:
    key_list = [key for key in keys if key]
    if not key_list:
        raise ValueError("merge keys are required")
    return " AND ".join(
        f"{target_alias}.{key} = {source_alias}.{key}" for key in key_list
    )


def merge_delta_table(  # pragma: no cover
    df,
    table_fqn: str,
    merge_keys: Iterable[str],
    *,
    target_alias: str = "target",
    source_alias: str = "source",
) -> None:
    from delta.tables import DeltaTable

    condition = build_merge_condition(
        merge_keys, target_alias=target_alias, source_alias=source_alias
    )
    delta_table = DeltaTable.forName(df.sparkSession, table_fqn)
    (
        delta_table.alias(target_alias)
        .merge(df.alias(source_alias), condition)
        .whenMatchedUpdateAll()
        .whenNotMatchedInsertAll()
        .execute()
    )
