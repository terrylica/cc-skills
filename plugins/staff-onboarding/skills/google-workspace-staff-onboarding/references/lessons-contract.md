# Lessons contract, version 1

The lessons log is how onboarding improves itself from the people being onboarded: an experience library, written by the session that saw the problem and turned into a reviewed change. It is `onboarding/lessons.ndjson` in the organisation's repository: tracked, one JSON object per line, **name-free** (roles, never names, addresses, chat handles or phone numbers).

## Fields (all required, no others)

| Field      | Value                                                                                           |
| ---------- | ----------------------------------------------------------------------------------------------- |
| `id`       | `L-YYYYMMDD-NN`, the day it was first recorded and a counter                                    |
| `recorded` | `YYYY-MM-DD`                                                                                    |
| `seen_on`  | Dates it happened, `YYYY-MM-DD` (or `YYYY-MM` when only the month is known); one per occurrence |
| `role`     | The person's role ("QA lead", "front desk"), never their name                                   |
| `step`     | A step id from the skill's § Steps, `conversation` or `tooling` for the rules, or `org:<slug>`  |
| `scope`    | `generic` (true in any Google Workspace organisation) or `org`; an `org:` step is always `org`  |
| `saw`      | What the person saw, in their terms (the exact message or page title where there was one)       |
| `cause`    | Why, as measured, not guessed                                                                   |
| `fix`      | What the session now says or does differently                                                   |
| `changed`  | Files the fix edits; prefix a file in this marketplace with `cc-skills:`                        |
| `status`   | `open` (no fix yet), `proposed` (PR open), `applied` (merged), `rejected` (declined)            |
| `pr`       | The PR URL, or `null`                                                                           |

Step ids: `find-seat`, `introduce`, `first-signin`, `password-change`, `2sv`, `passkey`, `backup-codes`, `shared-seat`, `shared-drives`, `mail-questions`, `legacy-mail`, `mail-copy`, `labels-filters`, `send-as`, `end-forward`, `contacts`, `remote-support`, `ai-tools`, `github`, `conversation`, `tooling`, `record`. A new step in the skill adds its id here in the same change.

## The loop

1. The person gets stuck, or the onboarding ends: the session appends the lesson (status `open`).
2. Same problem again: keep the `id`, add the date to `seen_on`. Two or more dates make it **high priority**; read and fix those first.
3. The session makes the fix and opens a PR for the administrator, never merging it itself: `generic` lessons against this skill, `org` lessons against `profile:lessons.org_target`. Status `proposed`, `pr` set.
4. Merged: `applied`. Declined: `rejected`, with the reason in `fix`.

## Rules an organisation's check should enforce

- Every line parses; every field is present and no other; ids are unique.
- `proposed` and `applied` lessons name at least one changed file.
- No email address, chat handle or phone number; on request, no word from the roster's names.
