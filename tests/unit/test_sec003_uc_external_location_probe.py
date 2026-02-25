from __future__ import annotations

import scripts.phase7.sec003_uc_external_location_probe as sec003


def test_sanitize_suffix_replaces_non_identifier_characters() -> None:
    assert sec003._sanitize_suffix("run-2026/02/23 12:00") == "run_2026_02_23_12_00"
    assert sec003._sanitize_suffix("***") == "probe"


def test_build_probe_location_normalizes_trailing_slash() -> None:
    path = sec003.build_probe_location(
        base_path="abfss://container@account.dfs.core.windows.net/",
        run_id="run-1",
    )
    assert (
        path == "abfss://container@account.dfs.core.windows.net/_sec003_probe_run_1.txt"
    )


def test_parse_args_requires_sec003_arguments() -> None:
    args = sec003.parse_args(
        [
            "--run-id",
            "sec003_case",
            "--catalog",
            "cat",
            "--external-location",
            "team4_adls_test",
            "--base-path",
            "abfss://container@account.dfs.core.windows.net",
        ]
    )
    assert args.run_id == "sec003_case"
    assert args.catalog == "cat"
    assert args.external_location == "team4_adls_test"
    assert args.base_path.startswith("abfss://")
