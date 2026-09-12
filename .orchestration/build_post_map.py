#!/usr/bin/env python3
"""Build .orchestration/post-map.json from posts-raw.json.

Adds per post: scene (image prompt), accent (dominant clay hue), excerpt
(from og:description), related (3 slugs scored by shared cats + title words),
alt (image alt text).
"""
import json, re, pathlib, html as H

ROOT = pathlib.Path(__file__).resolve().parent
SITE = ROOT.parent / "site"

SCENES = {
 "are-photo-cleaner-apps-safe": ("a sturdy mint clay shield with a small padlock standing guard in front of a neat stack of clay photo prints, one print slightly lifted as if being inspected", "mint"),
 "best-alternative-to-cleanmyphone": ("two rounded clay smartphones side by side on a small podium, the left one a little taller, a tiny triangular pennant flag planted between them", "lav"),
 "best-app-to-delete-similar-photos-iphone-free": ("a fan of near-identical clay photographs spread like playing cards, one card circled with a thick pink clay loop", "pink"),
 "best-duplicate-photo-finder-free-iphone-2026": ("an oversized clay magnifying glass hovering over two identical clay photographs, a tiny check mark floating above one", "ochre"),
 "best-free-photo-cleaner-apps-iphone-2026": ("three small clay smartphones on a winners podium with a few chunky clay coins scattered at the base", "mint"),
 "best-iphone-cleaner-app-no-subscription": ("a clay smartphone leaning against a chubby pink piggy bank with a coin slot, no coins in sight, a small green sprout beside them", "peach"),
 "best-photo-cleaner-app-iphone-2026": ("a clay smartphone wearing a tiny gold trophy hat, confetti pieces floating around it", "ochre"),
 "can-i-undo-deleting-photos-cleaner-app": ("a clay photograph hopping back out of a small clay trash bin along a dotted motion arc, the lid open", "pink"),
 "compress-videos-iphone": ("a chunky clay film clapperboard being gently pressed into a much smaller cube by two symmetric downward arrows", "lav"),
 "convert-live-photos-to-stills-iphone": ("a clay photograph with wavy motion ripple lines on its left half and a crisp flat surface on its right half, a small pause button between them", "teal"),
 "do-photo-cleaner-apps-delete-icloud-photos": ("a chubby clay cloud floating safely above a clay smartphone, photos tucked in a basket underneath the cloud, untouched", "mint"),
 "duplicate-photo-finder-iphone-free": ("two identical clay flowers in pots side by side, one tagged with a small pink check mark flag", "rose"),
 "find-blurry-photos-iphone": ("two clay photographs leaning against each other, the left one smeared and out of focus, the right one crisp with a sharp border", "lav"),
 "find-delete-duplicate-photos-iphone": ("a small clay trash bin with a twin pair of identical photographs leaning over its edge, about to drop in", "peach"),
 "find-similar-photos-on-iphone": ("a neat row of near-identical clay photographs pinned to a string with tiny clothespins, one photo slightly different from the rest", "ochre"),
 "free-up-icloud-storage-without-deleting-photos": ("a plump clay cloud sitting on a tidy stack of photographs with a round gauge beside it pointing to full, nothing leaving the stack", "mint"),
 "how-much-space-do-live-photos-take": ("a yellow clay measuring tape wrapped around a thick stack of photographs, the tape end curling up", "peach"),
 "how-to-check-iphone-storage-breakdown": ("a clay smartphone whose screen is a colorful round donut chart with chunky segments, a small magnifying glass beside it", "pink"),
 "how-to-clean-iphone-before-selling": ("a clay smartphone tucked into a gift box with a big bow on top, tiny sparkles around the lid", "lav"),
 "how-to-clean-iphone-storage-without-deleting-photos": ("a balanced clay scale: a smartphone on one side and a glass jar full of tiny photographs on the other, both sides level", "teal"),
 "how-to-clean-up-iphone-for-free": ("a clay smartphone being swept by a small broom with a few dust puffs, a single clay coin standing nearby", "mint"),
 "how-to-clean-up-iphone-photo-library-fast": ("a chunky clay stopwatch next to a tall stack of photographs with the top few photos sliding off into a tray", "ochre"),
 "how-to-clean-up-screenshots-on-iphone": ("a clay smartphone tipping forward and dropping screenshot cards into a neat clay tray below", "rose"),
 "how-to-compress-photos-on-iphone": ("a thick stack of clay photographs being pressed by a flat clay press into a much thinner stack, arrows pointing down on both sides", "pink"),
 "how-to-delete-photos-fast-on-iphone": ("a small conveyor belt carrying clay photographs toward a rounded trash bin, one photo mid-air", "lav"),
 "how-to-delete-screenshots-from-iphone": ("a marching line of clay screenshot cards walking up a tiny ramp into an open trash bin", "peach"),
 "how-to-find-burst-photos-on-iphone": ("a wide fan of clay photographs spread like a deck of cards, one card in the middle raised slightly with a tiny pink dot on it", "teal"),
 "how-to-find-duplicate-photos-on-iphone-without-app": ("a clay magnifying glass held over a smartphone showing two identical photo thumbnails, with a small crossed-out app tile beside it", "ochre"),
 "how-to-find-large-files-in-iphone-photo-library": ("a giant clay photograph on a seesaw outweighing a pile of tiny photographs on the other end", "rose"),
 "how-to-finish-photo-cleanup-in-one-session": ("a checkered finish flag planted beside a tidy shelf of labeled clay photo albums, everything squared up", "mint"),
 "how-to-manage-live-photos-iphone": ("a clay photograph with gentle ripple lines around it and a chunky pause button floating at its corner", "pink"),
 "how-to-organize-iphone-photos": ("a set of small labeled clay drawer trays, each holding neatly sorted stacks of photographs, one drawer half open", "lav"),
 "how-to-organize-thousands-of-photos-iphone": ("a tiny clay forklift stacking pallets of miniature photographs into a tall neat tower", "peach"),
 "how-to-stop-duplicate-photos-iphone": ("a rounded stop sign on a short post with two identical clay photographs bouncing off it in mid-air", "teal"),
 "how-to-use-tidybyte": ("a chunky clay hand flicking a photograph card off a smartphone screen, motion arc behind the card", "ochre"),
 "iphone-storage-full-but-no-photos": ("an overstuffed clay smartphone bulging like a stuffed suitcase, photographs squeezing out of the edges of the screen", "rose"),
 "iphone-storage-full-free-up-space": ("a suitcase-shaped clay phone with its lid open and a few items gently floating up and out, lighter and relieved", "mint"),
 "open-source-iphone-photo-cleaner": ("a clay smartphone with a small hinged lid flipped open, revealing friendly gears and a heart inside", "pink"),
 "swipe-left-right-organize-photos": ("a large arrow pointing left and a large arrow pointing right with a single photograph card caught mid-swipe between them", "lav"),
 "tidybyte-review": ("a clay magnifying glass resting over a smartphone that shows a small checklist with check marks, a pencil beside it", "peach"),
 "tidybyte-vs-gemini-photos": ("two clay smartphones facing off on a background split into a pink half and a teal half, each phone leaning toward its own side", "pink"),
 "tidybyte-vs-slidebox": ("two clay smartphones side by side, the right one with tiny sliding drawers pulling out of its screen", "teal"),
 "tidybyte-vs-smart-cleaner": ("three clay smartphones of slightly different heights standing on a podium, the middle one tallest with a small flag", "lav"),
 "tinder-for-photos-app": ("a chunky clay hand flicking a heart-topped photograph card to the right while a plain card exits to the left", "rose"),
 "why-are-there-duplicate-photos-in-my-iphone": ("a clay smartphone with a tiny conveyor belt printing pairs of identical photographs out of its screen", "ochre"),
}

STOP = set("""a an the is are to of for on in with without your you iphone ios apple app apps photo photos how why what when best free vs my i it its and or not do does delete deleting find finding clean cleaning cleaner organize organizing manage managing stop check up fast no space storage""".split())

def title_words(t):
    return {w for w in re.findall(r"[a-z0-9]+", t.lower())} - STOP

def main():
    raw = json.loads((ROOT / "posts-raw.json").read_text())
    by_slug = {p["slug"]: p for p in raw}
    slugs = set(by_slug)
    out = []
    for p in raw:
        slug = p["slug"]
        post = SITE / "blog" / f"{slug}.html"
        t = post.read_text(encoding="utf-8")
        m = re.search(r'og:description" content="([^"]+)"', t)
        excerpt = H.unescape(m.group(1)).strip() if m else ""
        if len(excerpt) > 160:
            excerpt = excerpt[:157].rsplit(" ", 1)[0].rstrip(",;:.") + "…"
        scene, accent = SCENES[slug]
        cats = set(p["cats"].split())
        tw = title_words(p["title"])
        scored = []
        for q in raw:
            if q["slug"] == slug: continue
            qc = set(q["cats"].split())
            score = 2 * len(cats & qc) + len(tw & title_words(q["title"]))
            scored.append((-score, q["slug"]))
        related = [s for _, s in sorted(scored)[:3]]
        alt = f"Clay illustration: {scene.split(',', 1)[0]}"
        out.append({**p, "excerpt": excerpt, "scene": scene, "accent": accent,
                    "related": related, "alt": alt})
    (ROOT / "post-map.json").write_text(json.dumps(out, indent=1))
    print(f"{len(out)} posts mapped")
    accents = {}
    for o in out: accents[o["accent"]] = accents.get(o["accent"], 0) + 1
    print("accent balance:", accents)
    assert all(len(o["related"]) == 3 and o["excerpt"] and o["scene"] for o in out)
    print("all related slugs resolve:",
          all(set(o["related"]) <= slugs for o in out))

if __name__ == "__main__":
    main()
