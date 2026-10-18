/**
 * Tests for lib/shell-heredoc-data.ts: which heredoc bodies are data a guard may ignore.
 *
 * Run with: bun test plugins/itp-hooks/hooks/lib/shell-heredoc-data.test.ts
 */

import { describe, expect, test } from "bun:test";

import { stripDataHeredocBodies } from "./shell-heredoc-data.ts";

const GATED = "cd wt && gh pr ready 12";

describe("data bodies are removed", () => {
  test.each([
    [`cat > /tmp/notes.md <<'EOF'\n${GATED}\nEOF`],
    [`git commit -F - <<'EOF'\nfix: mention ${GATED}\nEOF`],
    [`tee /tmp/a.txt >/dev/null <<EOF\n${GATED}\nEOF`],
  ])("%s", (command) => {
    expect(stripDataHeredocBodies(command)).not.toContain("gh pr ready");
  });
});

describe("bodies that will run are kept (found in review)", () => {
  test.each([
    [`bash <<'EOF'\n${GATED}\nEOF`],
    [`cat <<'EOF' | bash\n${GATED}\nEOF`],
    [`cat > /tmp/s.sh <<'EOF'\n${GATED}\nEOF\nbash /tmp/s.sh`],
    [`ssh host sh <<'EOF'\n${GATED}\nEOF`],
  ])("%s", (command) => {
    expect(stripDataHeredocBodies(command)).toContain("gh pr ready");
  });
});
