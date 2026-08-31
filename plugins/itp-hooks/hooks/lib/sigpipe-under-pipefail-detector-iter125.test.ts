#!/usr/bin/env bun
// # PROCESS-STORM-OK
/**
 * Tests for sigpipe-under-pipefail-detector-iter125.ts
 *
 * The NEGATIVE cases carry most of the weight here. A detector that flags every
 * pipeline would pass every positive test and be worthless — mql5's own census
 * put 70 sites across 33 of 114 scripts, so a rule that cannot tell `| head -1`
 * from `| tail -1` produces enough noise to get the hook switched off, which is
 * the failure this port exists to avoid.
 *
 * Two cases are regression tests for bugs found in the ORIGINAL gate rather than
 * invented here:
 *   - `awk '/x/{print; exit}'` (the idiomatic spelling) went unreported while
 *     four other shapes were flagged, because the first awk rule forbids `;`.
 *   - `head -n -5` reads to EOF and must NOT be flagged.
 */

import { describe, it, expect } from "bun:test";
import {
  detectSigpipeUnderPipefailSites,
  findUnquotedPipePositions,
  stripTrailingComment,
} from "./sigpipe-under-pipefail-detector-iter125.ts";

const PATH = "/tmp/example-script.sh";
const PREAMBLE = "#!/usr/bin/env bash\nset -euo pipefail\n";

function detect(body: string, path = PATH) {
  return detectSigpipeUnderPipefailSites(path, PREAMBLE + body);
}

// ============================================================================
// Gating: pipefail is what makes this a defect at all
// ============================================================================

describe("pipefail gating", () => {
  it("does not fire without pipefail, even on a textbook offender", () => {
    const content = "#!/usr/bin/env bash\nset -eu\nmoon query tasks | grep -q foo\n";
    expect(detectSigpipeUnderPipefailSites(PATH, content)).toHaveLength(0);
  });

  it("fires with `set -o pipefail` on its own line", () => {
    const content = "#!/usr/bin/env bash\nset -o pipefail\nmoon query tasks | grep -q foo\n";
    expect(detectSigpipeUnderPipefailSites(PATH, content)).toHaveLength(1);
  });

  it("treats `set +o pipefail` as a DISABLE, not an enable", () => {
    const content = "#!/usr/bin/env bash\nset +o pipefail\nmoon query tasks | grep -q foo\n";
    expect(detectSigpipeUnderPipefailSites(PATH, content)).toHaveLength(0);
  });

  it("ignores a pipeline that locally disables pipefail (the prescribed fix)", () => {
    expect(detect("x=$( set +o pipefail; producer | head -1 )\n")).toHaveLength(0);
  });

  it("ignores non-shell files entirely", () => {
    // No shebang: a .md is only a shell script by EXTENSION here. (With the
    // bash shebang it legitimately IS one — shebang detection exists so that
    // extensionless scripts like deploy/git-hooks/pre-push are covered.)
    const sites = detectSigpipeUnderPipefailSites(
      "/tmp/notes.md",
      "set -euo pipefail\nproducer | grep -q foo\n",
    );
    expect(sites).toHaveLength(0);
  });

  it("DOES cover an extensionless file carrying a bash shebang", () => {
    const sites = detectSigpipeUnderPipefailSites(
      "/repo/deploy/git-hooks/pre-push",
      PREAMBLE + "producer | grep -q foo\n",
    );
    expect(sites).toHaveLength(1);
  });
});

// ============================================================================
// Positive cases — every reader shape
// ============================================================================

describe("early-exiting readers are flagged", () => {
  it("flags grep -q", () => {
    const sites = detect("moon query tasks | grep -q '\"check-all-gates\"'\n");
    expect(sites).toHaveLength(1);
    expect(sites[0]?.reader).toBe("grep -q");
    expect(sites[0]?.producer).toBe("moon query tasks");
  });

  it("flags --quiet and --silent long forms", () => {
    expect(detect("producer | grep --quiet foo\n")).toHaveLength(1);
    expect(detect("producer | grep --silent foo\n")).toHaveLength(1);
  });

  it("flags grep -m N", () => {
    const sites = detect("producer | grep -m 1 foo\n");
    expect(sites).toHaveLength(1);
    expect(sites[0]?.reader).toBe("grep -m N");
  });

  it("flags head", () => {
    const sites = detect("find . -name '*.log' | sort -rn | head -1\n");
    expect(sites).toHaveLength(1);
    expect(sites[0]?.reader).toBe("head");
  });

  it("flags sed with a q command", () => {
    const sites = detect("producer | sed -n '1p;q'\n");
    expect(sites).toHaveLength(1);
    expect(sites[0]?.reader).toBe("sed ... q");
  });

  it("flags awk with an unquoted exit", () => {
    expect(detect("producer | awk NR==1{exit}\n").length).toBeGreaterThan(0);
  });

  it("flags the IDIOMATIC awk spelling — regression for the original gate's own gap", () => {
    const sites = detect("producer | awk '/x/{print; exit}'\n");
    expect(sites).toHaveLength(1);
    expect(sites[0]?.reader).toBe("awk ... exit");
  });

  it("flags a bare read as the final stage", () => {
    const sites = detect("producer | read line\n");
    expect(sites).toHaveLength(1);
    expect(sites[0]?.reader).toBe("read (final stage)");
  });

  it("reports the 1-based line number of the pipeline", () => {
    const sites = detect("echo one\necho two\nproducer | grep -q x\n");
    // PREAMBLE is 2 lines, then 2 echoes -> the pipeline is line 5.
    expect(sites[0]?.lineNumber).toBe(5);
  });
});

// ============================================================================
// Negative cases — readers that drain to EOF
// ============================================================================

describe("draining readers are NOT flagged", () => {
  it("does not flag tail", () => {
    expect(detect("producer | tail -1\n")).toHaveLength(0);
  });

  it("does not flag tail -n +N", () => {
    expect(detect("producer | tail -n +5\n")).toHaveLength(0);
  });

  it("does not flag sort or wc", () => {
    expect(detect("producer | sort\n")).toHaveLength(0);
    expect(detect("producer | wc -l\n")).toHaveLength(0);
  });

  it("does not flag grep WITHOUT -q or -m", () => {
    expect(detect("producer | grep foo\n")).toHaveLength(0);
    expect(detect("producer | grep -i foo\n")).toHaveLength(0);
  });

  it("does not flag awk without exit", () => {
    expect(detect("producer | awk '{print $1}'\n")).toHaveLength(0);
  });

  it("does not flag `head -n -5` / `head -c -20`, which read to EOF", () => {
    expect(detect("producer | head -n -5\n")).toHaveLength(0);
    expect(detect("producer | head -c -20\n")).toHaveLength(0);
  });

  it("does not flag a while-read consumer", () => {
    expect(detect("producer | while read -r line; do echo \"$line\"; done\n")).toHaveLength(0);
  });

  it("does not mistake `awk -v x=\"exit\"` for an exiting awk", () => {
    expect(detect("producer | awk -v x=\"exit\" '{print}'\n")).toHaveLength(0);
  });

  it("does not mistake a SHELL exit after awk for awk's own", () => {
    expect(detect("producer | awk '{print}'; exit 1\n")).toHaveLength(0);
  });
});

// ============================================================================
// Lexing: quotes, || and heredocs
// ============================================================================

describe("lexing", () => {
  it("ignores a `|` inside quotes", () => {
    expect(detect("grep -E 'a|b' file | tail -1\n")).toHaveLength(0);
    expect(findUnquotedPipePositions("grep -E 'a|b' file")).toHaveLength(0);
  });

  it("does not treat `||` as a pipe", () => {
    expect(findUnquotedPipePositions("cmd || head -1")).toHaveLength(0);
    expect(detect("cmd || head -1\n")).toHaveLength(0);
  });

  it("does not treat `|&` as a plain pipe", () => {
    expect(findUnquotedPipePositions("cmd |& head")).toHaveLength(0);
  });

  it("ignores pipelines inside a heredoc body", () => {
    const body = "cat <<EOF\nproducer | grep -q foo\nEOF\n";
    expect(detect(body)).toHaveLength(0);
  });

  it("still sees a pipeline AFTER a heredoc closes", () => {
    const body = "cat <<EOF\nsome text\nEOF\nproducer | grep -q foo\n";
    expect(detect(body)).toHaveLength(1);
  });

  it("folds a backslash continuation into one logical pipeline", () => {
    expect(detect("producer \\\n  | grep -q foo\n")).toHaveLength(1);
  });

  it("folds a trailing-pipe continuation", () => {
    expect(detect("producer |\n  grep -q foo\n")).toHaveLength(1);
  });

  it("strips trailing comments but respects quotes", () => {
    expect(stripTrailingComment("cmd # note")).toBe("cmd ");
    expect(stripTrailingComment("echo '# not a comment'")).toBe("echo '# not a comment'");
  });

  it("does not fire on a commented-out pipeline", () => {
    expect(detect("# producer | grep -q foo\n")).toHaveLength(0);
  });
});

// ============================================================================
// Escape hatches
// ============================================================================

describe("escape hatches", () => {
  it("SIGPIPE-OK on the pipeline's line suppresses it", () => {
    expect(detect("producer | grep -q foo  # SIGPIPE-OK: status unused\n")).toHaveLength(0);
  });

  it("file-wide SHELL-SAFETY-OK suppresses the whole file", () => {
    const content =
      "#!/usr/bin/env bash\n# SHELL-SAFETY-OK: legacy\nset -euo pipefail\nproducer | grep -q foo\n";
    expect(detectSigpipeUnderPipefailSites(PATH, content)).toHaveLength(0);
  });

  it("an unrelated comment does NOT suppress", () => {
    expect(detect("producer | grep -q foo  # this is fine honestly\n")).toHaveLength(1);
  });
});

// ============================================================================
// Multi-stage pipelines
// ============================================================================

describe("multi-stage pipelines", () => {
  it("attributes the producer immediately left of the offending pipe", () => {
    const sites = detect("cat f | sort -rn | head -1\n");
    expect(sites).toHaveLength(1);
    expect(sites[0]?.producer).toBe("sort -rn");
  });

  it("reports each offending stage in a pipeline with two readers", () => {
    const sites = detect("producer | grep -q a | head -1\n");
    expect(sites.length).toBeGreaterThanOrEqual(2);
  });

  it("strips a leading VAR= assignment prefix before matching the reader", () => {
    expect(detect("producer | LC_ALL=C head -1\n")).toHaveLength(1);
  });

  it("handles a pipeline inside a command substitution", () => {
    const sites = detect("first=$(producer | head -1)\n");
    expect(sites).toHaveLength(1);
    expect(sites[0]?.producer).toBe("producer");
  });
});
