**Skill**: [ITP Go Workflow](../SKILL.md)

# Phase 3 Gate Logic

## Entry Gate Logic

Parse flags from invocation:

- `RELEASE_FLAG`: true if `-r` or `--release` provided
- `PUBLISH_FLAG`: true if `-p` or `--publish` provided

```bash
/usr/bin/env bash << 'PREFLIGHT_EOF_2'
# Check branch
CURRENT_BRANCH=$(git branch --show-current)

# Parse flags
RELEASE_FLAG=false
PUBLISH_FLAG=false
[[ "$ARGUMENTS" =~ -r|--release ]] && RELEASE_FLAG=true
[[ "$ARGUMENTS" =~ -p|--publish ]] && PUBLISH_FLAG=true
PREFLIGHT_EOF_2
```

## Case 1: Feature Branch (not main/master)

```bash
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
  echo ""
  echo "============================================================="
  if [ "$RELEASE_FLAG" = true ] || [ "$PUBLISH_FLAG" = true ]; then
    # Verbose reminder when flags provided on feature branch
    echo "  PHASE 3 DEFERRED (Feature Branch)"
    echo "============================================================="
    echo ""
    echo "  You provided release/publish flags on a feature branch:"
    [ "$RELEASE_FLAG" = true ] && echo "    -r (release): YES"
    [ "$PUBLISH_FLAG" = true ] && echo "    -p (publish): YES"
    echo ""
    echo "  Current branch: $CURRENT_BRANCH"
    echo ""
    echo "  Phase 3 CANNOT run on feature branches."
    echo "  These flags are recorded as YOUR INTENT for after merge."
    echo ""
    echo "  +-----------------------------------------------------------+"
    echo "  | NEXT STEPS (you must do these manually):                  |"
    echo "  +-----------------------------------------------------------+"
    echo "  | 1. Create PR: gh pr create                                |"
    echo "  | 2. Get approval and merge to main/master                  |"
    echo "  | 3. Switch: git checkout main && git pull                  |"
    [ "$RELEASE_FLAG" = true ] && echo "  | 4. Release: /itp:go -r    # semantic-release             |"
    [ "$PUBLISH_FLAG" = true ] && echo "  | 5. Publish: /itp:go -p    # PyPI publish                 |"
    echo "  |                                                           |"
    echo "  | Or combine: /itp:go -r -p    # for both                   |"
    echo "  +-----------------------------------------------------------+"
    echo ""
    echo "  The release/publish steps will NOT happen automatically."
    echo "  You MUST manually run them after merging to main."
  else
    # Standard feature branch message (no flags)
    echo "  WORKFLOW COMPLETE (Phase 2)"
    echo "============================================================="
    echo ""
    echo "  Current branch: $CURRENT_BRANCH"
    echo "  Phase 3 (Release): SKIPPED - not on main/master"
    echo ""
    echo "  Next steps:"
    echo "    1. Create PR: gh pr create"
    echo "    2. Get approval and merge to main/master"
    echo "    3. Run /itp:go -r on main to release (or /itp:go -r -p for both)"
  fi
  echo ""
  echo "============================================================="
  exit 0
fi
```

## Case 2: Main/Master WITHOUT Flags

```bash
if [ "$RELEASE_FLAG" = false ] && [ "$PUBLISH_FLAG" = false ]; then
  echo ""
  echo "============================================================="
  echo "  PHASE 3 SKIPPED (No Flags)"
  echo "============================================================="
  echo ""
  echo "  You are on: $CURRENT_BRANCH"
  echo "  But no release/publish flags were provided."
  echo ""
  echo "  To release this version, run one of:"
  echo "    /itp:go -r       # semantic-release (version + changelog + GitHub)"
  echo "    /itp:go -p       # PyPI publishing (if applicable)"
  echo "    /itp:go -r -p    # both release and publish"
  echo ""
  echo "  Phase 3 requires explicit intent via flags."
  echo ""
  echo "============================================================="
  exit 0
fi
```

## Case 3: Main/Master WITH Flags

Proceed to Phase 3 subsections (3.1 through 3.4) in [SKILL.md](../SKILL.md#phase-3-release--publish-requires--r-or--p-flag-on-main).
