# Task Dependency: Publish Must Depend on Build

When a task runner orchestrates the release, the publish task **must** declare a dependency on the build task. Without it, running the publish task on a clean checkout fails late with "no wheels found" instead of the task graph building first.

With moon (the task runner used across these repos), declare it in `moon.yml` with `deps`:

```yaml
# moon.yml — CORRECT: publish depends on build
tasks:
  release-build-all:
    description: "Build all platform wheels + sdist into dist/"
    deps: ["~:release-version"]
    script: |
      bash scripts/build-macos-arm64.sh
      bash scripts/build-linux.sh
      bash scripts/build-sdist.sh

  release-pypi:
    description: "Publish to PyPI using Doppler credentials (local-only)"
    deps: ["~:release-build-all"] # CRITICAL: enforces build-before-publish
    command: "./scripts/publish-to-pypi.sh"

  release-full:
    description: "Full release workflow"
    deps: ["~:release-postflight", "~:release-pypi"] # include ALL phases
    command: "echo 'Released and published!'"
```

Run it with `moon run <project>:release-full`. The build script names above are placeholders for whatever your project uses to produce wheels.

**Anti-pattern**: defining `release-pypi` without `deps` on `release-build-all`. The publish script will detect "no wheels found" and fail, but only after the release has already started, instead of the task graph preventing it.
