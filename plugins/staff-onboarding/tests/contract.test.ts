/**
 * The skill, its two contracts and the example profile must agree (2026-11-14). Several sessions edit the skill;
 * these checks fail the marketplace gate (repo:test) when a step id, a profile key or a contract version drifts.
 */
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const DIR = join(
	import.meta.dir,
	"..",
	"skills",
	"google-workspace-staff-onboarding",
);
const read = (f: string) => readFileSync(join(DIR, f), "utf8");
const skill = read("SKILL.md");
const profileContract = read("references/profile-contract.md");
const lessonsContract = read("references/lessons-contract.md");
const example = Bun.TOML.parse(
	read("references/example-profile.toml"),
) as Record<string, unknown>;

/** Dotted keys of every scalar or array value in a TOML table. */
function keys(o: Record<string, unknown>, prefix = ""): string[] {
	return Object.entries(o).flatMap(([k, v]) => {
		const key = prefix ? `${prefix}.${k}` : k;
		return v &&
			typeof v === "object" &&
			!Array.isArray(v) &&
			!isInlineValue(key)
			? keys(v as Record<string, unknown>, key)
			: [key];
	});
}
/** Keys whose value is itself an inline table (documented as one key). */
const isInlineValue = (key: string) => key === "chat.watch_hours";

/** Required keys: the first column of the "## Required" table. */
function requiredKeys(): string[] {
	const section =
		profileContract.split("## Required")[1]?.split("\n## ")[0] ?? "";
	return [...section.matchAll(/^\| `([a-z_.]+)`/gm)].map((m) => m[1] ?? "");
}
/** Optional keys: each "| `section` | `key`, `key` (…) |" row of "## Optional sections". */
function optionalKeys(): string[] {
	const section =
		profileContract.split("## Optional sections")[1]?.split("\n## ")[0] ?? "";
	return [...section.matchAll(/^\| `([a-z_.]+)` +\| (.+) \|$/gm)].flatMap(
		(m) => {
			const keyList = (m[2] ?? "").replace(/\([^)]*\)/g, "");
			return [...keyList.matchAll(/`([a-z_]+)`/g)].map(
				(k) => `${m[1]}.${k[1]}`,
			);
		},
	);
}

describe("staff-onboarding contracts", () => {
	test("the skill's step ids, plus conversation and tooling, are exactly the lessons contract's list", () => {
		const fromSkill = [...skill.matchAll(/\[`([a-z0-9-]+)`\]/g)].map(
			(m) => m[1] ?? "",
		);
		const line =
			lessonsContract.split("\n").find((l) => l.startsWith("Step ids:")) ?? "";
		const fromContract = [...line.matchAll(/`([a-z0-9-]+)`/g)].map(
			(m) => m[1] ?? "",
		);
		expect(new Set(fromSkill).size).toBe(fromSkill.length);
		expect([...fromSkill, "conversation", "tooling"].sort()).toEqual(
			[...fromContract].sort(),
		);
	});

	test("every profile: key the skill uses is defined in the profile contract", () => {
		const defined = new Set([...requiredKeys(), ...optionalKeys()]);
		const used = [
			...new Set(
				[...skill.matchAll(/profile:([a-z_]+(?:\.[a-z_]+)+)/g)].map(
					(m) => m[1] ?? "",
				),
			),
		];
		const sections = new Set(
			[...defined].map((k) => k.split(".").slice(0, -1).join(".")),
		);
		expect(used.filter((k) => !defined.has(k) && !sections.has(k))).toEqual([]);
	});

	test("the example profile has every required key and no key the contract does not define", () => {
		const req = requiredKeys();
		const all = new Set([...req, ...optionalKeys()]);
		const have = keys(example);
		expect(req.length).toBeGreaterThan(10);
		expect(req.filter((k) => !have.includes(k))).toEqual([]);
		expect(have.filter((k) => !all.has(k))).toEqual([]);
	});

	test("both contracts and the example name the same contract version", () => {
		const v = (t: string) =>
			/contract,? version (\d+)|contract version (\d+)/i
				.exec(t)
				?.slice(1)
				.find(Boolean);
		expect(v(profileContract)).toBe("1");
		expect(v(lessonsContract)).toBe("1");
		expect((example.schema as number).toString()).toBe(v(profileContract));
		expect(v(read("references/example-profile.toml"))).toBe(v(profileContract));
	});
});
