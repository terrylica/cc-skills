#!/usr/bin/env python3
"""Batch-create new Pushover apps from createnew.json: create-app (name+desc) then edit-app (icon).
Run from the _lib dir so `pushover_headless_web_control` imports. Records new tokens (last6) for the inventory."""
import json
import os

from playwright.sync_api import sync_playwright, Error as PWError
from pushover_headless_web_control import login, create_app, edit_app

EMAIL = os.environ["PO_EMAIL"]; PW = os.environ["PO_PW"]
PLAN_PATH = os.environ.get("CREATE_PLAN", "/tmp/po_sounds/createnew.json")
with open(PLAN_PATH, encoding="utf-8") as f:
    plan = json.load(f)

results = []
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", headless=True)
    pg = b.new_context(viewport={"width": 1100, "height": 1700}).new_page()
    pg.on("dialog", lambda d: d.accept())
    login(pg, EMAIL, PW)
    for item in plan:
        try:
            r = create_app(pg, item["new_name"], item["desc"], "", True)  # reveal=True -> full token
            slug = r.get("app_url", "").rsplit("/", 1)[-1]
            token = r.get("token") or ""
            icon = item.get("icon")
            iconed = False
            if slug and icon and os.path.exists(icon):
                edit_app(pg, slug, None, None, None, icon)
                iconed = True
            results.append({"name": item["new_name"], "created": r.get("created"),
                            "slug": slug, "token_last6": token[-6:] if token else None, "icon": iconed})
        except (PWError, OSError) as e:
            results.append({"name": item["new_name"], "error": str(e)[:140]})

print(json.dumps(results, indent=2, ensure_ascii=False))
print(f"\ncreated {sum(1 for r in results if r.get('created'))}/{len(plan)}")
