# shellcheck shell=bash
# Sourced helpers that make the git commands run against throwaway fixture repos hermetic. Defines functions
# only; sourcing it runs nothing.
#
#   hermetic_git_disable_config_hooks   git only, no temp files: safe where forks are counted
#   hermetic_fixture_git_setup          everything a test runner needs (calls the function above)
#
# Why, in three parts:
#
# 1. git exports GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, ... into hooks (githooks(5)). With these inherited,
#    fixture git commands hit THIS repository instead. Observed 2026-09-30 from the first gated push: fixture
#    commits on the pushed branch, a staged mass deletion, core.bare=true and a probe identity in .git/config.
#    `git rev-parse --local-env-vars` is git's own list of exactly these variables.
#
# 2. Template hooks: `git init` copies them from init.templateDir. $GIT_TEMPLATE_DIR outranks that
#    (git-init(1), "TEMPLATE DIRECTORY"), so an empty one keeps them out.
#
# 3. Config-based hooks (git >= 2.54: `hook.<name>.command` + `hook.<name>.event` in the global config). Neither
#    an empty template nor core.hooksPath=/dev/null stops them; measured on git 2.56, only
#    `hook.<name>.enabled=false` does. Two of them ran bun on every fixture commit, 1.27 s per `git commit`
#    (0.01 s disabled), and under repo:check's load fixture commits blew bun's 5 s test budget
#    (review-round-gate.test.ts). The override is passed through GIT_CONFIG_COUNT/KEY/VALUE, which git applies
#    to every invocation in this process tree without touching any config file.

# Disable every config-based hook in the global config for this process tree. Appends to an existing
# GIT_CONFIG_COUNT rather than replacing it.
hermetic_git_disable_config_hooks() {
  local index="${GIT_CONFIG_COUNT:-0}" key name
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    name="${key#hook.}"
    name="${name%.command}"
    export "GIT_CONFIG_KEY_${index}=hook.${name}.enabled"
    export "GIT_CONFIG_VALUE_${index}=false"
    index=$((index + 1))
  done < <(git config --global --name-only --get-regexp '^hook\..*\.command$' 2>/dev/null || true)
  if (( index > 0 )); then export GIT_CONFIG_COUNT="$index"; fi
}

# For a test runner: clear git's repo variables, use an empty template directory, disable config hooks.
# The caller removes "$GIT_TEMPLATE_DIR" when done.
hermetic_fixture_git_setup() {
  local -a local_vars
  read -ra local_vars <<<"$(git rev-parse --local-env-vars 2>/dev/null | tr '\n' ' ')"
  if (( ${#local_vars[@]} > 0 )); then unset "${local_vars[@]}"; fi
  GIT_TEMPLATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cc-skills-empty-git-template.XXXXXX")"
  export GIT_TEMPLATE_DIR
  hermetic_git_disable_config_hooks
}
