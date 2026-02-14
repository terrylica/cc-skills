# Evolution Log

Change history for gmail-access skill (newest first).

---

## 2026-02-04: Add Account Context Verification (Step 2.5)

**Problem**: Skill proceeded to access Gmail without verifying which account would be accessed. In multi-account setups where different projects use different Gmail accounts (via mise directory-based env vars), this could result in accessing the wrong email.

**Root cause**: Step 2 only checked if `GMAIL_OP_UUID` was set, but didn't:

1. Show which project context we're in
2. Display which email account the UUID maps to
3. Cross-reference with project expectations (e.g., `RECRUITER_EMAIL`)
4. Confirm with user before proceeding

**Fix**: Added Step 2.5 "Verify Account Context" that:

- Shows current working directory
- Shows where `GMAIL_OP_UUID` is defined in mise hierarchy
- Retrieves email address from 1Password for the UUID
- Compares against project-specific email expectations
- Requires confirmation before proceeding

**Lesson**: For any credential-based skill, always verify the credential matches the project context before use. mise's directory-based env resolution means the same env var can have different values in different projects.
