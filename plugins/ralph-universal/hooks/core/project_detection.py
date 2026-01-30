# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Project type detection utilities (single source of truth).

Consolidates project detection logic to avoid duplication across:
- loop-until-done.py (_detect_alpha_forge_simple)
- adapters/alpha_forge.py (AlphaForgeAdapter.detect)

ADR: Phase 0C consolidation from Ralph enhancement plan.
"""

import logging
from pathlib import Path

logger = logging.getLogger(__name__)


def is_alpha_forge_project(project_dir: Path | str) -> bool:
    """Detect if project is Alpha Forge (canonical check).

    Detection strategy (any match returns True):
    1. Root pyproject.toml contains 'alpha-forge' or 'alpha_forge'
    2. Monorepo: packages/*/pyproject.toml contains 'alpha-forge'
    3. Characteristic directory: packages/alpha-forge-core/ exists
    4. Experiment outputs: outputs/runs/ directory exists
    5. Git remote URL contains 'alpha-forge' (handles sparse checkouts/branches)
    6. Parent directories contain alpha-forge markers (subdirectory detection)

    Args:
        project_dir: Path to project root (may be a subdirectory)

    Returns:
        True if Alpha Forge project detected
    """
    if isinstance(project_dir, str):
        project_dir = Path(project_dir)

    if not project_dir:
        return False

    # Strategy 1: Root pyproject.toml
    pyproject = project_dir / "pyproject.toml"
    if pyproject.exists():
        try:
            content = pyproject.read_text()
            if "alpha-forge" in content or "alpha_forge" in content:
                logger.debug(f"Detected alpha-forge via {pyproject}")
                return True
        except OSError:
            pass

    # Strategy 2: Monorepo package detection
    packages_dir = project_dir / "packages"
    if packages_dir.is_dir():
        for pkg_pyproject in packages_dir.glob("*/pyproject.toml"):
            try:
                content = pkg_pyproject.read_text()
                if "alpha-forge" in content or "alpha_forge" in content:
                    logger.debug(f"Detected alpha-forge via {pkg_pyproject}")
                    return True
            except OSError:
                continue

    # Strategy 3: Characteristic directory marker
    if (project_dir / "packages" / "alpha-forge-core").is_dir():
        logger.debug("Detected alpha-forge via packages/alpha-forge-core/")
        return True

    # Strategy 4: Experiment outputs directory (unique to alpha-forge)
    if (project_dir / "outputs" / "runs").is_dir():
        logger.debug("Detected alpha-forge via outputs/runs/")
        return True

    # Strategy 5: Git remote URL contains 'alpha-forge' (handles sparse checkouts/branches)
    # This catches branches like 'asciinema-recordings' that lack file markers
    import subprocess

    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=project_dir,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            remote_url = result.stdout.strip().lower()
            if "alpha-forge" in remote_url or "alpha_forge" in remote_url:
                logger.debug(f"Detected alpha-forge via git remote: {remote_url}")
                return True
    except (subprocess.TimeoutExpired, OSError):
        pass  # Git not available or timeout, continue to other strategies

    # Strategy 6: Check parent directories (when CWD is a subdirectory)
    current = project_dir
    for _ in range(5):  # Limit traversal depth
        parent = current.parent
        if parent == current:  # Reached filesystem root
            break
        # Check parent's pyproject.toml
        parent_pyproject = parent / "pyproject.toml"
        if parent_pyproject.exists():
            try:
                content = parent_pyproject.read_text()
                if "alpha-forge" in content or "alpha_forge" in content:
                    logger.debug(f"Detected alpha-forge via parent: {parent}")
                    return True
            except OSError:
                pass
        # Check for alpha-forge packages in parent
        parent_packages = parent / "packages"
        if parent_packages.is_dir():
            if (parent_packages / "alpha-forge-core").is_dir():
                logger.debug(f"Detected alpha-forge via parent packages: {parent}")
                return True
        # Check for outputs/runs in parent
        if (parent / "outputs" / "runs").is_dir():
            logger.debug(f"Detected alpha-forge via parent outputs: {parent}")
            return True
        current = parent

    return False
