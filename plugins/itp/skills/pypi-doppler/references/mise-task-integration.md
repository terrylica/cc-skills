# mise Task Integration

When using mise tasks to orchestrate the release workflow, the publish task **must** depend on the build task. Without this dependency, running `mise run release:pypi` before building will fail because no wheels exist.

```toml
# .mise.toml — CORRECT: publish depends on build
[tasks."release:build-all"]
description = "Build all platform wheels + sdist"
depends = ["release:version"]
run = """
mise run release:macos-arm64
mise run release:linux
mise run release:sdist
# Consolidate artifacts to dist/
VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/.*= "\\(.*\\)"/\\1/')
cp -n target/wheels/*-${VERSION}-*.whl dist/ 2>/dev/null || true
cp -n target/wheels/*-${VERSION}.tar.gz dist/ 2>/dev/null || true
"""

[tasks."release:pypi"]
description = "Publish to PyPI using Doppler credentials (local-only, ADR-0027)"
depends = ["release:build-all"]  # CRITICAL: enforces build-before-publish
run = "./scripts/publish-to-pypi.sh"

[tasks."release:full"]
description = "Full release workflow"
depends = ["release:postflight", "release:pypi"]  # Include ALL phases
run = "echo 'Released and published!'"
```

**Anti-pattern**: Defining `release:pypi` without `depends` on `release:build-all`. The publish script will detect "no wheels found" and fail, but the failure happens late instead of being prevented by the task DAG.

See [Release Workflow Patterns](../../mise-tasks/references/release-workflow-patterns.md) for the complete DAG pattern and audit checklist.
