# App naming + icon scheme (generic template)

A reusable CONVENTION for keeping a fleet of per-concern Pushover apps scannable.
This is a TEMPLATE — your own concrete app→repo map is private (keep it in
`~/.claude/pushover-commander.private/`, not here).

## Why per-concern apps

Pushover identifies every message by its **application token**. One app per concern
(per repo / host / subsystem) makes alerts independently scoped, filterable, and
auditable — and lets each carry its own icon + default sound. Renaming an app does
NOT change its token, so renames are non-breaking.

## Naming scheme

```
<emoji> <repo-or-host> <role>
```

Keep the NAME ≤ 20 chars (an emoji counts ~2); DESCRIPTION ≤ 500.
Examples (generic): `📉 myrepo runtime`, `🖥 host01 daemon`, `🔁 fleet rotation`.

## Category palette / monogram / sound (example)

Assign each category a color (icon background via `make_app_icon.py`), a 2–4 char
monogram, and a default sound (built-in or a custom sound uploaded via
`custom-sounds`). Pick your own categories; this is illustrative:

| category         | emoji | color     | monogram | sound                 |
| ---------------- | ----- | --------- | -------- | --------------------- |
| service / app    | 📉    | `#3b82f6` | APP      | info ↑ / crit fanfare |
| host daemon      | 🖥    | `#22c55e` | HST      | piano                 |
| data pipeline    | 📡    | `#06b6d4` | DAT      | uplift                |
| fleet / rotation | 🔁    | `#8b5cf6` | FLT      | uplift                |
| network          | 🌐    | `#14b8a6` | NET      | siren                 |
| release          | 🚀    | `#f97316` | REL      | fanfare               |
| generic          | 🤖    | `#6366f1` | GEN      | default               |
| scratch / test   | 🧪    | `#6e7681` | TST      | celebrate             |

## Tooling

- `make_app_icon.py` — render a monogram + category-color PNG icon.
- `make_custom_sound.sh` / `find_jingles.sh` — source + loudness-normalize + size-fit
  free MP3 jingles (MP3 only, < 500 KB, ≤ 30 s; sweet spot ~29 s @ 128 kbps ≈ 454 KB).
- `manage-apps-and-sounds-headless` (`create-app` / `edit-app` / `add-sound`) applies
  name + icon + sound headlessly.
- `batch_create_pushover_apps.ts` — create many apps from a plan JSON in one pass.
