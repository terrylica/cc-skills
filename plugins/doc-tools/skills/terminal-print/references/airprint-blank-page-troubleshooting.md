# AirPrint / IPP-Everywhere Blank-Page Troubleshooting

When `lpr` reports success but **no page comes out** — or a **blank page comes out** — on an HP AirPrint / IPP-Everywhere printer (HP LaserJet Pro MFP 3101/3108 family and similar), use this playbook.

This is not theoretical: it captures the full diagnostic odyssey and the working fix from a real session (2026-05-09) where Chrome-headless PDFs, cgpdftops-converted PostScript, and even direct IPP submissions all silently dropped pages on the AirPrint queue, while a parallel **socket://IP:9100 + PostScript-PPD** queue worked first try.

---

## Symptom Signature

You're hitting this exact bug if any of the following are true:

| Observation                                                                                                                                              | Meaning                                                                                                                     |
| -------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `lpstat -o` shows queue empty within ~6 seconds                                                                                                          | Job left the local Mac spool — it's on the printer's plate now                                                              |
| `ipptool -tv ipp://localhost/jobs/<N>` returns `job-state=completed` and `job-state-reasons=processing-to-stop-point` with `job-impressions-completed=0` | Local CUPS thinks success; printer reported back that it rasterized zero pages                                              |
| Printer's own ledger (`ipptool -tv ipp://<printer>.local.:631/ipp/print` querying completed jobs) shows `impressions=0, sheets=0` for the job            | Printer received the job and dropped it before rasterization (PDF interpreter rejected)                                     |
| Printer's own ledger shows `impressions=1, sheets=0` for a plain-text job                                                                                | Printer rasterized text but the IPP `sheets` counter on this firmware **under-reports by one** — page actually did come out |
| Channel test (plain text) prints fine, but PDFs come out blank                                                                                           | Document-format-specific rejection by the firmware, not a transport issue                                                   |
| Same PDF prints fine on another machine / via another protocol                                                                                           | Confirms it's the local CUPS → AirPrint path, not the document                                                              |

The local CUPS spool will report `job-state=completed` whether the printer printed a real page, a blank page, or nothing at all. **Do not trust local CUPS as ground truth.** The only ground truths are (a) the printer's own job ledger over IPP and (b) what's physically in the output tray.

---

## Diagnostic Ladder (in order)

Run these top-to-bottom. Stop when you find the first one that explains the failure.

### 1. Is the printer reachable?

```bash
# Bonjour discovery — list nearby IPP printers
timeout 4 dns-sd -B _ipps._tcp local.

# Resolve hostname for this printer (substitute the instance name from -B)
timeout 3 dns-sd -L "HP LaserJet Pro MFP 3101-3108 [A02E22]" _ipps._tcp local.
# Look for "reached at <hostname>:<port>" in output

# Ping the resolved hostname (e.g. HP28C5C8A02E22.local.)
ping -c 2 HP28C5C8A02E22.local.
```

If unreachable: printer is asleep / off-network / DNS-SD record stale. Wake it via the front panel and retry. Skip the rest of the ladder until ping works.

### 2. Read the printer's own job ledger (NOT the local CUPS ledger)

```bash
PRINTER_HOST="HP28C5C8A02E22.local.:631"   # <-- from step 1

cat > /tmp/get-completed-jobs.test <<'EOF'
{
  OPERATION Get-Jobs
  GROUP operation-attributes-tag
  ATTR charset attributes-charset utf-8
  ATTR naturalLanguage attributes-natural-language en
  ATTR uri printer-uri $uri
  ATTR keyword which-jobs completed
  ATTR keyword requested-attributes job-id,job-state,job-state-reasons,job-impressions-completed,job-media-sheets-completed,job-name
  STATUS successful-ok
  EXPECT job-id
}
EOF

ipptool -tv "ipp://$PRINTER_HOST/ipp/print" /tmp/get-completed-jobs.test \
  | grep -E "job-(id|name|impressions-completed|media-sheets-completed)" | head -30
```

Compare your job to known-good jobs in the printer's history:

| `impressions`          | `sheets` | Interpretation                                                                      |
| ---------------------- | -------- | ----------------------------------------------------------------------------------- |
| 1+                     | 1+       | ✅ Real success                                                                     |
| 1                      | 0        | Probably success — this firmware under-reports sheets by one for some job types     |
| 0                      | 0        | ❌ Document-format rejection — printer didn't even rasterize. Skip to step 4        |
| Job not in list at all | —        | Job never reached printer. Re-check transport (Wi-Fi flapping, dnssd record stale). |

### 3. Is it a mechanical-state issue?

Send a plain-text channel test:

```bash
echo "PRINT CHANNEL TEST $(date)" | lp -d <printer-queue> -t channel-test
sleep 6
# Check the printer's ledger again — and walk to the printer
```

- Page comes out → mechanical fine, problem is document-specific (go to step 4).
- Nothing comes out, **and** the printer's ledger reports `impressions=1, sheets=0` for the channel test → genuine mechanical issue (paper out, jam, cover open). The IPP `state-reasons=none` will lie about this on this firmware family — front panel tells the truth. Look for blinking lights or error codes on the printer.

### 4. Bypass the IPP-Everywhere PDF/PWG interpreter (the real fix)

If the channel test prints but PDFs don't, the printer's IPP-Everywhere PDF interpreter is dropping the document. Do not waste time re-rendering, untagging, flattening, or version-downgrading the PDF — those won't help. Instead, **add a parallel queue that uses raw socket-9100 with a PostScript PPD**:

```bash
# Run the helper script (or do it manually below)
"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/doc-tools}/skills/terminal-print/assets/setup-socket-9100-queue.sh"
```

What that script does, manually:

```bash
# 1. Get printer IP (resolve from Bonjour)
PRINTER_IP=$(dscacheutil -q host -a name HP28C5C8A02E22.local | awk '/ip_address/{print $2; exit}')

# 2. Confirm TCP/9100 (JetDirect) listening
nc -z -v -w 3 "$PRINTER_IP" 9100   # expect "Connection ... succeeded"

# 3. Create a parallel queue with Generic PostScript PPD
lpadmin -p HP_3101_PS9100 \
  -E \
  -v "socket://$PRINTER_IP:9100" \
  -m drv:///sample.drv/generic.ppd \
  -D "HP LaserJet (PostScript over socket-9100, AirPrint bypass)"

# 4. Print to the new queue — local CUPS converts PDF→PS via cgpdftops,
#    ships raw PostScript over JetDirect, printer's PS interpreter renders it.
lp -d HP_3101_PS9100 -o media=Letter /path/to/document.pdf
```

To remove the queue later: `lpadmin -x HP_3101_PS9100`.

### 5. If even socket-9100 + PostScript fails

The cgpdftops PostScript output itself may have something the printer's PS interpreter can't render (rare). Fallbacks in order:

```bash
# (a) Convert via cupsfilter to the printer's preferred format and submit raw
cupsfilter -p HP_3101_PS9100 -m image/pwg-raster /path/to/doc.pdf > /tmp/doc.pwg
lp -d HP_3101_PS9100 -o raw /tmp/doc.pwg

# (b) Use the LaserJet PCL 4/5 PPD instead of Generic PS
lpadmin -p HP_3101_PCL9100 -E -v "socket://$PRINTER_IP:9100" -m drv:///sample.drv/laserjet.ppd

# (c) Re-render the source HTML to a simpler PDF — drop tagged PDF, drop landscape,
#     drop -webkit-print-color-adjust. Some firmware PDF interpreters reject these.
```

---

## What CUPS Will Tell You (and Why You Can't Trust It)

```bash
lpstat -o                                  # active queue — empties in seconds even on failure
ipptool -tv ipp://localhost/jobs/<N>       # local-CUPS view — says "completed" regardless
tail /var/log/cups/error_log               # default verbosity is "warn" — silent on these failures
```

The local Mac CUPS treats the IPP-Everywhere transaction as binary success/failure. If the printer's IPP server returned `successful-ok` (it does), CUPS marks `completed` and discards the job. The fact that the printer rasterized 0 pages is invisible at this layer.

**The only reliable signal from the local Mac side** is `job-state-reasons=processing-to-stop-point` paired with `job-impressions-completed=0`. That combo is the fingerprint of "AirPrint accepted the bytes and the printer ate them silently."

---

## Why This Happens

HP LaserJet Pro MFP 3101 (and the broader 3101/3108/3201/3208/3301/3308 family) ships an IPP-Everywhere implementation whose PDF interpreter has known incompatibilities. Documented externally:

- **Manjaro forum** ([forum.manjaro.org/t/.../92072](https://forum.manjaro.org/t/hp-laserjet-driverless-printing-results-in-a-blank-page/92072)) — same printer family, same blank-page symptom. Resolution: socket://IP:9100 + PostScript driver.
- **Apple CUPS issue #5002** ([github.com/apple/cups/issues/5002](https://github.com/apple/cups/issues/5002)) — unresolved upstream; workaround discussions point to direct socket submission.
- **HP support** has stopped shipping full-feature drivers for macOS (Sequoia/Tahoe), forcing reliance on AirPrint and exposing this firmware bug to all Mac users.

The firmware's PostScript Level 3 interpreter, by contrast, is reliable on this same printer — confirmed end-to-end on 2026-05-09. Use it.

---

## Quick Recipe Card (when you're sure this is what you're hitting)

```bash
# One-time setup
PRINTER_IP=192.168.0.196   # or resolve via dscacheutil
lpadmin -p HP_3101_PS9100 -E -v "socket://$PRINTER_IP:9100" -m drv:///sample.drv/generic.ppd

# Every print
lp -d HP_3101_PS9100 -o media=Letter document.pdf
```
