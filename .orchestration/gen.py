#!/usr/bin/env python3
"""B2: generate 45 claymation blog images, convert, vision-QA. Idempotent.

API key comes from AGNES_KEY env var (never stored on disk).
Usage: AGNES_KEY=... python3 gen.py [--max-seconds N] [slug ...]
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
API = "https://apihub.agnes-ai.com/v1"
SRC = ROOT / "img-src"
BLOG = ROOT.parent / "site" / "assets" / "img" / "blog"
MANIFEST = ROOT / "image-manifest.json"
LOG = SRC / "gen.log"
ANCHOR = ROOT.parent / "site" / "assets" / "img" / "illustrations" / "hero-cleanup.webp"

STYLE_CLAUSE = ("Playful 3D claymation diorama in the exact same style, palette and soft "
    "studio lighting as the reference image: matte clay texture with subtle fingerprint "
    "bumps, chunky rounded forms, warm cream background (#fffaf0), gentle shadows, "
    "no outlines.")
PROMPT_TAIL = (" Square-ish balanced composition with generous margins, single subject, "
    "no text, no letters, no numbers, no logos, no watermark, no people.")
REGEN_SUFFIX = (" Previous attempt had issues; ensure absolutely no text and classic "
    "chunky clay forms.")
QA_PROMPT = ('Score this illustration for a cohesive claymation blog set. Answer STRICT '
    'JSON: {"style_match": 0-10, "has_text": true/false, "glitches": true/false, '
    '"dominant_hue": "<pink|rose|lav|peach|ochre|mint|teal|other>", "notes": "<max 15 words>"}. '
    'style_match: does it look like the same matte clay / cream background / soft light '
    'family? has_text: ANY legible text, letters or numbers. glitches: melted shapes, '
    'cut-off subject, obvious AI artifacts.')

HUES = {"pink", "rose", "lav", "peach", "ochre", "mint", "teal", "other"}
_last_api = 0.0
_use_nested_image = True  # top-level "image" → upstream 403 "Model is blocked"

def log(slug, status, verdict="-"):
    SRC.mkdir(parents=True, exist_ok=True)
    with LOG.open("a") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {slug} {status} {verdict}\n")

def pace():
    global _last_api
    wait = 3.4 - (time.time() - _last_api)
    if wait > 0:
        time.sleep(wait)
    _last_api = time.time()

def call(path, body, timeout=180):
    req = urllib.request.Request(
        API + path, data=json.dumps(body).encode(), method="POST",
        headers={"Authorization": "Bearer " + os.environ["AGNES_KEY"],
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read()), {}
    except urllib.error.HTTPError as e:
        hdrs = {k.lower(): v for k, v in e.headers.items()}
        return e.code, e.read().decode("utf-8", "replace")[:500], hdrs

def prompt_for(entry, regen):
    p = STYLE_CLAUSE + " Scene: " + entry["scene"] + ". Dominant accent color: " \
        + entry["accent"] + " (use the reference palette tints for that hue)." + PROMPT_TAIL
    return p + REGEN_SUFFIX if regen else p

def image_body(prompt):
    b64 = base64.b64encode(ANCHOR.read_bytes()).decode()
    uri = "data:image/webp;base64," + b64
    if _use_nested_image:
        return {"model": "agnes-image-2.1-flash", "prompt": prompt,
                "size": "1536x1024", "response_format": "b64_json",
                "extra_body": {"image": uri}}
    return {"model": "agnes-image-2.1-flash", "prompt": prompt,
            "size": "1536x1024", "response_format": "b64_json", "image": uri}

def generate(slug, prompt):
    """Returns (http_status, png_bytes|None). Retries per spec."""
    global _use_nested_image
    back429, back5xx = 0, 0
    while True:
        pace()
        status, resp, hdrs = call("/images/generations", image_body(prompt))
        if status == 200:
            try:
                d = resp["data"][0]
                if d.get("b64_json"):
                    return 200, base64.b64decode(d["b64_json"])
                if d.get("url"):
                    time.sleep(1)
                    with urllib.request.urlopen(d["url"], timeout=120) as r:
                        return 200, r.read()
                return 200, None
            except Exception as e:
                print(f"  decode error: {e}")
                return 200, None
        if status == 400 and "input_image" in str(resp).lower():
            print(f"  unsupported field: {str(resp)[:120]}")
            return status, None
        if status == 429:
            back429 += 1
            if back429 > 3:
                return 429, None
            try:
                ra = max(1, int(hdrs.get("retry-after", "30")))
            except (ValueError, TypeError):
                ra = 30
            print(f"  429, sleep {ra}s ({back429}/3)")
            time.sleep(ra)
            continue
        if status >= 500 or status == 0:
            back5xx += 1
            if back5xx > 2:
                return status, None
            print(f"  {status}, retry {back5xx}/2")
            time.sleep(10)
            continue
        return status, None

def convert(slugs):
    if not slugs:
        return set()
    r = subprocess.run(["python3", str(ROOT / "img.py"), *slugs],
                       capture_output=True, text=True)
    print(r.stdout.strip())
    return {ln.split()[1] for ln in r.stdout.splitlines() if ln.startswith("FAILED ")}

def qa_image(png_path):
    b64 = base64.b64encode(png_path.read_bytes()).decode()
    body = {"model": "agnes-2.5-flash", "max_tokens": 1500, "messages": [
        {"role": "user", "content": [
            {"type": "text", "text": QA_PROMPT},
            {"type": "image_url",
             "image_url": {"url": "data:image/webp;base64," + b64}}]}]}
    for attempt in range(3):
        pace()
        status, resp, _ = call("/chat/completions", body, timeout=120)
        if status == 429:
            time.sleep(30)
            continue
        if status != 200:
            time.sleep(8)
            continue
        try:
            content = resp["choices"][0]["message"]["content"]
        except Exception:
            continue
        s = content.strip()
        if s.startswith("```"):
            s = s.split("```")[1].removeprefix("json").strip()
        try:
            j = json.loads(s[s.index("{"):s.rindex("}") + 1])
        except Exception:
            if attempt == 2:
                return None
            continue
        return {
            "style_match": float(j.get("style_match", 0)),
            "has_text": str(j.get("has_text", "")).lower() in ("true", "1", "yes"),
            "glitches": str(j.get("glitches", "")).lower() in ("true", "1", "yes"),
            "dominant_hue": str(j.get("dominant_hue", "other")).strip().lower(),
            "notes": str(j.get("notes", ""))[:120],
        }
    return None

def passed(q):
    return bool(q) and q["style_match"] >= 7 and not q["has_text"] and not q["glitches"]

def save_manifest(m):
    MANIFEST.write_text(json.dumps(m, indent=1) + "\n")

def main():
    max_seconds = 420
    args = sys.argv[1:]
    if args and args[0] == "--max-seconds":
        max_seconds = int(args[1]); args = args[2:]
    posts = json.loads((ROOT / "post-map.json").read_text())
    by_slug = {p["slug"]: p for p in posts}
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else []
    mby = {m["slug"]: m for m in manifest}
    wanted = args if args else [p["slug"] for p in posts]
    deadline = time.time() + max_seconds
    stats = {"gen": 0, "ok": 0, "failed_qa": 0, "failed_api": 0, "skipped": 0}

    for slug in wanted:
        if slug not in by_slug:
            print(f"?? {slug}: not in post-map"); continue
        m = mby.get(slug)
        if m and m.get("status") in ("ok", "failed_qa", "failed_api"):
            stats["skipped"] += 1
            continue
        if time.time() > deadline:
            print(f"[budget] stopping generation at {slug}")
            break
        entry = by_slug[slug]
        png = SRC / f"{slug}.png"
        if not m:
            m = {"slug": slug, "accent": entry["accent"], "attempts": 0,
                 "style_match": None, "has_text": None, "glitches": None,
                 "dominant_hue": None, "status": "pending", "notes": ""}
            mby[slug] = m; manifest.append(m)
        if not png.exists():
            print(f"[gen] {slug}")
            st, data = generate(slug, prompt_for(entry, False))
            m["attempts"] += 1; stats["gen"] += 1
            log(slug, st, "-")
            if st != 200 or not data:
                m["status"] = "failed_api"; m["notes"] = f"http {st}"
                save_manifest(manifest)
                print(f"  FAILED_API http {st}")
                continue
            png.write_bytes(data)
        # convert + QA (fresh or resumed)
        result = None
        for regen_round in (False, True):
            failed_conv = convert([slug])
            q = qa_image(BLOG / f"{slug}.webp") if slug not in failed_conv else None
            m.update(style_match=q["style_match"] if q else None,
                     has_text=q["has_text"] if q else None,
                     glitches=q["glitches"] if q else None,
                     dominant_hue=q["dominant_hue"] if q else None)
            if q and q["dominant_hue"] in HUES and q["dominant_hue"] != entry["accent"]:
                q["notes"] = (q["notes"] + f" hue:{entry['accent']}->{q['dominant_hue']}").strip()
            if passed(q) or (regen_round and m["attempts"] >= 2):
                result = (q, regen_round)
                break
            if m["attempts"] >= 2:
                result = (q, True)
                break
            print(f"  regen (attempt {m['attempts']} failed QA): {q}")
            st, data = generate(slug, prompt_for(entry, True))
            m["attempts"] += 1; stats["gen"] += 1
            log(slug, st, "regen")
            if st != 200 or not data:
                m["status"] = "failed_api"; m["notes"] = f"regen http {st}"
                break
            png.write_bytes(data)
        if m["status"] == "failed_api":
            save_manifest(manifest); continue
        q, was_regen = result if result else (None, True)
        if passed(q):
            m["status"] = "ok"
            stats["ok"] += 1
            log(slug, "QA", f"ok {q['style_match']:.0f}")
            print(f"  OK sm={q['style_match']:.0f} hue={q['dominant_hue']}")
        else:
            m["status"] = "failed_qa"
            stats["failed_qa"] += 1
            log(slug, "QA", f"fail {q if isinstance(q, str) else (q['notes'] if q else 'qa_err')}")
            print(f"  FAILED_QA {m['notes']}")
        m["notes"] = (q["notes"] if q else m["notes"]) or m["notes"]
        save_manifest(manifest)

    # convert anything left unconverted (crash recovery, budget stop)
    leftover = [p.stem for p in SRC.glob("*.png")
                if not (BLOG / f"{p.stem}.avif").exists()]
    if leftover:
        print(f"[convert] leftover: {leftover}")
        convert(leftover)
    save_manifest(manifest)
    print(f"SUMMARY gen={stats['gen']} ok={stats['ok']} failed_qa={stats['failed_qa']} "
          f"failed_api={stats['failed_api']} skipped={stats['skipped']}")

if __name__ == "__main__":
    main()
