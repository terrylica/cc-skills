# Draft-integrity guards

> The three guards standing between a composed message and a Gmail draft, what each one is
> **observed** to do, and how each was caught not doing it.
>
> **Hub**: [gmail-commander CLAUDE.md](../CLAUDE.md)

This file replaces ten documents (~2,000 lines) written on 2026-07-28/29 that described these
guards as working. Two of the three did not work. The documents cited each other and nothing
else, so the citations read as corroboration while the whole cluster rested on nobody having run
the code. They were deleted rather than corrected — see [Why one file](#why-one-file).

## The rule these guards keep re-teaching

**A guard nobody has watched FIRE — and nobody has watched STAY SILENT on good input — is not
known to work.** Both directions, or it does not count.

Reading a guard tells you what its author intended. Only running it tells you what it does. Every
defect below was invisible to review and obvious within one execution:

| Guard                     | Believed             | Actually did                                                                                               | Found by                     |
| ------------------------- | -------------------- | ---------------------------------------------------------------------------------------------------------- | ---------------------------- |
| Layer 2 mojibake detector | blocked mojibake     | matched the **legitimate** em dash `e2 80 94` and missed real mojibake `c3 a2 c2 80 c2 94` — inverted      | running it on a good subject |
| Layer 4 read-back verify  | verified every draft | read `fetchedDraft.payload`; the API returns `{message:{payload}}` — failed open on **every** draft        | running it on a real draft   |
| Layer 3 test gate         | refused red suites   | cached on the **builder's** mtime, so a broken _test file_ took a stale "pass" hit and permitted the write | deliberately breaking a test |

Three for three. The pattern is not that these particular guards were unlucky; it is that a guard
is the one kind of code whose failure mode is silence, so "no complaints" is indistinguishable
from "not running".

## The three layers

All three hang off `hooks/gmail-draft-guard.sh` and `hooks/gmail-mojibake-detector.sh`, wired as
global `PreToolUse(Bash)` hooks in `hooks/hooks.json`.

### Layer 1 — canonical-builder enforcement (2026-07-23)

Blocks ad-hoc Gmail drafts-API writes so every draft goes through `scripts/gmail-draft.ts`.

Gmail re-encodes ingested `text/plain` and hard-folds lines at ~72 columns, so hand-rolled drafts
show forced mid-paragraph breaks in the compose window. The builder is structurally immune: it
unwraps paragraphs and emits `multipart/alternative` with a `text/html` part.

- Detection is deliberately **coarse** — any `POST|PUT|PATCH` token in a drafts-API command
  blocks. A precise regex was defeated by quote-escaping variants; a rare false positive is a
  loud pointer to the right tool, not damage.
- Read-only `GET` passes. Escape hatch: prefix with `GMAIL_DRAFT_ADHOC_OK=1`.
- **Fails open** on parse errors — advisory infrastructure must never wedge a session.

### Layer 2 — mojibake detector

Blocks draft writes whose body carries UTF-8-read-as-Latin-1 corruption (`—` → `â€"`).

The byte signature is the whole point, and getting it backwards is what made this guard worse
than useless for a day:

| Bytes               | Meaning                                                  |
| ------------------- | -------------------------------------------------------- |
| `e2 80 94`          | a **correct** UTF-8 em dash — must NOT match             |
| `c3 a2 c2 80 c2 94` | UTF-8 em dash re-encoded through Latin-1 — real mojibake |
| `c3 83 c2 ...`      | double-encoded variant                                   |

So the test is `c3 a2 c2` / `c3 83 c2`, never a bare `e2 80`. The original matched `e2 80` and
would have blocked the client draft it was written to protect.

### Layer 3 — builder test gate (2026-07-29)

Runs `bun test scripts/gmail-draft.test.ts` before permitting a draft write and **refuses on
failure**. Added because the Subject-encoding function shipped with no test at all.

- **Fails closed** on a red suite or a missing test runner. A broken builder is worse than
  blocked mail, and a missing runner is a misconfiguration worth surfacing.
- The verdict is cached so a batch of drafts does not re-run the suite per message. The cache key
  is a digest of path+size+mtime over **every** `*.ts` under `scripts/` — builder, test file, and
  every sibling module the suite imports. Keying it on the builder alone was the bug above.
- Only a **pass** is cached. A red suite is re-run every time, so the gate opens the moment it
  goes green — on evidence, not on an expiring record.
- Escape hatch: `GMAIL_DRAFT_TEST_GATE_SKIP=1`.

### Layer 4 — post-write read-back

After creating a draft, `scripts/gmail-draft.ts` fetches it back and asserts the Subject header
decodes to exactly what was asked for. This is the only layer that inspects what Gmail _stored_
rather than what we _sent_.

The Gmail `drafts.get` response nests the message: `{id, message: {payload: {headers: [...]}}}`.
Reading `fetchedDraft.payload` yields `undefined`, the header scan finds nothing, and the check
passes vacuously. It failed open on every draft it ever "verified".

## Verification log

Both directions, observed rather than inferred. Re-run these after touching any guard.

**2026-07-29 — Layer 3, all six paths:**

| #   | Input                       | Expected   | Observed   |
| --- | --------------------------- | ---------- | ---------- |
| 1   | healthy builder, cold cache | permit (0) | permit (0) |
| 2   | healthy builder, warm cache | permit (0) | permit (0) |
| 3   | **broken test, warm cache** | refuse (1) | refuse (1) |
| 4   | test restored               | permit (0) | permit (0) |
| 5   | unrelated bash command      | permit (0) | permit (0) |
| 6   | ad-hoc drafts-API POST      | block (2)  | block (2)  |

Row 3 is the one that matters: before the fingerprint fix it returned permit (0).

Reproduce:

```bash
cd ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander
P='{"tool_input":{"command":"bun scripts/gmail-draft.ts --account a --body b --from c --to d --subject e"}}'
cp scripts/gmail-draft.test.ts /tmp/gd.test.bak
printf '\ntest("temporary", () => { expect(1).toBe(2); });\n' >> scripts/gmail-draft.test.ts
echo "$P" | bash hooks/gmail-draft-guard.sh; echo "expect 1, got $?"
cp /tmp/gd.test.bak scripts/gmail-draft.test.ts          # ALWAYS restore
echo "$P" | bash hooks/gmail-draft-guard.sh; echo "expect 0, got $?"
```

**Layer 2** — assert a subject containing a real em dash passes and one containing `c3 a2 c2`
blocks. A detector that only ever sees bad input cannot tell you it is not blocking everything.

**Layer 1** — assert a drafts-API `POST` blocks and a `GET` passes.

## Why one file

The ten predecessors split by artifact (`HARDENING-ARCHITECTURE`, `HARDENING-COMPLETE`,
`HARDENING-SUMMARY`, `VERIFICATION-REPORT`, two different `HARDENING-LAYERS`, …) rather than by
reader question, so each new pass wrote a new file instead of correcting an old one, and none was
reachable from `CLAUDE.md`. Their content was also not merely redundant but **wrong**: they
asserted three working layers when two were broken.

Two of them, `scripts/LAYER1-VERIFICATION-PROOF.ts` and `test-layer1-proof.ts`, were near-identical
`console.log` scripts that no runner executed. Every property they asserted is now a real test in
`scripts/gmail-draft.test.ts`, which `bun test` runs and Layer 3 gates.

If a guard changes, change this file in the same commit, and re-run the table above.

## 2026-07-30 — the guards were right and the draft was still corrupt

A day after the hardening above, an email to the client was staged with three evidence bullets
welded into one run-on paragraph and an em dash in the subject delivered as `â€”`. Both bugs were
already fixed. Both fixes were already installed. Neither ran.

**The nine hardening commits existed in exactly one place** — the installed marketplace clone at
`~/.claude/plugins/marketplaces/cc-skills`. They were never pushed to origin and never present in the
`~/eon/cc-skills` checkout. The draft was staged by invoking the builder at the `~/eon` path, nine
commits behind, and it re-introduced both defects verbatim.

Three separate things had to be true for that to reach a client, and each is now closed:

| what failed | why it was possible | closed by |
| --- | --- | --- |
| the fix was not where the code ran | nine commits unpushed, in one directory | pushed; the working checkout is synced |
| the stale copy was invokable | the guard allowed any path ending `scripts/gmail-draft.ts` | the guard names the installed COPY, not just the filename |
| the corruption passed verification | the read-back compared bodies after collapsing whitespace | see below |

**The verification failure is the one worth internalising.** The check said `matches: True`. It
compared the staged body against the source after `" ".join(text.split())` — which collapses exactly
the newlines that had been destroyed. It could not have failed, for any input, on this defect. A
read-back that normalises away the property under test is not evidence; it is a second copy of the
assumption. Structural assertions replaced it: count the `<li>`, assert no paragraph contains `". - "`,
decode the subject and look for the mojibake marker, and list the thread to prove exactly one draft.

**The guard itself was wrong in both directions, twice, in one day.** Its write detector was
`grep -qE '(POST|PUT|PATCH)'` over the whole command: case-sensitive, so `curl -X put .../drafts`
sailed through, and substring-matching, so a read-only GET was blocked because the same line contained
`echo "…the failed PUT?"`. Blocking reads while permitting writes is worse than no guard — it trains
the operator to reach for `GMAIL_DRAFT_ADHOC_OK=1` by reflex, and then the hatch is already in their
fingers when the guard is right. Then the fix itself rejected `~/.claude/...`, the exact command the
guard's own error message prints, and blocked `bun test` on the builder. Both were caught by
dogfooding within minutes, and both are now in the probe.

`hooks/gmail-draft-guard.probe.sh` asserts 18 cases in both directions. Run it after ANY change to the
guard: `GMAIL_DRAFT_ADHOC_OK=1 bash hooks/gmail-draft-guard.probe.sh` (the hatch is required because
the probe's own argument strings would otherwise trip the guard that runs it).

**`drafts.update` was tried and rejected on evidence.** Replacing a draft in place would avoid the
window in which two drafts exist and would keep the id stable. Measured against the live account:
HTTP 200 on a standalone draft, HTTP 400 `Message not a draft` on a threaded reply, for all four
request shapes. Almost every client draft is a threaded reply. Create-then-delete stays; the delete
failure is now fatal rather than swallowed, and the thread is listed afterwards to prove exactly one
draft remains.
