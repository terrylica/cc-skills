import { describe, expect, test } from "bun:test";
import { isRemoteCommand, stripLaunchWrappers } from "./readonly-command-detector.ts";

describe("isRemoteCommand sees ssh behind launch wrappers", () => {
  test.each([
    ["ssh host 'ls'", true],
    ["timeout --foreground 60 ssh -o BatchMode=yes host 'ls'", true],
    ["timeout -k 5 30s ssh host 'ls'", true],
    ["FOO=1 BAR='a b' timeout --foreground 10 ssh host ls", true],
    ["nice -n 10 ssh host ls", true],
    ["exec < /dev/null\ntimeout --foreground 60 ssh host 'ls'", true],
    ["ssh localhost ls", false],
    ["timeout 60 ssh 127.0.0.1 ls", false],
    ["timeout --foreground 60 rm -rf /tmp/x", false],
    ["echo ssh host", false],
  ])("%p -> %p", (cmd, want) => {
    expect(isRemoteCommand(cmd)).toBe(want);
  });

  test("stripLaunchWrappers leaves the launched command", () => {
    expect(stripLaunchWrappers("A=1 timeout --kill-after=5 --foreground 2m nice ssh h x")).toBe("ssh h x");
  });
});
