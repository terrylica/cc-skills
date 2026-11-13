# staff-onboarding

Onboard a staff member onto their Google Workspace seat through a chat conversation run by Claude Code, for any organisation.

- **One generic skill**, `google-workspace-staff-onboarding`: find the seat, first sign-in with a temporary password and one backup code, Google's password change and "Don't get locked out" page, a passkey on the person's own phone, 2-Step Verification and new backup codes, shared seats, shared drives, mail questions, finding and copying old Outlook mail, labels, filters and send-as, ending a legacy forward, contacts, remote support, a company GitHub account.
- **A profile per organisation**, `onboarding/profile.toml` in that organisation's repository, holding every value that differs: domain, admin commands, chat channel and languages, legacy mail host, tailnet, GitHub org. See the [example](./skills/google-workspace-staff-onboarding/references/example-profile.toml) and the [contract](./skills/google-workspace-staff-onboarding/references/profile-contract.md).
- **A lessons log** that turns every onboarding into proposed fixes: whenever someone gets stuck, the session records a name-free lesson and opens a pull request for review ([contract](./skills/google-workspace-staff-onboarding/references/lessons-contract.md)).

## Install

```bash
claude plugin marketplace add terrylica/cc-skills
claude plugin install staff-onboarding@cc-skills
```

Then copy the example profile into the organisation's repository as `onboarding/profile.toml`, add an empty `onboarding/lessons.ndjson`, and write a short overlay skill for the organisation's own extras.
