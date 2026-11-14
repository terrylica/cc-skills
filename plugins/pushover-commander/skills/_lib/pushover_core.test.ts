import { describe, expect, test } from "bun:test";
import { tokenFieldFor } from "./pushover_core.ts";

describe("tokenFieldFor maps --app to its credential field", () => {
  test("the two built-in apps keep their fields", () => {
    expect(tokenFieldFor("test")).toBe("api_token_test");
    expect(tokenFieldFor("main")).toBe("api_token_main");
  });

  test("a dedicated app reads api_token_<name>", () => {
    expect(tokenFieldFor("my_app")).toBe("api_token_my_app");
    expect(tokenFieldFor("my_app2")).toBe("api_token_my_app2");
  });

  test("names that could reach another field or a shell are refused", () => {
    for (const bad of ["", "user_key x", "../device", "Main", "my-app", "a;b", "x".repeat(41)]) {
      expect(() => tokenFieldFor(bad)).toThrow(/dedicated app name/);
    }
  });
});
