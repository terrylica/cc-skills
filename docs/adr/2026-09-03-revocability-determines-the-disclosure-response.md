# Revocability, not severity, decides whether a disclosure warrants a history rewrite

- **Status**: Accepted
- **Date**: 2026-09-03
- **Context**: This repository carried two live doctrines prescribing opposite responses to published sensitive content, with nothing reconciling them. [`2026-08-22-leaked-credential-response-rotate-not-rewrite.md`](./2026-08-22-leaked-credential-response-rotate-not-rewrite.md) says "Do not rewrite git history. No `filter-repo`, no BFG, no force-push." The header comment of [`scripts/pii-staged-content-guard.ts`](../../scripts/pii-staged-content-guard.ts) records that a PII incident's "Remediation cost a `git filter-repo` rewrite of 3,890 commits and 1,021 tags, a force-push, and a GitHub Support request that is still open". Both are accurate. Neither points at the other, so whoever handles the next incident inherits whichever document they happen to read first — and the two lead to opposite actions on the worst day to be guessing.

## Decision

**The response is determined by whether the disclosed value is REVOCABLE, not by how bad it feels.**

**Revocable — rotate, never rewrite.** API keys, tokens, passwords, certificates, session cookies. The issuer can invalidate the value, and once invalidated the published bytes are inert. A history rewrite buys nothing here because rotation has already delivered the entire security property, while the rewrite still costs every consumer their clone and every pinned SHA its validity. Follow the 2026-08-22 ADR unchanged.

**Irrevocable — removal is the only lever, so a rewrite may be justified.** A person's name, a client identity, a home address, a private email, a medical or legal detail. Nobody can issue a replacement that makes the published value worthless; the subject cannot "rotate" who they are. Removal is therefore the only mechanism that reduces exposure at all, which is why the 2026-08-24 PII incident was judged to warrant the rewrite that the credential ADR forbids.

**But state the limit honestly, because it is the part most likely to be forgotten under pressure.** A rewrite does not un-publish. Forks are independent repositories, GitHub retains unreachable objects until a Support request prunes them, scanners and clones that already indexed the content keep it, and installed marketplace caches on other machines are untouched. A rewrite reduces the surface; it never clears it. If a rewrite is chosen it must be described as mitigation, never as remediation, and the disclosure to the affected party must not imply the content was recalled.

## Consequences

- The two existing documents now cross-reference this one, so either entry point reaches the distinction.
- **Prevention is where the leverage is, and this ADR does not change that.** `pii-staged-content-guard.ts` fails the commit rather than warning precisely because the post-hoc options are all bad. This ADR only decides which bad option applies once prevention has already failed.
- A mixed disclosure — a credential and a personal identifier in the same commit — takes the irrevocable path for the identifier AND rotation for the credential. They are independent obligations, not alternatives.
- **The bar for the irrevocable path is still high and gets higher with time.** Content published across many releases and installed into consumer caches is materially harder to reduce, and each additional release lowers the ratio of benefit to breakage. Weigh the age and reach of the disclosure, not only its category.
