# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries.

---

## 2026-05-09: AirPrint blank-page workaround

**Status**: New flag `--bypass-airprint`, new helper script, new troubleshooting reference.

### What changed

- **`SKILL.md`**: Description now triggers on AirPrint/blank-page symptoms. Added `--bypass-airprint` and `--printer NAME` flags to the options table. New "Blank page came out" troubleshooting section pointing to the new reference. Default-printer description corrected — script now auto-detects via `lpstat -d` rather than hardcoding.
- **`assets/print-terminal.sh`**: Auto-detects system default printer (was hardcoded). New `--bypass-airprint` flag routes through a parallel `socket://IP:9100` queue with a Generic PostScript PPD. New `--printer NAME` override. Help text expanded. After-print message reminds the user to verify physical output, since CUPS marks `completed` regardless.
- **`assets/setup-socket-9100-queue.sh`** (new): One-shot helper that auto-discovers the HP printer via Bonjour, probes TCP/9100, and creates the bypass CUPS queue (`HP_3101_PS9100` by default). Idempotent — exits cleanly if the queue already exists.
- **`references/airprint-blank-page-troubleshooting.md`** (new): Full diagnostic playbook with the printer-side IPP ledger queries, the failure-signature decision table, the diagnostic ladder, and the manual setup recipe. Captures the lesson that `job-state=completed` from local CUPS is meaningless on AirPrint queues — the only ground truth is `job-impressions-completed` queried directly off the printer.
- **`references/workflow.md`**: New "Dual-Queue Architecture" section explaining the AirPrint vs socket-9100 split with an ASCII diagram. New "Diagnostic ledger — when CUPS lies" section with the `ipptool` query template. Files table expanded.

### Why it changed

Empirical session 2026-05-09 (Claude Code, plus user testing): printing a Chrome-headless landscape Letter PDF to the HP LaserJet Pro MFP 3101 via the default AirPrint queue silently produced no output across multiple attempts. CUPS reported `job-state=completed`. The printer's own IPP job ledger reported `job-impressions-completed=0` — diagnostic of the firmware's IPP-Everywhere PDF interpreter dropping the document. A `cupsfilter` PDF→PostScript conversion submitted via the same AirPrint queue produced a _blank_ page (printer rasterized something, but it was empty). Direct IPP submission also failed.

A parallel queue using `socket://192.168.0.196:9100` with the `Generic PostScript Printer` PPD worked first try. This matches the documented Manjaro forum fix for the same printer family ([forum.manjaro.org/.../92072](https://forum.manjaro.org/t/hp-laserjet-driverless-printing-results-in-a-blank-page/92072)) and the unresolved Apple CUPS issue #5002.

The skill previously had no awareness of this failure mode, so a Claude session debugging it had to rediscover the diagnostic protocol from scratch (~30 minutes). The update encodes the symptom signature, the printer-side ledger query, and the working fix so the next session can resolve it in seconds.

### Files affected

```
SKILL.md                                                 (modified)
assets/print-terminal.sh                                 (modified)
assets/setup-socket-9100-queue.sh                        (new)
references/workflow.md                                   (modified)
references/airprint-blank-page-troubleshooting.md        (new)
references/evolution-log.md                              (this entry)
```

### Provenance

- Real session, 2026-05-09, while printing a one-page integration-spectrum field guide for a CS-1 student.
- Failure modes observed in order: PDF rejected (`impressions=0`); cgpdftops PostScript via AirPrint produced blank page (`impressions=0` but sheet ejected blank); plain text via AirPrint printed correctly (`impressions=1, sheets=0` per IPP — counter under-reports); socket-9100 + PostScript PPD printed correctly first try.
- Affected printer firmware: HP LaserJet Pro MFP 3101fdw (and 3108/3201/3208/3301/3308 share the IPP stack).

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
