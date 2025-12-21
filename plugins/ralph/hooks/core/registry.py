# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Adapter registry with auto-discovery.

Scans the adapters/ directory and loads all ProjectAdapter implementations.
Alpha Forge exclusive: No universal fallback - Ralph only works with Alpha Forge.
"""

import importlib.util
import logging
from pathlib import Path

from core.protocols import ProjectAdapter

logger = logging.getLogger(__name__)


class AdapterRegistry:
    """Auto-discovers and manages project adapters.

    The registry scans the adapters/ directory on initialization and loads
    all classes that implement the ProjectAdapter protocol. When get_adapter()
    is called, it tries each adapter's detect() method until one matches,
    falling back to the universal adapter if none match.

    Example:
        # Initialize registry (scans adapters/ directory)
        AdapterRegistry.discover(Path(__file__).parent.parent / "adapters")

        # Get adapter for a project
        adapter = AdapterRegistry.get_adapter(Path("/path/to/project"))
        print(f"Using adapter: {adapter.name}")
    """

    _adapters: list[ProjectAdapter] = []
    _universal: ProjectAdapter | None = None
    _discovered: bool = False

    @classmethod
    def discover(cls, adapters_dir: Path) -> None:
        """Scan adapters/ directory and load all adapter classes.

        Args:
            adapters_dir: Path to the adapters/ directory

        Raises:
            FileNotFoundError: If adapters_dir doesn't exist
        """
        if not adapters_dir.exists():
            logger.warning(f"Adapters directory not found: {adapters_dir}")
            return

        cls._adapters = []
        cls._universal = None

        for py_file in sorted(adapters_dir.glob("*.py")):
            if py_file.name.startswith("_"):
                continue

            try:
                cls._load_adapter_module(py_file)
            except Exception as e:
                logger.error(f"Failed to load adapter from {py_file.name}: {e}")

        cls._discovered = True
        logger.info(
            f"Discovered {len(cls._adapters)} adapters + "
            f"{'universal fallback' if cls._universal else 'no fallback'}"
        )

    @classmethod
    def _load_adapter_module(cls, py_file: Path) -> None:
        """Load a single adapter module and register its adapter class.

        Args:
            py_file: Path to the Python adapter file
        """
        spec = importlib.util.spec_from_file_location(py_file.stem, py_file)
        if spec is None or spec.loader is None:
            logger.warning(f"Could not load spec for {py_file.name}")
            return

        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        # Find classes that look like adapters (have 'name' attribute and required methods)
        for attr_name in dir(module):
            if attr_name.startswith("_"):
                continue

            attr = getattr(module, attr_name)
            if not isinstance(attr, type):
                continue

            # Check if it has the required adapter attributes/methods
            if not (
                hasattr(attr, "name")
                and hasattr(attr, "detect")
                and hasattr(attr, "get_metrics_history")
                and hasattr(attr, "check_convergence")
                and hasattr(attr, "get_session_mode")
            ):
                continue

            try:
                adapter = attr()
                if adapter.name == "universal":
                    cls._universal = adapter
                    logger.debug(f"Registered universal adapter from {py_file.name}")
                else:
                    cls._adapters.append(adapter)
                    logger.debug(
                        f"Registered adapter '{adapter.name}' from {py_file.name}"
                    )
            except Exception as e:
                logger.warning(f"Could not instantiate {attr_name}: {e}")

    @classmethod
    def get_adapter(cls, project_dir: Path) -> ProjectAdapter | None:
        """Return matching adapter (Alpha Forge exclusive, no universal fallback).

        Args:
            project_dir: Path to project root directory

        Returns:
            The first adapter whose detect() returns True, or None if not Alpha Forge
        """
        if not cls._discovered:
            # Auto-discover if not already done
            adapters_dir = Path(__file__).parent.parent / "adapters"
            cls.discover(adapters_dir)

        for adapter in cls._adapters:
            try:
                if adapter.detect(project_dir):
                    logger.info(f"Selected adapter: {adapter.name}")
                    return adapter
            except Exception as e:
                logger.warning(f"Adapter {adapter.name} detect() failed: {e}")

        # Alpha Forge exclusive: no fallback, return None for non-Alpha Forge projects
        logger.info("No matching adapter found (Ralph is Alpha Forge exclusive)")
        return None

    @classmethod
    def list_adapters(cls) -> list[str]:
        """Return list of registered adapter names.

        Returns:
            List of adapter name strings
        """
        names = [a.name for a in cls._adapters]
        if cls._universal:
            names.append(cls._universal.name)
        return names

    @classmethod
    def reset(cls) -> None:
        """Reset registry state (for testing)."""
        cls._adapters = []
        cls._universal = None
        cls._discovered = False
