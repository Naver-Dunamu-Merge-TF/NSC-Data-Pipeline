from __future__ import annotations

import scripts.phase7.sec004_secret_scope_probe as sec004


def test_compute_secret_fingerprint_is_deterministic() -> None:
    digest_1, length_1 = sec004.compute_secret_fingerprint("abc123")
    digest_2, length_2 = sec004.compute_secret_fingerprint("abc123")
    digest_3, length_3 = sec004.compute_secret_fingerprint("abc124")

    assert length_1 == 6
    assert length_2 == 6
    assert digest_1 == digest_2
    assert digest_1 != digest_3
    assert length_3 == 6


def test_parse_args_requires_sec004_arguments() -> None:
    args = sec004.parse_args(
        [
            "--run-id",
            "sec004_case",
            "--secret-scope",
            "ledger-analytics-dev",
            "--secret-key",
            "salt_user_key",
        ]
    )
    assert args.run_id == "sec004_case"
    assert args.secret_scope == "ledger-analytics-dev"
    assert args.secret_key == "salt_user_key"
