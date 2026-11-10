import { expect, test } from "bun:test";
import { UsageError } from "../../lib/args.ts";
import { EDIT, LABEL, URL, wantFromFlags } from "./passwordless.ts";

test("--allow-skip maps to the wanted checkbox state", () => {
  expect(wantFromFlags({ "allow-skip": "on" })).toBe(true);
  expect(wantFromFlags({ "allow-skip": "off" })).toBe(false);
});

test("ensure without --allow-skip is a usage error", () => {
  expect(() => wantFromFlags({})).toThrow(UsageError);
});

test("the page constants are the measured ones (2026-11-10)", () => {
  expect(URL).toBe(
    "https://admin.google.com/ac/managedsettings/352555445522/passwordless",
  );
  expect(LABEL).toBe(
    "Allow users to skip their password and authenticate with a passkey",
  );
  expect(EDIT).toBe("Edit Skip passwords");
});
