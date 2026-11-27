// fake-mcp-server.ts — a minimal stdio MCP server for mcp-drive.test.ts: answers initialize, and answers every
// tools/call with the text "echo:<tool name>" (the tool name "fail" returns isError).
let buf = "";
process.stdin.on("data", (d) => {
  buf += d.toString();
  for (let i = buf.indexOf("\n"); i >= 0; i = buf.indexOf("\n")) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    const m = JSON.parse(line);
    if (m.id === undefined) continue;
    const result = m.method === "tools/call"
      ? { content: [{ type: "text", text: `echo:${m.params.name}` }], isError: m.params.name === "fail" }
      : {};
    process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: m.id, result }) + "\n");
  }
});
