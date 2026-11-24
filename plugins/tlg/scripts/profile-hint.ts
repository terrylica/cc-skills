/**
 * The error for a profile name with no 1Password item. On a fresh account (a new user on a shared
 * Linux host, say) the profile file does not exist yet, so the list of profiles is empty and the bare
 * "unknown profile" message gave no way forward. Name the file, its shape and the two ways around it.
 */
/** The profile file, relative to the user's home; `loadProfiles()` in tg-cli.ts reads exactly this path. */
export const PROFILES_RELATIVE_PATH = ".config/cc-skills/tlg-profiles.json";
export const PROFILES_FILE = `~/${PROFILES_RELATIVE_PATH}`;

export function unknownProfileMessage(profile: string, available: readonly string[]): string {
  const known = available.length > 0 ? `Available: ${available.join(", ")}.` : `No profiles are configured for this user.`;
  return (
    `unknown profile '${profile}'. ${known} ` +
    `Add it to ${PROFILES_FILE} as {"default": "<profile>", "profiles": {"<profile>": "<1password-item-id>"}}, ` +
    `or set TELETHON_OP_UUID to the 1Password item for one run, ` +
    `or skip 1Password for the API id and hash with TELEGRAM_API_ID and TELEGRAM_API_HASH ` +
    `(each user keeps their own profile file and their own session in ~/.local/share/gramjs/<profile>.session).`
  );
}
