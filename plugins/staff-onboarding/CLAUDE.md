# staff-onboarding Plugin

> Onboard staff onto Google Workspace seats for any organisation: one generic skill, a profile per organisation, and a lessons log that turns every onboarding into proposed fixes.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../CLAUDE.md)

## Design

- **Mechanism and policy are separate.** The skill holds only what is the same in every Google Workspace organisation. Everything that differs (domain, admin tool commands, credential scopes, chat channel and languages, signing rule, roster path, legacy mail host, remote-support tailnet, GitHub org) is a key in the organisation's own `onboarding/profile.toml`, in the organisation's own repository. In software-engineering terms this is a product line: core assets plus declared variation points, applied as base plus overlay (the organisation's overlay skill wins where it differs).
- **Self-improving through an experience library.** Every onboarding writes name-free lessons to the organisation's `onboarding/lessons.ndjson`; the session makes the fix and opens a PR, which a person approves. Generic lessons come back here; organisation lessons stay in the organisation's repository. A lesson seen twice is high priority. Never auto-applied.
- **The two contracts are the definition.** [`profile-contract.md`](./skills/google-workspace-staff-onboarding/references/profile-contract.md) and [`lessons-contract.md`](./skills/google-workspace-staff-onboarding/references/lessons-contract.md). Each organisation checks its own files in its own local gate; this plugin ships no checker, so no organisation's gate depends on a plugin install path.

## Invariants (read before editing)

- **Public and organisation-free.** No organisation name, domain, person, address, chat handle, tailnet, credential scope or internal path may appear in any file here; the example profile uses `example.com` and the fictional "Acme". An organisation-specific lesson belongs in that organisation's overlay, never here.
- **Step ids are an API.** Lessons in every organisation's log refer to the bracketed step ids in `SKILL.md` § Steps. Renaming one breaks their logs; add a new id instead, and list it in `lessons-contract.md` in the same change.
- **Contract changes bump the version** in both contract files and in the example profile's header, and say what an organisation must change.
- **Each claim about Google's behaviour came from a real onboarding.** When a lesson contradicts the text (Google forced the password change on one run, not on another), write what varies, not the latest observation alone.

## Skill

- [google-workspace-staff-onboarding](./skills/google-workspace-staff-onboarding/SKILL.md)
