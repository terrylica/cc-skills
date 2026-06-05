#!/usr/bin/env python3
"""manage-apps-and-sounds-headless — headless control of the pushover.net dashboard (things the API can't do).

Drives system Google Chrome via Playwright (channel="chrome"; no browser download).
pushover.net login is a plain email/password form with no anti-bot/CAPTCHA/2FA, so stealth
tooling (Scrapling / Obscura) is optional — see SKILL.md.

Creds from env: PO_EMAIL, PO_PW (export from resolve_pushover_secret.sh). Optional PO_USER lets create-app
exclude the user key when scraping the app's API token. Secrets are masked in output unless
--reveal is passed (needed when you actually want the new token).

Commands:
  apps                          login, list application names
  create-app --name N [--desc D] [--url U] [--reveal]   create an app, return its API token
  delete-app (--name N | --slug S)                       delete an app, verify gone
"""
import argparse
import json
import os
import re

from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

TOKRE = re.compile(r"[A-Za-z0-9]{30}")


def login(pg, email, pw):
    out = {}
    pg.goto("https://pushover.net/login", wait_until="domcontentloaded", timeout=45000)
    for s in ('input[name="email"]', 'input[type="email"]', 'input[type="text"]'):
        el = pg.query_selector(s)
        if el:
            el.fill(email)
            break
    el = pg.query_selector('input[type="password"]')
    if el:
        el.fill(pw)
    for s in ('button[type="submit"]', 'input[type="submit"]', 'button:has-text("Login")'):
        el = pg.query_selector(s)
        if el:
            el.click()
            break
    try:
        pg.wait_for_load_state("networkidle", timeout=30000)
    except PWTimeout as e:
        out["networkidle_timeout"] = str(e)[:120]
    out["url"] = pg.url
    out["logged_in"] = "/login" not in pg.url
    return out


def list_apps(pg):
    pg.goto("https://pushover.net/", wait_until="networkidle", timeout=30000)
    return sorted({(a.text_content() or "").strip()
                   for a in pg.query_selector_all('a[href^="/apps/"]') if (a.text_content() or "").strip()})


def find_app_href(pg, name):
    pg.goto("https://pushover.net/", wait_until="networkidle", timeout=30000)
    for a in pg.query_selector_all('a[href^="/apps/"]'):
        if (a.text_content() or "").strip() == name:
            return a.get_attribute("href")
    return None


def create_app(pg, name, desc, url, reveal):
    out = {"name": name}
    pg.goto("https://pushover.net/apps/build", wait_until="networkidle", timeout=30000)
    pg.fill("#application_short_name", name)
    if desc:
        pg.fill("#application_description", desc)
    if url:
        pg.fill("#application_url", url)
    pg.check("#application_terms_of_service")
    pg.click('input[name="commit"]')
    pg.wait_for_load_state("networkidle", timeout=30000)
    out["app_url"] = pg.url
    cands = set(TOKRE.findall(pg.inner_text("body")))
    for v in pg.eval_on_selector_all("input", "els=>els.map(e=>e.value||'')"):
        cands.update(TOKRE.findall(v))
    userkey = os.environ.get("PO_USER")
    if userkey:
        cands.discard(userkey)
    token = sorted(cands)[0] if cands else None
    out["created"] = token is not None
    out["token"] = (token if reveal else (f"{token[:4]}...{token[-4:]}" if token else None))
    return out


def delete_app(pg, name, slug):
    out = {}
    if not slug:
        href = find_app_href(pg, name)
        out["app_href"] = href
        if not href:
            out["error"] = "app not found by name"
            return out
        slug = href.rsplit("/", 1)[-1]
    out["slug"] = slug
    pg.goto(f"https://pushover.net/apps/edit/{slug}", wait_until="networkidle", timeout=30000)
    el = pg.query_selector('a[href^="/apps/destroy/"]')
    out["delete_control"] = bool(el)
    if el:
        el.click()  # Rails data-method=post; confirm() auto-accepted via dialog handler
        pg.wait_for_load_state("networkidle", timeout=20000)
    names = list_apps(pg)
    out["deleted"] = name not in names if name else (slug not in str(names))
    return out


def list_sounds(pg):
    pg.goto("https://pushover.net/sounds", wait_until="networkidle", timeout=30000)
    return sorted({(a.get_attribute("href") or "").rsplit("/", 1)[-1]
                   for a in pg.query_selector_all('a[href^="/sounds/edit/"]')})


def add_sound(pg, name, file_path, desc):
    out = {"name": name, "file": file_path}
    pg.goto("https://pushover.net/sounds/build", wait_until="networkidle", timeout=30000)
    pg.fill("#sound_name", name)
    if desc:
        pg.fill("#sound_description", desc)
    pg.set_input_files("#sound_sound_data_file", file_path)
    pg.click('input[name="commit"]')
    pg.wait_for_load_state("networkidle", timeout=60000)
    out["url_after"] = pg.url
    out["added"] = name in list_sounds(pg)
    if not out["added"]:
        body = pg.inner_text("body")
        out["error_hints"] = [ln.strip() for ln in body.splitlines()
                              if any(k in ln.lower() for k in ("error", "must", "size", "too", "invalid"))][:5]
    return out


def remove_sound(pg, name):
    out = {"name": name}
    pg.goto(f"https://pushover.net/sounds/edit/{name}", wait_until="networkidle", timeout=30000)
    el = pg.query_selector('a[href^="/sounds/destroy/"]') or pg.query_selector('a:has-text("Delete")')
    out["delete_control"] = bool(el)
    if el:
        el.click()  # Rails data-method=post; confirm() auto-accepted
        pg.wait_for_load_state("networkidle", timeout=20000)
    out["removed"] = name not in list_sounds(pg)
    return out


SLUGRE = re.compile(r"^/apps/[^/]+$")


def dump_apps(pg):
    """Inventory every app: name, slug, 30-char API token, description."""
    pg.goto("https://pushover.net/", wait_until="networkidle", timeout=30000)
    seen, apps = set(), []
    for a in pg.query_selector_all('a[href^="/apps/"]'):
        href = a.get_attribute("href") or ""
        name = (a.text_content() or "").strip()
        if name and SLUGRE.match(href) and "Create an" not in name:
            slug = href.rsplit("/", 1)[-1]
            if slug not in seen and slug not in ("build", "new"):
                seen.add(slug)
                apps.append({"name": name, "slug": slug})
    userkey = os.environ.get("PO_USER", "")
    for app in apps:
        pg.goto(f"https://pushover.net/apps/{app['slug']}", wait_until="networkidle", timeout=30000)
        toks = [v for v in pg.eval_on_selector_all("input", "els=>els.map(e=>e.value||'')")
                if TOKRE.fullmatch(v or "") and v != userkey]
        app["token"] = toks[0] if toks else None
        pg.goto(f"https://pushover.net/apps/edit/{app['slug']}", wait_until="networkidle", timeout=30000)
        de = pg.query_selector("#application_description")
        app["description"] = de.input_value() if de else ""
    return apps


def edit_app(pg, slug, new_name, desc, url, icon):
    """Rename / set description (<=500) / url / upload icon for an app. Slug changes on rename."""
    out = {"slug": slug}
    pg.goto(f"https://pushover.net/apps/edit/{slug}", wait_until="networkidle", timeout=30000)
    if new_name is not None:
        pg.fill("#application_short_name", new_name)
    if desc is not None:
        pg.fill("#application_description", desc[:500])
    if url is not None:
        pg.fill("#application_url", url)
    if icon:
        pg.set_input_files("#application_icon", icon)
    pg.click('input[name="commit"]')
    pg.wait_for_load_state("networkidle", timeout=60000)
    new_slug = pg.url.rsplit("/", 1)[-1] if "/apps/" in pg.url else slug
    out["new_slug"] = new_slug
    pg.goto(f"https://pushover.net/apps/edit/{new_slug}", wait_until="networkidle", timeout=30000)
    nm = pg.query_selector("#application_short_name")
    de = pg.query_selector("#application_description")
    out["name"] = nm.input_value() if nm else None
    out["desc_len"] = len(de.input_value()) if de else 0
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["apps", "dump-apps", "create-app", "delete-app", "edit-app",
                                    "list-sounds", "add-sound", "remove-sound"], nargs="?", default="apps")
    ap.add_argument("--name")
    ap.add_argument("--new-name", dest="new_name")
    ap.add_argument("--slug")
    ap.add_argument("--file")
    ap.add_argument("--icon")
    ap.add_argument("--desc", default="")
    ap.add_argument("--url", default="")
    ap.add_argument("--reveal", action="store_true")
    ap.add_argument("--headed", action="store_true")
    a = ap.parse_args()
    email, pw = os.environ["PO_EMAIL"], os.environ["PO_PW"]

    with sync_playwright() as p:
        b = p.chromium.launch(channel="chrome", headless=not a.headed)
        pg = b.new_context(viewport={"width": 1100, "height": 1700}).new_page()
        pg.on("dialog", lambda d: d.accept())
        out = login(pg, email, pw)
        if out.get("logged_in"):
            if a.cmd == "apps":
                out["apps"] = list_apps(pg)
            elif a.cmd == "dump-apps":
                out["apps_detail"] = dump_apps(pg)
            elif a.cmd == "create-app":
                if not a.name:
                    raise SystemExit("create-app requires --name")
                out.update(create_app(pg, a.name, a.desc, a.url, a.reveal))
            elif a.cmd == "delete-app":
                if not (a.name or a.slug):
                    raise SystemExit("delete-app requires --name or --slug")
                out.update(delete_app(pg, a.name, a.slug))
            elif a.cmd == "edit-app":
                slug = a.slug
                if not slug and a.name:
                    href = find_app_href(pg, a.name)
                    slug = href.rsplit("/", 1)[-1] if href else None
                if not slug:
                    raise SystemExit("edit-app requires --slug or --name")
                out.update(edit_app(pg, slug, a.new_name, a.desc or None, a.url or None, a.icon))
            elif a.cmd == "list-sounds":
                out["sounds"] = list_sounds(pg)
            elif a.cmd == "add-sound":
                if not (a.name and a.file):
                    raise SystemExit("add-sound requires --name and --file")
                out.update(add_sound(pg, a.name, a.file, a.desc))
            elif a.cmd == "remove-sound":
                if not a.name:
                    raise SystemExit("remove-sound requires --name")
                out.update(remove_sound(pg, a.name))
        b.close()
    print(json.dumps(out, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
