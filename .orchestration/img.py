#!/usr/bin/env python3
"""Convert raw generated PNGs into the blog image variants.

Input : .orchestration/img-src/<slug>.png   (raw model output, any aspect)
Output: site/assets/img/blog/<slug>.avif        1400w, q55  (article hero)
        site/assets/img/blog/<slug>.webp        1400w, q82  (article fallback)
        site/assets/img/blog/<slug>-card.webp    640w, q80  (hub thumbnail)
        site/assets/img/blog/<slug>-og.jpg    1200x630 crop (social card)

Usage: python3 img.py            # process every PNG in img-src/
       python3 img.py slug-a ... # process specific slugs
Exits non-zero if any slug fails, printing FAILED lines.
"""
import subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "img-src"
OUT = ROOT.parent / "site" / "assets" / "img" / "blog"
OUT.mkdir(parents=True, exist_ok=True)

VARIANTS = [
    (["-resize", "1400x", "-quality", "55"], ".avif"),
    (["-resize", "1400x", "-quality", "82"], ".webp"),
    (["-resize", "640x", "-quality", "80"], "-card.webp"),
    (["-resize", "1200x630^", "-gravity", "center", "-extent", "1200x630",
      "-quality", "82"], "-og.jpg"),
]

def convert(png: pathlib.Path):
    for extra, suffix in VARIANTS:
        dest = OUT / f"{png.stem}{suffix}"
        r = subprocess.run(["magick", str(png), *extra, str(dest)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError(f"{dest.name}: {r.stderr.strip()[:300]}")

def main():
    wanted = set(sys.argv[1:])
    pngs = sorted(p for p in SRC.glob("*.png") if not wanted or p.stem in wanted)
    if wanted:
        missing = wanted - {p.stem for p in pngs}
        if missing:
            print("MISSING SRC:", ", ".join(sorted(missing)))
    if not pngs:
        print("nothing to do")
        return 1
    failed = []
    for p in pngs:
        try:
            convert(p)
            outs = [OUT / f"{p.stem}{s}" for _, s in VARIANTS]
            print(f"OK {p.stem}: " +
                  " ".join(f"{o.name}={o.stat().st_size//1024}KB" for o in outs))
        except Exception as e:
            failed.append(p.stem)
            print(f"FAILED {p.stem}: {e}")
    print(f"\n{len(pngs) - len(failed)}/{len(pngs)} converted")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
