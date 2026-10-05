# shellcheck shell=bash
# op_sa_token.sh — resolve a 1Password Service Account token for `op`, from sources the
# USER configured. Sourced (not executed) by resolve_pushover_secret.sh and by the
# verbatim-audit-notify scripts, so there is one implementation per plugin.
#
# Resolution order — these three, nothing else, and NO default path:
#   1. OP_SERVICE_ACCOUNT_TOKEN already in the environment (used as-is).
#   2. OP_SA_TOKEN_CMD — a command whose stdout is the token, e.g.
#        export OP_SA_TOKEN_CMD='vault get op-service-account token'
#      It is split on whitespace into an argv and executed DIRECTLY: no shell, so no
#      quoting, globbing, variable expansion, pipes or redirections. Use an absolute
#      program path when the caller (launchd, cron) has a minimal PATH.
#   3. A token FILE, only when the user names one: PUSHOVER_OP_SA_TOKEN_FILE (this
#      plugin's own, older knob) or the generic OP_SA_TOKEN_FILE.
#
# Until 2026-10 the plugin silently read a hard-coded file under ~/.claude; that default
# is gone. A secret lying in a plaintext file nobody asked for is the thing being removed.
#
# The token travels only through stdout and the environment of the `op` child — never
# argv, which any local user can read from the process table (ps, /proc/<pid>/cmdline).
#
# op_sa_token: print the token on stdout and return 0. Otherwise print one diagnostic
# line on stderr and return 1 (nothing configured) or 2 (configured, but it failed).

op_sa_token_unconfigured_hint() {
  printf '%s' "no 1Password service-account token source is configured: export OP_SERVICE_ACCOUNT_TOKEN, or set OP_SA_TOKEN_CMD to a command that prints it (e.g. OP_SA_TOKEN_CMD='vault get op-service-account token'), or set OP_SA_TOKEN_FILE to a chmod-600 file holding it"
}

op_sa_token() {
  if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    printf '%s' "${OP_SERVICE_ACCOUNT_TOKEN}"
    return 0
  fi

  if [ -n "${OP_SA_TOKEN_CMD:-}" ]; then
    local -a argv=()
    local out="" rc=0
    read -r -a argv <<<"${OP_SA_TOKEN_CMD}"
    if [ "${#argv[@]}" -eq 0 ]; then
      echo "op_sa_token: OP_SA_TOKEN_CMD is blank" >&2
      return 2
    fi
    out="$("${argv[@]}")" || rc=$?
    if [ "${rc}" -ne 0 ]; then
      echo "op_sa_token: OP_SA_TOKEN_CMD (${argv[0]}) exited ${rc}" >&2
      return 2
    fi
    if [ -z "${out}" ]; then
      echo "op_sa_token: OP_SA_TOKEN_CMD (${argv[0]}) printed nothing" >&2
      return 2
    fi
    printf '%s' "${out}"
    return 0
  fi

  local file="${PUSHOVER_OP_SA_TOKEN_FILE:-${OP_SA_TOKEN_FILE:-}}"
  if [ -n "${file}" ]; then
    if [ ! -r "${file}" ]; then
      echo "op_sa_token: token file ${file} is not readable" >&2
      return 2
    fi
    local tok=""
    tok="$(tr -d '\r\n' <"${file}")"
    if [ -z "${tok}" ]; then
      echo "op_sa_token: token file ${file} is empty" >&2
      return 2
    fi
    printf '%s' "${tok}"
    return 0
  fi

  echo "op_sa_token: $(op_sa_token_unconfigured_hint)" >&2
  return 1
}
