/**
 * Per-user names for directories under a temp root that every account on the host can see.
 *
 * On macOS os.tmpdir() is a per-user /var/folders/... directory, but /tmp is shared, and on Linux os.tmpdir() is
 * /tmp itself. A fixed directory there is created by the first account that needs it, with that account's umask
 * (0755), and every other account then fails to write into it: a check silently skipped, a gate never set, a cache
 * never saved. On a host several people use, suffix the directory with the uid.
 */

/** The uid (or the user name where there is no getuid), as a path-safe suffix. */
export function perUserTempSuffix(): string {
  return typeof process.getuid === "function" ? String(process.getuid()) : process.env.USER || "user";
}

/** `<base>-<uid>`: the per-user twin of a directory that would otherwise be shared by every account. */
export function perUserTempPath(base: string): string {
  return `${base}-${perUserTempSuffix()}`;
}
