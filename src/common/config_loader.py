"""Pipeline configuration loader.

Loads environment-specific configuration from YAML files under ``configs/``.

Priority chain (highest wins):
    CLI args  >  env vars  >  configs/{env}.yaml  >  configs/common.yaml

Usage::

    from src.common.config_loader import get_config_value, find_repo_root

    catalog = get_config_value("databricks.catalog")
    scope = get_config_value("analytics.secret_scope", "fallback-scope")
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any

import yaml

_SENTINEL = object()

_cached_config: dict | None = None
_cached_repo_root: Path | None = None


def find_repo_root() -> Path:
    """Best-effort repo root resolution for Databricks Jobs/Bundles.

    Walks parent directories from several candidate starting points looking
    for the characteristic ``src/`` + ``mock_data/`` directory pair.  Falls
    back to ``PIPELINE_ROOT`` env var or ``/dbfs/tmp/data-pipeline``.
    """
    global _cached_repo_root
    if _cached_repo_root is not None:
        return _cached_repo_root

    candidates: list[Path] = []

    # Caller's __file__ is unavailable here; use argv[0] and cwd instead.
    if sys.argv and sys.argv[0]:
        candidates.append(Path(sys.argv[0]))
    candidates.append(Path.cwd())

    env_root = os.environ.get("PIPELINE_ROOT")
    if env_root:
        candidates.append(Path(env_root))

    for base in candidates:
        for probe in (base, *base.parents):
            if (probe / "src").is_dir() and (probe / "mock_data").is_dir():
                _cached_repo_root = probe
                return probe

    result = Path(env_root or "/dbfs/tmp/data-pipeline")
    _cached_repo_root = result
    return result


def _deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge *override* into a shallow copy of *base*."""
    merged = dict(base)
    for key, value in override.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def load_config(
    *,
    env: str | None = None,
    repo_root: Path | None = None,
) -> dict:
    """Load and merge pipeline configuration.

    1. Read ``configs/common.yaml`` (required).
    2. Read ``configs/{env}.yaml`` (optional override).
    3. Deep-merge override onto base.
    4. Cache the result for the process lifetime.

    Parameters
    ----------
    env:
        Environment name (``dev``, ``prod``, ...).  Defaults to
        ``PIPELINE_ENV`` env var or ``"dev"``.
    repo_root:
        Repository root path.  Auto-detected via :func:`find_repo_root`
        if not provided.
    """
    global _cached_config
    if _cached_config is not None:
        return _cached_config

    root = repo_root or find_repo_root()
    env = env or os.environ.get("PIPELINE_ENV", "dev")

    common_path = root / "configs" / "common.yaml"
    if not common_path.exists():
        raise FileNotFoundError(f"Required config file not found: {common_path}")
    with open(common_path) as f:
        base: dict = yaml.safe_load(f) or {}

    env_path = root / "configs" / f"{env}.yaml"
    if env_path.exists():
        with open(env_path) as f:
            override: dict = yaml.safe_load(f) or {}
        base = _deep_merge(base, override)

    _cached_config = base
    return base


def get_config_value(key_path: str, default: Any = _SENTINEL) -> Any:
    """Access a configuration value using dot-notation.

    Examples::

        get_config_value("databricks.catalog")       # required
        get_config_value("analytics.secret_scope",
                         "ledger-analytics-dev")      # with fallback

    Raises :class:`KeyError` when the key is missing and no *default* is
    provided.
    """
    config = load_config()
    keys = key_path.split(".")
    current: Any = config
    for key in keys:
        if isinstance(current, dict) and key in current:
            current = current[key]
        elif default is not _SENTINEL:
            return default
        else:
            raise KeyError(f"Config key not found: {key_path}")
    return current


def reset_cache() -> None:
    """Clear cached config and repo root.  Useful for testing."""
    global _cached_config, _cached_repo_root
    _cached_config = None
    _cached_repo_root = None
