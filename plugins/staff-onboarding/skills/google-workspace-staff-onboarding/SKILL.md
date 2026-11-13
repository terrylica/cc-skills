---
name: google-workspace-staff-onboarding
description: Onboard a staff member onto their Google Workspace seat through a chat conversation the agent runs, for ANY organisation - the steps that are the same everywhere (find the seat, first sign-in with a temporary password and one backup code, Google's forced password change and its "Don't get locked out" page, a passkey on the person's own phone then 2-Step Verification then new backup codes, a shared seat, shared drives, mail questions, where old mail really is and copying it from an Outlook .pst, labels, filters and send-as, ending a legacy forward, contacts, remote support on a staff Windows PC or Mac, a company GitHub account), driven by the organisation's own profile (onboarding/profile.toml) and overlay skill, and improved after every onboarding through a name-free lessons log that becomes pull requests. Use when someone is ready to start on a Workspace account, or to write a profile for a new organisation. TRIGGERS - onboard staff, new staff member, Workspace seat, first sign-in, backup code, passkey, 2-Step Verification, Don't get locked out, shared seat, pst import, staff onboarding profile, onboarding lessons.
---

# Google Workspace staff onboarding (organisation-agnostic)

> **Self-Evolving skill**: every onboarding feeds the organisation's lessons log, and generic lessons come back here as pull requests; see § Lessons, then a PR, and the Post-Execution Reflection at the bottom.

This skill is the **mechanism**: the steps that are the same in every Google Workspace organisation. Each organisation supplies the **policy**: a profile, `onboarding/profile.toml` in its own repository ([contract](./references/profile-contract.md), [example](./references/example-profile.toml)), and an overlay skill for what only it does. Read the profile first; every command, address pattern, language and channel below comes from it, written here as `profile:<key>`. Where the overlay skill and this skill differ, the overlay wins for that organisation. A step whose profile section is absent does not apply.

Every onboarding also improves this skill: whenever the person gets stuck, and once at the end, write a lesson and propose the fix (§ Lessons, then a PR).

## Before the first message

1. Read the profile and the overlay skill (`profile:org.overlay_skill`). Run `profile:admin.spec` for the organisation's admin tool: its JSON command list is the authority on flags, not this file.
2. Read the lessons: `profile:lessons.check`, then the log at `profile:lessons.log` with high-priority entries first (seen twice or more). **Before each step below, read the lessons whose `step` is that step's id**; they are the newest knowledge about it.
3. Find the person in the roster (`profile:roster.people`, never tracked) and in the organisation's access model. A name comes from the organisation's own documents, never from a chat display name; confirm it with the person.

## Conversation rules

- **The person works on their own, through a conversation with this session**: no calls or screen shares. Use `profile:chat.channel`; every composed message carries the automatic Claude Code footer with `profile:chat.footer_context`. When `profile:chat.name_signature` is false, never end a chat message with a name. Where the text itself must name the administrator (the introduction), use `profile:org.operator_name`.
- **Languages**: `profile:chat.languages`, every line in each language the person reads, side by side.
- **Introduce first**: who the administrator is, what the footer line means, why the organisation is moving to Google Workspace, the steps ahead.
- **Secrets only in a private channel** (`profile:chat.secrets_channel`): passwords, backup codes and single-use keys never go where other staff read. Delete them for everyone once used. When reading a chat back, mask passwords **and** backup codes, or skip those messages.
- **One question at a time, by tap buttons** where the profile has a bot (`profile:chat.bot`). Follow up every short or ambiguous answer until it is specific (which year, which address, visible CC or not); conflicting answers get one clear restatement for a yes.
- **The reply watcher must show everything the person sends**, including every attachment: download it and print its path. A screenshot without a caption is a message, and a captioned one is more than its text. With many agent windows open on the administrator's machine, read the watcher's output file rather than trusting silence. After any history import into a chat, re-arm the watcher from the newest message ID.
- **One listener per bot token**: a second listener steals the person's taps. Sessions onboarding different people take turns.
- **Ask for a screenshot before every irreversible click** (Migrate, Turn on, Delete) and confirm each sign-in milestone from a screenshot, not from "done".

## Steps

Each step's id (in brackets) is the `step` value a lesson about it carries.

1. **Find the seat** [`find-seat`]. `profile:admin.check` reads the account (never signed in = last login 1970), 2-Step Verification state, aliases, free alias names and every shared drive as admin and as the user. Google allows up to 30 aliases per user. A new alias may not be listed for some minutes: run the check again before concluding it failed.
2. **First message** [`introduce`]: the introduction, the account address and aliases, that the old mailbox keeps working for now, and two questions: at a computer now (which one), and iPhone or Android.
3. **Shared seat** [`shared-seat`], when the person joins someone who still works on the seat: never reset the password. Hand it over once through a password manager share of a **new item holding only the username and password**; never share the original item, which may also hold the administrator's authenticator seed and notes (check the fields first). Send one backup code with `profile:admin.backup_code` (it voids older backup codes only). The person adds a passkey on their own phone and turns on **Skip password when possible** (myaccount › Security › Passkeys). The administrator's own passkeys stay as break-glass. Record whose passkey is whose from the login audit (`profile:admin.login_audit`: `passkey_enrolled` and `2sv_enroll` with time and IP) in the roster.
4. **First sign-in** [`first-signin`], own seat: `profile:admin.first_signin` resets the password with change at next sign-in, makes backup codes and sends the password and one code privately, without printing either. The message says: **sign in in Chrome (or another browser), not Outlook**; Outlook's "Your email provider can no longer connect to Outlook" can be ignored. Google has no password-free first sign-in: a backup code replaces only the second step.
5. **Password change** [`password-change`]: Google may or may not force it at the first sign-in. Say "if Google asks, set your own password", ask afterwards whether it asked, and if not, send the person to `myaccount.google.com/signinoptions/password`.
6. **"Don't get locked out"** [`2sv`]: a never-signed-in account often shows this page after the password when 2-Step Verification is enforced from a later date for new users. The person clicks **Do this later** and enrols from the phone in the next step.
7. **Passkey, then 2-Step Verification** [`passkey`]: the Gmail app on the phone (Google prompt), then **a passkey on the person's own phone** (Gmail app › Manage your Google Account › Security › Passkeys), then Turn on 2-Step Verification. A passkey on the person's own device is required; the Google prompt alone is not enough. A password manager's browser extension may grab a passkey prompt on the computer: create it on the phone. A Windows PC without Windows Hello asks for a USB key: skip it; the phone signs in on the PC by QR code. Confirm from a screenshot of "Second steps". The Gmail app is not a prerequisite for the passkey: when adding the account in the app fails, or the person wants to work on the PC first, create the passkey from the PC (myaccount.google.com › Security › Passkeys › Create a passkey › Use another device), and the phone camera scans the QR code, no app needed. 2-Step Verification enforcement for a new user starts on the date shown on the "Don't get locked out" page, so the passkey must exist before then. In a Gmail app that already holds other accounts, Add account is under the avatar › Manage accounts on this device.
8. **New backup codes** [`backup-codes`]: Backup codes › Get new codes, which voids the ones sent; the person keeps them on paper or in their own password manager.
9. **Shared drives** [`shared-drives`]: show their department drive and the company-wide one, and ask them to create and delete a "Test" folder. Work files never go in My Drive. `profile:admin.drives_domain_only` keeps drives to the organisation's own people.
10. **Mail questions** [`mail-questions`], one at a time: which old mail to copy, webmail or Outlook, mail kept only on the PC, sending address, labels (one example per label), an alias with their name, sender name, CC habits. For a seat shared with a colleague, apply nothing until the colleague has been asked too. Outlook becomes reference only: from now on mail is read and answered in Gmail in the browser.
11. **Where the old mail really is** [`legacy-mail`]: ask for Outlook › File › Account Settings. **POP or IMAP into a .pst on the PC means the server holds little** (`profile:legacy_mail.kind`). Ask why each account is in Outlook: one Outlook may also pull a colleague's mailbox, whose mail then exists only on this PC. Never copy another person's .pst into this seat.
12. **Copy the old mail** [`mail-copy`] with Google Workspace Migration for Microsoft Outlook (`https://tools.google.com/dlpage/gsmmo/`, the version for users), run by the person, signed in as their seat: close Outlook; From PST File(s) › their own .pst; Migrate all data on the first run; untick Calendar, Contacts, Junk and Deleted items; set **on or after** the agreed start and **on or before** the day before the oldest message already in Gmail (read it first), so nothing is copied twice. A screenshot before each Next and before Migrate.
13. **Labels and filters** [`labels-filters`]: `profile:admin.labels` first, then `profile:admin.filters` with entries like `{"label": "Quotes", "query": "subject:(quote OR quotation)"}`. Filters label new mail only. Mail forwarded to a brand-new alias tends to land in Spam: give that alias's filter `neverSpam`. Gmail has no automatic CC; a visible CC habit is the person's own.
14. **Send-as** [`send-as`]: `profile:admin.send_as` makes the agreed alias the default From address with the agreed sender name (no verification for the user's own alias).
15. **End the legacy forward** [`end-forward`], when the profile has `legacy_mail`: once the person works in Gmail and their mail is verified there, stop the legacy host keeping a copy (`profile:legacy_mail.keep_copy_off`, dry run first), and switch the legacy host's own spam filter off for that mailbox (`profile:legacy_mail.spam_filter_off`) when its spam folder is never forwarded. Tell the person first that new mail now appears only in Gmail. Append to an existing forward, never replace it: other automation may hang off it.
16. **Contacts** [`contacts`], copy only: export from Outlook over remote support, import into one Google Contacts label per source, named after asking the person which contacts are theirs. A POP-created .pst often holds no contacts at all: ask before naming an "own" label. On Windows, drive Outlook's object model from PowerShell 7 (Windows PowerShell 5.1 can fail with `TYPE_E_CANTLOADLIBRARY`), and stop any Outlook instance your own call started.
17. **Remote support** [`remote-support`], when the profile has `remote_support`: the organisation's kit (`profile:remote_support.windows_kit`, `profile:remote_support.mac_kit`) joins the PC or Mac to the organisation's tailnet with a single-use key (`profile:remote_support.key`, sent privately) and opens key-only SSH that the SSH server itself limits to tailnet addresses. Tell the person before a restart. Prove it with `profile:remote_support.check`, which must fail unless every check passes, including sign-in attempts that must be refused; never report access or a restriction from reading a setting.
18. **AI tools** [`ai-tools`], when the profile has `ai_tools`: follow the overlay skill.
19. **A company GitHub account** [`github`], when the profile has `github`: never the person's own account or address. Give the seat a name alias (`profile:github.address_pattern`) and its `neverSpam` filter **before** sign-up, or GitHub's codes land in Spam. The person registers with that address (username `profile:github.username_pattern`), chooses their own password, turns on two-step sign-in, is added to `profile:github.team`, accepts the invitation, and runs `gh auth login` **themselves** (never send anyone a device code to enter).
20. **Record** [`record`] each choice in the roster and any new ruling in `profile:org.decision_log`.

## Lessons, then a PR

The rule: a lessons log plus proposed fixes, never applied without the administrator's approval ([contract](./references/lessons-contract.md)).

1. **When the person gets stuck**, and once more at the end of every onboarding, append one entry per lesson to `profile:lessons.log`: step id, what they saw, the cause, the fix, the file changed, scope `generic` (true in any Google Workspace organisation) or `org`. Roles only, never names, addresses or handles.
2. **A repeat** keeps its id and adds that day's date to `seen_on`; seen twice is high priority.
3. **Make the fix and open a PR.** A `generic` lesson edits this skill (in a worktree of this marketplace's repository; nothing about any organisation may go in it). An `org` lesson edits the overlay skill, a flow or a tool in the organisation's repository. Set the lesson's `status` to `proposed` and its `pr` to the URL; `applied` once merged, `rejected` if the administrator declines.
4. Run `profile:lessons.check` before pushing.

## Writing a profile for a new organisation

Copy [`example-profile.toml`](./references/example-profile.toml) to `onboarding/profile.toml` in the organisation's repository, fill only the sections that apply, add an empty `onboarding/lessons.ndjson`, and write a thin overlay skill that names the profile and holds only what this skill does not. Check both in the repository's own local gate against the two contracts.

## Post-Execution Reflection

At the end of every onboarding, before closing:

1. **Did the person get stuck anywhere?** Each time is a lesson in the log, with the step id and what they saw in their own words.
2. **Did Google behave differently from a step here?** Write what varies (seen both ways), not only the latest run.
3. **Is the lesson generic or the organisation's?** Generic means true in any Google Workspace organisation; it edits this skill, with nothing organisation-specific in it.
4. **Is a PR open for every new lesson with a fix?** Status `proposed`, `pr` set; the administrator approves it.

Only change this skill for something that really happened, never for a guess.
