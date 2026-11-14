# Profile contract, version 1

An organisation's onboarding profile is `onboarding/profile.toml` in its own repository: every value the skill needs that differs between organisations (its variation points). It is tracked, so it holds **roles, seats, paths and command templates only**; who holds which seat lives in the git-ignored roster it points to. A section left out means the steps that use it do not apply. [Example](./example-profile.toml).

Command templates use `{placeholder}` names the skill fills per person: `{seat}`, `{dm_chat}` (the private chat), `{first_name}`, `{name}`, `{alias}`, `{address}`, `{sender_name}`, `{labels}`, `{filters_json}`, `{candidates}`, `{hostname}`, `{pubkey}`, `{local}`, `{forum}`, `{member_json}`, `{flow_json}`, `{run_dir}`, `{commands}`.

## Required

| Key                      | Meaning                                                                   |
| ------------------------ | ------------------------------------------------------------------------- |
| `schema`                 | `1`                                                                       |
| `org.key`                | Short slug of the organisation                                            |
| `org.domain`             | The Workspace primary domain                                              |
| `org.overlay_skill`      | Path of the organisation's own skill, which wins where it differs         |
| `org.decision_log`       | Where new rulings are recorded                                            |
| `roster.people`          | Git-ignored roster: who holds which seat                                  |
| `admin.spec`             | Command printing the admin tool's machine-readable command list           |
| `chat.channel`           | The chat the conversation runs in (for example `telegram`)                |
| `chat.footer_context`    | Context string for the Claude Code footer of every message                |
| `chat.languages`         | BCP 47 tags, every message carries each one side by side                  |
| `lessons.log`            | Path of the lessons log ([contract](./lessons-contract.md))               |
| `lessons.check`          | Command that checks the profile and the log (the organisation's own gate) |
| `lessons.generic_target` | Where generic lessons are proposed: this skill                            |
| `lessons.org_target`     | Where organisation lessons are proposed: usually the overlay skill        |

## Optional sections

| Section          | Keys                                                                                                                                                                                                                                                                                                            |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `org`            | `display_name`, `operator_name` (how staff name the administrator; used only where a text must), `admin_contact` (short name in bot texts)                                                                                                                                                                      |
| `roster`         | `access_model` (tracked model of departments, seats and drives)                                                                                                                                                                                                                                                 |
| `admin`          | Command templates: `batch` (wrap several calls in one credential read), `check`, `first_signin`, `backup_code`, `alias_add`, `labels`, `send_as`, `filters`, `drives_domain_only`, `login_audit`                                                                                                                |
| `security`       | `two_step_enforced_ou`, `passkey_required`, `skip_password_on_shared_seat`, `shared_seat_password_share`                                                                                                                                                                                                        |
| `chat`           | `send_as` (which account or profile sends), `name_signature` (false: no name line in chat), `workspace` (`forum` or `group`), `forum_title`, `secrets_channel`, `reply_watch`, `watch_hours` (`{ days = ["Mon", …], start = "09:00", end = "17:00", utc_offset = "-07:00" }`: the only hours a watcher may run) |
| `chat.bot`       | `handle`, `vault_scope`, `flows_dir` (tracked, name-free question flows), `member_dir` (git-ignored, per person), `run`, `one_run_per_token`                                                                                                                                                                    |
| `legacy_mail`    | `host`, `kind` (`pop-to-pst`, `imap`, `none`), `forward_target`, `keep_copy_off`, `spam_filter_off`, `alias_forward`                                                                                                                                                                                            |
| `remote_support` | `tailnet`, `key`, `check`, `policy`, `windows_kit`, `mac_kit`, `mac_env`, `hostname_pattern`                                                                                                                                                                                                                    |
| `github`         | `org`, `team`, `username_pattern`, `address_pattern`                                                                                                                                                                                                                                                            |
| `ai_tools`       | Organisation-defined; the overlay skill owns the steps                                                                                                                                                                                                                                                          |

## Rules an organisation's check should enforce

- Every required key is present; every path key that names a tracked file exists.
- Every `admin.*` command uses a subcommand the admin tool's own `spec` lists.
- No secret value anywhere: commands name vault scopes, never values.
- A new key is added here first (this contract is the definition), then in the organisation's profile and check.
