# Terminal Print Workflow

Detailed documentation for the terminal-print skill.

## Pipeline Architecture

````
┌─────────────────────────────────────────────────────────────────────┐
│                        INPUT (Clipboard or File)                     │
│                     pbpaste  OR  cat file.txt                        │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │      Strip ANSI Codes       │
                    │   sed 's/\x1b\[[0-9;]*m//g' │
                    └─────────────┬───────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │   Wrap in Markdown Code     │
                    │   Block with ```text        │
                    └─────────────┬───────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │   pandoc + xelatex          │
                    │   Markdown → PDF            │
                    │   (Letter, landscape,       │
                    │    DejaVu Sans Mono)        │
                    └─────────────┬───────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │   Preview in Preview.app    │
                    │   (unless --no-preview)     │
                    └─────────────┬───────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │   Confirm & Print           │
                    │   lpr → HP printer          │
                    │   (single-sided)            │
                    └─────────────────────────────┘
````

## Design Decisions

### Why Strip ANSI Instead of Converting to Colors?

1. **Target printer is B&W**: HP LaserJet Pro MFP 3101 is a monochrome printer
2. **Simpler pipeline**: No HTML intermediate, no color-to-grayscale mapping
3. **cc-skills pattern**: Follows existing Markdown → LaTeX → PDF workflow
4. **Reliability**: Avoids pandoc HTML table issues with `<br>` tags

### Why Markdown Code Blocks?

1. **Monospace rendering**: Proper character alignment for terminal output
2. **Native pandoc support**: Direct LaTeX conversion without HTML
3. **Syntax highlighting**: Optional via `--highlight-style` (not enabled by default)

### Why Landscape Orientation?

Terminal output typically has 80-120 character lines. Landscape orientation:

- Fits ~120 characters per line at 9pt font
- Reduces line wrapping
- Better matches terminal aspect ratio

## Customization

### Change Default Printer

Edit `assets/print-terminal.sh` line 19:

```bash
PRINTER="Your_Printer_Name_Here"
```

Find your printer name with: `lpstat -p -d`

### Change Font Size

Edit the pandoc command in `assets/print-terminal.sh`:

```bash
-V fontsize=9pt   # Default
-V fontsize=8pt   # Smaller (more content per page)
-V fontsize=10pt  # Larger (easier to read)
```

### Enable Syntax Highlighting

Add to the pandoc command:

```bash
--highlight-style=tango
```

Available styles: `pygments`, `tango`, `espresso`, `zenburn`, `kate`, `monochrome`

### Change Paper Size

Edit the geometry variable:

```bash
-V geometry:letterpaper,landscape   # US Letter (default)
-V geometry:a4paper,landscape       # A4 (international)
```

## Integration with cc-skills

This skill follows the cc-skills pattern established by:

- **pandoc-pdf-generation**: Universal build script pattern
- **asciinema-converter**: ANSI stripping pattern
- **Shell command portability**: Heredoc invocation for zsh compatibility

## Dual-Queue Architecture (AirPrint blank-page workaround)

This skill supports **two CUPS queues** to the same physical printer, picked at runtime via `--bypass-airprint`:

```
                                                ┌─────────────────────────────────────┐
                                                │  HP LaserJet Pro MFP 3101 (192.168) │
                                                ├─────────────────────────────────────┤
PDF ──▶ AirPrint queue (default) ──▶ dnssd:// ─▶│  IPP-Everywhere PDF interpreter     │ ✗ buggy: drops PDFs silently
        (HP_LaserJet_…AirPrint…)                │  ──────────────────────────────     │
                                                │  PostScript Level 3 interpreter     │ ✓ reliable
PDF ─cgpdftops─▶ Bypass queue ──▶ socket://9100 ┘                                     ┘
                 (HP_3101_PS9100)
                 Generic PostScript PPD
```

### Why two queues?

The HP LaserJet Pro MFP 3101/3108 family ships an IPP-Everywhere PDF interpreter that silently drops some PDFs (notably Chrome-headless landscape output with tagged structure). CUPS receives `successful-ok` from the printer's IPP server and marks the local job `completed`, while the printer rasterized zero pages. The printer's own job ledger reveals the truth — `job-impressions-completed=0`. Documented externally on Manjaro forums and Apple CUPS issue #5002.

The PostScript Level 3 interpreter on the same printer is reliable. `socket://IP:9100` (JetDirect raw print) sends pre-rasterized PostScript directly to that interpreter, bypassing the broken IPP-Everywhere path entirely.

### Setup the bypass queue (one-time)

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/terminal-print/assets/setup-socket-9100-queue.sh"
```

The script auto-discovers the printer via Bonjour, probes TCP/9100, and creates a CUPS queue named `HP_3101_PS9100` with the `Generic PostScript Printer` PPD. See [airprint-blank-page-troubleshooting.md](airprint-blank-page-troubleshooting.md) for the full diagnostic protocol.

### Diagnostic ledger — when CUPS lies

Local CUPS reports `job-state=completed` whether or not the printer actually rendered the page. The reliable signal is the **printer's own ledger** queried directly:

```bash
PRINTER_HOST="HP28C5C8A02E22.local.:631"

ipptool -tv "ipp://$PRINTER_HOST/ipp/print" - <<'EOF' | grep -E "job-(id|name|impressions-completed|media-sheets-completed)"
{
  OPERATION Get-Jobs
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri $uri
  ATTR keyword which-jobs completed
  ATTR keyword requested-attributes job-id,job-state,job-impressions-completed,job-media-sheets-completed,job-name
  STATUS successful-ok
}
EOF
```

`impressions=0, sheets=0` is the unambiguous fingerprint of "AirPrint accepted the bytes and the printer dropped them."

## Files

| File                                                | Purpose                                          |
| --------------------------------------------------- | ------------------------------------------------ |
| `SKILL.md`                                          | Skill definition and quick start                 |
| `assets/print-terminal.sh`                          | Main execution script                            |
| `assets/setup-socket-9100-queue.sh`                 | One-time setup of the AirPrint bypass queue      |
| `references/workflow.md`                            | This detailed documentation                      |
| `references/airprint-blank-page-troubleshooting.md` | Full diagnostic playbook for blank-page failures |
| `references/evolution-log.md`                       | Update history                                   |
