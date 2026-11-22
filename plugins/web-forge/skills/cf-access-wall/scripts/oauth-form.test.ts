// Tests of oauth-form.mjs: the GitHub "New OAuth App" field picker against the form's shape before and after
// GitHub's 2026-11-16 rename of the callback field. No browser is started.
import { describe, expect, test } from "bun:test";
import { isFillable, pickField, selectorFor } from "./oauth-form.mjs";

type Control = { tag: string; type: string; name: string | null; id: string | null; label: string };

// The form until 2026-11 (the names the forge used to fill by exact match).
const FORM_2026_07: Control[] = [
  { tag: "input", type: "text", name: "oauth_application[name]", id: "oauth_application_name", label: "Application name" },
  { tag: "input", type: "text", name: "oauth_application[url]", id: "oauth_application_url", label: "Homepage URL" },
  { tag: "textarea", type: "textarea", name: "oauth_application[description]", id: "oauth_application_description", label: "Application description" },
  { tag: "input", type: "text", name: "oauth_application[callback_url]", id: "oauth_application_callback_url", label: "Authorization callback URL" },
  { tag: "input", type: "checkbox", name: "oauth_application[device_flow_enabled]", id: "oauth_application_device_flow_enabled", label: "Enable Device Flow" },
];

// The form read on 2026-11-16 (read-only probe of /settings/applications/new): the callback is a "Redirect URI"
// list with a hidden _destroy and a wildcard checkbox per row.
const ROW = "oauth_application[application_callback_urls_attributes][0]";
const FORM_2026_11: Control[] = [
  { tag: "input", type: "text", name: "oauth_application[name]", id: "oauth_application_name", label: "Application name" },
  { tag: "input", type: "text", name: "oauth_application[url]", id: "oauth_application_url", label: "Homepage URL" },
  { tag: "textarea", type: "textarea", name: "oauth_application[description]", id: "oauth_application_description", label: "Application description" },
  { tag: "input", type: "hidden", name: `${ROW}[_destroy]`, id: "oauth_application_application_callback_urls_attributes_0__destroy", label: "" },
  { tag: "input", type: "text", name: `${ROW}[url]`, id: "oauth_application_application_callback_urls_attributes_0_url", label: "Redirect URI" },
  { tag: "input", type: "hidden", name: `${ROW}[matching_strategy]`, id: null, label: "Allow wildcard matching" },
  { tag: "input", type: "checkbox", name: `${ROW}[matching_strategy]`, id: "oauth_application_application_callback_urls_attributes_0_matching_strategy", label: "Allow wildcard matching" },
  { tag: "input", type: "hidden", name: "oauth_application[device_flow_enabled]", id: null, label: "Enable Device Flow" },
  { tag: "input", type: "checkbox", name: "oauth_application[device_flow_enabled]", id: "oauth_application_device_flow_enabled", label: "Enable Device Flow" },
  { tag: "input", type: "hidden", name: "oauth_application[token_expiration]", id: null, label: "Expire user access tokens" },
  { tag: "input", type: "checkbox", name: "oauth_application[token_expiration]", id: "oauth_application_token_expiration", label: "Expire user access tokens" },
];

describe("GitHub OAuth app form fields", () => {
  test("the 2026-07 form: every field by its label", () => {
    expect(pickField(FORM_2026_07, "name").name).toBe("oauth_application[name]");
    expect(pickField(FORM_2026_07, "homepage").name).toBe("oauth_application[url]");
    const cb = pickField(FORM_2026_07, "callback");
    expect(cb.name).toBe("oauth_application[callback_url]");
    expect(cb.matchedBy).toBe("label");
  });

  test("the 2026-11-16 form: the callback is the first Redirect URI row, never its hidden or checkbox siblings", () => {
    const cb = pickField(FORM_2026_11, "callback");
    expect(cb.name).toBe(`${ROW}[url]`);
    expect(cb.type).toBe("text");
    expect(cb.matchedBy).toBe("label");
    expect(pickField(FORM_2026_11, "name").id).toBe("oauth_application_name");
    expect(pickField(FORM_2026_11, "homepage").id).toBe("oauth_application_url");
  });

  test("a relabelled field is still found by the rename-tolerant name pattern", () => {
    const relabelled = FORM_2026_11.map((c) => (c.label === "Redirect URI" ? { ...c, label: "Callback addresses" } : c));
    const cb = pickField(relabelled, "callback");
    expect(cb.name).toBe(`${ROW}[url]`);
    expect(cb.matchedBy).toBe("name");
  });

  test("two Redirect URI rows: refuses to guess", () => {
    const row1 = { ...FORM_2026_11[4], name: `${ROW.replace("[0]", "[1]")}[url]`, id: "row1_url" };
    expect(() => pickField([...FORM_2026_11, row1], "callback")).toThrow(/^2 fields match the callback label .*refusing to guess$/);
  });

  test("no matching field: says the form changed and where to fix it", () => {
    const noCallback = FORM_2026_11.filter((c) => c.label !== "Redirect URI");
    expect(() => pickField(noCallback, "callback")).toThrow(/no callback field.*OAUTH_APP_FIELDS.*Vendor Quirks/);
    expect(() => pickField(FORM_2026_11, "nope")).toThrow(/unknown OAuth app field/);
  });

  test("only text-like inputs and textareas are fillable", () => {
    expect(FORM_2026_11.filter(isFillable).map((c) => c.label)).toEqual(["Application name", "Homepage URL", "Application description", "Redirect URI"]);
  });

  test("selectors: the id when present, else tag and exact name, quotes escaped", () => {
    expect(selectorFor({ tag: "input", name: `${ROW}[url]`, id: "a_b" })).toBe('[id="a_b"]');
    expect(selectorFor({ tag: "input", name: `${ROW}[url]`, id: null })).toBe(`input[name="${ROW}[url]"]`);
    expect(selectorFor({ tag: "input", name: 'x"y', id: null })).toBe('input[name="x\\"y"]');
    expect(() => selectorFor({ tag: "input", name: null, id: null, label: "x" })).toThrow(/neither id nor name/);
  });
});
