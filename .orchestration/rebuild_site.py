#!/usr/bin/env python3
"""Rebuild the 51 marketing-site pages from version-controlled inputs.

Context: the hand-applied clay rewrite of site/*.html + site/blog/*.html was
lost (uncommitted working tree reverted). Everything needed to regenerate it
survives: .orchestration/landing/* fragments (homepage, byte-identical to the
lost index.html), .orchestration/post-map.json (per-post data), HEAD post
bodies (kept verbatim per DECISIONS.md unless a claim rewrite applies), and
the design-token CSS + JS which were never lost.

Inputs (all committed or untracked-safe — rerunnable any time):
  HEAD bodies via `git show HEAD:<path>`  (post/utility/hub prose)
  .orchestration/landing/02-header.html + 12-footer.html (canonical chrome)
  .orchestration/landing/01,03-11 (homepage sections)
  .orchestration/post-map.json (slug/title/cats/date/read_min/excerpt/related/alt)

Outputs: site/index.html, site/404.html, site/privacy.html, site/support.html,
  site/changelog.html, site/blog/index.html, site/blog/<45 keepers>.html

Usage: python3 .orchestration/rebuild_site.py [--check]
  --check: regenerate to memory and diff against disk (CI guard).
"""
import html as H
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
ORCH = ROOT / ".orchestration"
LAND = ORCH / "landing"
CHECK = "--check" in sys.argv

CANON = "https://tidybyte.360ghar.com"
APP_URL = "https://apps.apple.com/in/app/tidybyte/id6775769763"
GITHUB = "https://github.com/360ghar/snap-clean-ios"

MAP = json.loads((ORCH / "post-map.json").read_text())
BY_SLUG = {p["slug"]: p for p in MAP}
CAT_LABELS = {"features": "Features", "privacy": "Privacy", "reviews": "Reviews",
              "storage": "Storage", "tutorials": "Tutorials", "comparisons": "Comparisons"}
CHIP_ORDER = ["all", "tutorials", "comparisons", "features", "storage", "privacy", "reviews"]

HEADER_FRAG = (LAND / "02-header.html").read_text()
FOOTER_FRAG = (LAND / "12-footer.html").read_text()


def head_version(path):
    """File content at HEAD (pre-rewrite body source)."""
    return subprocess.run(["git", "show", f"HEAD:{path}"],
                          cwd=ROOT, capture_output=True, text=True).stdout


# ---------------------------------------------------------------- token map

TOKEN_MAP = [
    ("glass-card", "clay-card"),
    ("text-zinc-100", "text-ink"),
    ("text-zinc-200", "text-ink"),
    ("text-zinc-300", "text-body"),
    ("text-zinc-400", "text-muted"),
    ("text-zinc-500", "text-muted"),
    ("text-zinc-600", "text-muted"),
    ("text-white", "text-ink"),
    ("hover:text-white", "hover:text-ink"),
    ("hover:text-zinc-100", "hover:text-ink"),
    ("hover:text-zinc-200", "hover:text-ink"),
    ("hover:text-zinc-300", "hover:text-ink"),
    ("hover:text-accent", "hover:text-ink"),
    ("text-accent", "link"),
    ("border-white/5", "border-hairline"),
    ("border-white/10", "border-hairline"),
    ("border-white/20", "border-hairline-strong"),
    ("hover:border-white/20", "hover:border-hairline-strong"),
    ("hover:bg-white/5", "hover:bg-surface-card"),
    ("bg-white/[0.02]", "bg-surface-soft"),
    ("marker:text-zinc-500", "marker:text-muted"),
    ("text-zinc-700", "text-muted"),
    ("bg-white/10", "bg-surface-card"),
    ("bg-accent", "bg-clay-pink"),
    ("divide-white/5", "divide-hairline"),
    ("divide-white/10", "divide-hairline"),
    ("bg-white/5", "bg-surface-card"),
    ("placeholder-zinc-500", "placeholder:text-muted"),
    ("focus:border-accent/60", "focus:border-clay-pink/60"),
    ("focus:ring-accent/40", "focus:ring-clay-pink/40"),
    ("bg-card-glass", "bg-surface-card"),
    ("shadow-glass", "shadow-card"),
    ("bg-accent/15", "bg-clay-pink/15"),
    ("text-green-400", "text-success"),
    ("focus:bg-accent", "focus:bg-primary"),
    ("focus:text-white", "focus:text-on-primary"),
]
# longest first so hover: variants win over bare ones
TOKEN_MAP.sort(key=lambda kv: -len(kv[0]))

OLD_TOKENS = [r"glass-card", r"zinc-", r"!text-", r"hover:text-white",
              r"text-accent", r"bg-accent", r"green-400", r"white/5", r"white/10",
              r"white/20", r"bg-white/\[", r"text-white(?![/\w])"]

# Consolidated-post redirects (F8): bodies still link the deleted slugs.
LINK_FIXES = [
    ("/blog/swipe-to-clean-photos-iphone", "/blog/how-to-organize-thousands-of-photos-iphone"),
    ("/blog/how-to-free-up-iphone-storage-without-deleting",
     "/blog/how-to-clean-iphone-storage-without-deleting-photos"),
    ("/blog/photo-cleaner-app-no-subscription", "/blog/best-iphone-cleaner-app-no-subscription"),
]
# …on the keeper page itself that first rule would self-link; point at the
# sibling swipe guide instead.
SELF_LINK_FIX = ('<a href="/blog/how-to-organize-thousands-of-photos-iphone" class="link hover:underline">how swipe-to-clean works on iPhon',
                 '<a href="/blog/swipe-left-right-organize-photos" class="link hover:underline">how swipe-to-clean works on iPhon')


def fix_links(text):
    for old, new in LINK_FIXES:
        text = text.replace(old, new)
    return text


CLAIM_FIXES = [
    ("has no backend, no analytics, and no network calls of any kind",
     "has no backend, no analytics SDK, and no tracking"),
    ("There are no network calls, no tracking SDKs, and no telemetry of any kind.",
     "There is no analytics SDK, no backend, and no tracking of any kind."),
    ("verify that no network calls are made",
     "verify that no analytics SDK, backend, or tracking is present"),
    ("no network calls of any kind", "no analytics SDK, no backend, no tracking"),
    ("clear in one tap", "clear them in one pass"),
]

CHEV = ('<svg aria-hidden="true" focusable="false" width="18" height="18" '
        'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" '
        'stroke-linecap="round" stroke-linejoin="round" class="faq-chev">'
        '<path d="m6 9 6 6 6-6"/></svg>')


def migrate_classes(html):
    """Whole-token class replacement inside class=\"...\" attributes."""

    def sub(m):
        toks = m.group(1).split()
        out = []
        for t in toks:
            for old, new in TOKEN_MAP:
                if t == old:
                    t = new
                    break
            out.append(t)
        return 'class="' + " ".join(out) + '"'

    return re.sub(r'class="([^"]+)"', sub, html)


def emdash_body(page):
    """Raw U+2014 -> &mdash; in body text nodes (tags/attrs untouched)."""
    m = re.search(r"<body>(.*)</body>", page, re.S)
    if not m:
        return page
    inner = m.group(1)
    parts = re.split(r"(<[^>]*>)", inner)
    for i in range(0, len(parts), 2):
        parts[i] = parts[i].replace("\u2014", "&mdash;")
    return page[:m.start(1)] + "".join(parts) + page[m.end(1):]


def fix_claims(text, soften=True):
    for old, new in CLAIM_FIXES:
        text = text.replace(old, new)
    if not soften:
        return text
    # "100% on-device" kept once per page: soften repeats to "on your device"
    parts = re.split(r"(100% on-device|100% on your device)", text)
    seen = 0
    for i in range(1, len(parts), 2):
        seen += 1
        if seen > 1:
            parts[i] = "on your device"
    return "".join(parts)


def emdashes(text):
    """Raw U+2014 -> &mdash; in text nodes of prose elements only."""

    def sub_text(m):
        tag, inner, close = m.group(1), m.group(2), m.group(3)
        if "<" in inner:
            return m.group(0)
        return tag + inner.replace("\u2014", "&mdash;") + close

    return re.sub(r"(<(?:p|li|h1|h2|h3|td|th|span|a|summary|figcaption|blockquote|time)[^>]*>)([^<>]*)(</(?:p|li|h1|h2|h3|td|th|span|a|summary|figcaption|blockquote|time)>)",
                  sub_text, text)


def strip_tags(s):
    s = re.sub(r"<[^>]+>", "", s)
    return H.unescape(s).strip()


def long_date(iso):
    y, m, d = (int(x) for x in iso.split("-"))
    return date(y, m, d).strftime("%B %-d, %Y")


# ---------------------------------------------------------------- head

def build_head(*, title, description, og_type, url, image, img_w, img_h,
               extra_scripts=(), preload=None, keep_jsonld=()):
    title_esc = title.replace("\u2014", "&mdash;")
    desc_esc = description.replace("\u2014", "&mdash;")
    lines = [
        "<!doctype html>", '<html lang="en">', "<head>",
        '  <meta charset="utf-8">',
        f"  <title>{title_esc}</title>",
        f'  <meta name="description" content="{desc_esc}">',
        '  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
        '  <meta name="theme-color" content="#fffaf0">',
        '  <meta name="robots" content="index, follow">',
        '  <meta name="author" content="TidyByte">',
        "",
        f'  <meta property="og:type" content="{og_type}">',
        '  <meta property="og:site_name" content="TidyByte">',
        '  <meta property="og:locale" content="en_US">',
        f'  <meta property="og:title" content="{title_esc}">',
        f'  <meta property="og:description" content="{desc_esc}">',
        f'  <meta property="og:image" content="{image}">',
        f'  <meta property="og:image:width" content="{img_w}">',
        f'  <meta property="og:image:height" content="{img_h}">',
        f'  <meta property="og:url" content="{url}">',
        "",
        '  <meta name="twitter:card" content="summary_large_image">',
        f'  <meta name="twitter:title" content="{title_esc}">',
        f'  <meta name="twitter:description" content="{desc_esc}">',
        f'  <meta name="twitter:image" content="{image}">',
        "",
        '  <link rel="icon" type="image/png" sizes="32x32" href="/assets/img/favicon-32.png">',
        '  <link rel="apple-touch-icon" href="/assets/img/apple-touch-icon.png">',
        f'  <link rel="canonical" href="{url}">',
    ]
    if preload:
        lines.append(
            f'  <link rel="preload" href="{preload}" as="font" type="font/woff2" crossorigin>')
    lines += [
        '  <link rel="stylesheet" href="/assets/css/styles.css">',
        '  <script src="/assets/js/theme.js"></script>',
        '  <script src="/assets/js/nav.js" defer></script>',
        '  <script src="/assets/js/site.js" defer></script>',
    ]
    for s in extra_scripts:
        lines.append(f'  <script src="{s}" defer></script>')
    lines.append("")
    lines.extend(fix_claims(b, soften=False) for b in keep_jsonld)
    lines.append("</head>")
    return "\n".join(lines)


def extract_jsonld_blocks(head_html):
    return re.findall(r"  <!-- Structured Data:[^\n]*\n  <script type=\"application/ld\+json\">.*?</script>",
                      head_html, re.S)


SKIP_LINK = ('<a href="#main" class="sr-only focus:not-sr-only focus:fixed focus:left-3 '
             'focus:top-3 focus:z-50 focus:rounded-full focus:bg-primary focus:px-3 '
             'focus:py-1.5 focus:text-sm focus:font-semibold focus:text-on-primary">'
             "Skip to content</a>")

BREAD = (
    '<nav aria-label="Breadcrumb" class="container-prose mx-auto max-w-prose pt-6 text-sm">\n'
    '  <ol class="flex items-center gap-1.5 text-muted">\n'
    '    <li><a href="/" class="text-muted hover:text-ink hover:underline">Home</a></li>\n'
    '    <li aria-hidden="true">/</li>\n'
    '    <li><a href="/blog" class="text-muted hover:text-ink hover:underline">Blog</a></li>\n'
    "  </ol>\n"
    "</nav>"
)


def chrome_wrap(*, body_main, home=False):
    """Skip link + header/footer with Phase-3 markers. Subpages get /#-prefixed anchors."""
    header = HEADER_FRAG
    if not home:
        header = re.sub(r'href="#(features|how-it-works|faq)"', r'href="/#\1"', header)
    return (f"{SKIP_LINK}\n"
            f"<!-- BEGIN:header -->\n{header}<!-- END:header -->\n\n"
            f"{body_main}\n\n"
            f"<!-- BEGIN:footer -->\n{FOOTER_FRAG}<!-- END:footer -->\n")


# ---------------------------------------------------------------- posts

def build_post(slug):
    meta = BY_SLUG[slug]
    src = head_version(f"site/blog/{slug}.html")

    head_src = src.split("</head>")[0]
    m = re.search(r"<title>(.*?)</title>", head_src, re.S)
    title = H.unescape(m.group(1)).strip() if m else meta["title"]
    m = re.search(r'<meta name="description" content="([^"]*)"', head_src)
    desc = m.group(1) if m else meta["excerpt"]
    m = re.search(r'<meta property="article:published_time" content="([^"]*)"', head_src)
    published = m.group(1) if m else meta["date"] + "T00:00:00Z"
    m = re.search(r'"dateModified": "([^"]*)"', src)
    modified = m.group(1) if m else meta["date"]
    m = re.search(r'"headline": "([^"]*)"', src)
    headline = m.group(1) if m else title

    main = re.search(r"<main[^>]*>(.*?)</main>", src, re.S).group(1)

    # Article header bits from HEAD (removed below, re-emitted per template)
    h1 = re.search(r"<h1[^>]*>(.*?)</h1>", main, re.S).group(1)
    lede_m = re.search(r'<p class="lede[^"]*">(.*?)</p>', main, re.S)
    lede = lede_m.group(1) if lede_m else meta["excerpt"]
    h1 = emdashes(fix_claims(migrate_classes(h1)))
    lede = emdashes(fix_claims(migrate_classes(lede)))
    # Strip old chrome: breadcrumb, article <header> (or bare badge/h1/lede)
    rest = re.sub(r'<nav aria-label="Breadcrumb">.*?</nav>', "", main, flags=re.S)
    rest = re.sub(r"<header[^>]*>.*?</header>", "", rest, flags=re.S)
    rest = re.sub(r"<h1[^>]*>.*?</h1>", "", rest, count=1, flags=re.S)
    rest = re.sub(r'<span class="badge[^"]*">.*?</span>', "", rest, count=1, flags=re.S)
    rest = re.sub(r'<p class="lede[^"]*">.*?</p>', "", rest, count=1, flags=re.S)

    # Split off FAQ + CTA tail: FAQ starts at the FAQ h2; CTA card follows.
    # Process uniformly instead: handle all h2/details/tables in place.
    h2s = []
    n = 0

    def h2_sub(m):
        nonlocal n
        attrs, text = m.group(1), m.group(2)
        if "h-section" not in attrs:
            return m.group(0)
        plain = strip_tags(text)
        if re.search(r"frequently asked|faq", plain, re.I):
            hid = "faq"
        else:
            n += 1
            hid = f"{slug}-section-{n}"
        h2s.append((hid, plain))
        return (f'<h2 id="{hid}" class="h-section mt-12 scroll-mt-24 text-2xl sm:text-3xl">'
                f"{text}</h2>")

    rest = re.sub(r"<h2([^>]*)>(.*?)</h2>", h2_sub, rest, flags=re.S)
    rest = re.sub(r'<h3([^>]*)>',
                  r'<h3 class="mt-8 text-lg font-semibold text-ink">', rest)

    # FAQ <details> -> canonical markup (also collects Q/A for JSON-LD)
    faqs = []

    def details_sub(m):
        inner = m.group(1)
        q = strip_tags(re.search(r"<summary[^>]*>(.*?)</summary>", inner, re.S).group(1))
        a_html = re.sub(r"<summary[^>]*>.*?</summary>", "", inner, flags=re.S).strip()
        faqs.append((q, strip_tags(a_html)))
        return (f'    <details class="clay-card group p-5 sm:p-6">\n'
                f'      <summary class="faq-summary">{q}\n'
                f'        {CHEV}\n'
                f'      </summary>\n'
                f'      <div class="muted mt-4 leading-relaxed">{a_html}</div>\n'
                f'    </details>')

    rest = re.sub(r"<details[^>]*>(.*?)</details>", details_sub, rest, flags=re.S)

    # Tables -> template wrapper + cell classes
    def table_sub(m):
        t = m.group(0)
        t = t.replace("w-full text-left text-sm sm:text-base",
                      "w-full min-w-[36rem] text-left text-sm")
        t = re.sub(r"<th([^>]*)>", r"<th\1>", t)
        t = re.sub(r'class="py-3 pr-4 font-semibold text-zinc-100"',
                   'class="px-3 py-3 font-semibold text-ink"', t)
        t = re.sub(r'class="py-3 font-semibold text-zinc-100"',
                   'class="px-3 py-3 font-semibold text-ink"', t)
        t = re.sub(r"<td([^>]*)>", r"<td\1>", t)
        return (f'<div class="clay-card mt-6 overflow-x-auto p-1">\n{t}\n    </div>')

    rest = re.sub(r"<table.*?</table>", table_sub, rest, flags=re.S)
    # td padding (only plain tds left unstyled)
    rest = re.sub(r"<td>", '<td class="border-t border-hairline px-3 py-2.5 align-top">', rest)
    rest = re.sub(r"<td class=\"([^\"]*)\"",
                  lambda m: f'<td class="{m.group(1)} border-t border-hairline px-3 py-2.5 align-top"'
                  if "px-3" not in m.group(1) else m.group(0), rest)
    rest = re.sub(r"<tr class=\"border-b border-white/10\">",
                  '<tr class="border-b border-hairline">', rest)

    rest = migrate_classes(rest)
    rest = fix_claims(rest)
    rest = fix_links(rest)
    rest = rest.replace(*SELF_LINK_FIX)
    rest = emdashes(rest)

    cats = meta["cats"].split()
    hero = (
        f'  <figure class="mt-8">\n'
        f'    <picture>\n'
        f'      <source srcset="/assets/img/blog/{slug}.avif" type="image/avif">\n'
        f'      <img src="/assets/img/blog/{slug}.webp" alt="{H.escape(meta["alt"], quote=True)}" width="1400" height="933"\n'
        f'           loading="eager" fetchpriority="high" decoding="async"\n'
        f'           class="block h-auto w-full rounded-2xl border border-hairline">\n'
        f'    </picture>\n'
        f'  </figure>'
    )
    badge = (f'    <a href="/blog#cat-{cats[0]}" class="badge">{CAT_LABELS[cats[0]]}</a>')
    toc_items = "\n".join(
        f'      <li><a href="#{hid}" class="link decoration-1">{H.escape(t)}</a></li>'
        for hid, t in h2s)
    rel_cards = []
    for r in meta["related"]:
        rm = BY_SLUG[r]
        rel_cards.append(
            f'      <a href="/blog/{r}" class="clay-card group overflow-hidden transition hover:-translate-y-0.5 hover:shadow-pop">\n'
            f'        <img src="/assets/img/blog/{r}-card.webp" alt="{H.escape(rm["alt"], quote=True)}" width="640" height="427"\n'
            f'             loading="lazy" decoding="async" class="block aspect-[3/2] h-auto w-full object-cover">\n'
            f'        <div class="p-4">\n'
            f'          <h3 class="font-display text-base font-medium leading-snug text-ink group-hover:underline">{H.escape(rm["title"])}</h3>\n'
            f'          <p class="muted mt-2 text-xs">{long_date(rm["date"])} &middot; {rm["read_min"]} min read</p>\n'
            f'        </div>\n'
            f'      </a>')
    related = "\n".join(rel_cards)

    article = (
        f'  <main id="main">\n'
        f'{BREAD}\n\n'
        f'<article class="container-prose mx-auto max-w-prose px-4 pb-16 pt-8 sm:pt-10">\n'
        f'  <div class="flex flex-wrap items-center gap-2">\n{badge}\n  </div>\n\n'
        f'  <h1 class="h-display mt-4">{h1}</h1>\n\n'
        f'  <p class="lede mt-5">{lede}</p>\n\n'
        f'  <div class="mt-6 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted">\n'
        f'    <time datetime="{meta["date"]}">{long_date(meta["date"])}</time>\n'
        f'    <span aria-hidden="true">&middot;</span>\n'
        f'    <span>{meta["read_min"]} min read</span>\n'
        f'  </div>\n\n'
        f'{hero}\n\n'
        f'  <nav aria-labelledby="toc-h" class="clay-card mt-10 p-5 sm:p-6">\n'
        f'    <h2 id="toc-h" class="font-display text-sm font-semibold uppercase tracking-[0.12em] text-muted">On this page</h2>\n'
        f'    <ol class="mt-3 space-y-2 text-[15px]">\n{toc_items}\n    </ol>\n'
        f'  </nav>\n'
        f'{rest}\n'
        f'  <section aria-labelledby="related-h" class="mt-14">\n'
        f'    <h2 id="related-h" class="h-section text-2xl sm:text-3xl">Keep reading</h2>\n'
        f'    <div class="mt-6 grid gap-4 sm:grid-cols-3">\n{related}\n    </div>\n'
        f'  </section>\n'
        f'</article>\n'
        f'  </main>'
    )

    img = f"{CANON}/assets/img/blog/{slug}-og.jpg"
    url = f"{CANON}/blog/{slug}"
    faq_block = ""
    if faqs:
        items = ",\n".join(
            '      {\n        "@type": "Question",\n'
            f'        "name": {json.dumps(fix_claims(q))},\n'
            '        "acceptedAnswer": {\n          "@type": "Answer",\n'
            f'          "text": {json.dumps(fix_claims(a))}\n        }}\n      }}'
            for q, a in faqs)
        faq_block = (
            "\n  <!-- Structured Data: FAQPage -->\n"
            '  <script type="application/ld+json">\n  {\n'
            '    "@context": "https://schema.org",\n'
            '    "@type": "FAQPage",\n    "mainEntity": [\n'
            f'{items}\n    ]\n  }}\n  </script>')

    art = {
        "@context": "https://schema.org",
        "@type": "Article",
        "headline": headline,
        "description": strip_tags(desc),
        "datePublished": published,
        "dateModified": modified,
        "author": {"@type": "Organization", "name": "TidyByte", "url": CANON},
        "publisher": {
            "@type": "Organization",
            "name": "TidyByte",
            "url": CANON,
            "logo": {"@type": "ImageObject",
                     "url": CANON + "/assets/img/icon-1024.png",
                     "width": 1024, "height": 1024},
        },
        "mainEntityOfPage": {"@type": "WebPage", "url": url},
        "image": img,
    }
    art_block = ("\n  <!-- Structured Data: Article -->\n"
                 '  <script type="application/ld+json">\n  '
                 + json.dumps(art, indent=2).replace("\n", "\n  ")
                 + "\n  </script>")
    crumb = [b for b in extract_jsonld_blocks(head_src) if "BreadcrumbList" in b]
    keep = [art_block, faq_block] if faq_block else [art_block]
    keep += crumb
    head = build_head(title=title, description=desc, og_type="article", url=url,
                      image=img, img_w=1200, img_h=630, keep_jsonld=keep)
    page = head + "\n\n<body>\n" + chrome_wrap(body_main=article) + "\n\n</body>\n</html>\n"
    return f"site/blog/{slug}.html", emdash_body(page)


# ---------------------------------------------------------------- hub

CHIP_ACTIVE = ("inline-flex cursor-pointer items-center rounded-full bg-primary px-4 py-1.5 "
               "text-sm font-semibold text-on-primary transition focus-visible:outline-none "
               "focus-visible:ring-2 focus-visible:ring-primary/40")
CHIP_INACTIVE = ("badge cursor-pointer px-4 py-1.5 text-sm font-medium transition hover:text-ink "
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40")


def build_hub():
    src = head_version("site/blog/index.html")
    head_src = src.split("</head>")[0]
    m = re.search(r"<title>(.*?)</title>", head_src, re.S)
    title = H.unescape(m.group(1)).strip()
    m = re.search(r'<meta name="description" content="([^"]*)"', head_src)
    desc = m.group(1).replace("54 expert guides", f"{len(MAP)} expert guides")
    keep = extract_jsonld_blocks(head_src)

    n = len(MAP)
    cards = []
    for p in MAP:
        cats = p["cats"]
        cards.append(
            f'        <article data-cats="{cats}" data-date="{p["date"]}">\n'
            f'          <a href="/blog/{p["slug"]}" class="card-link block h-full rounded-2xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40">\n'
            f'            <div class="clay-card h-full overflow-hidden transition hover:border-hairline-strong">\n'
            f'              <div class="overflow-hidden">\n'
            f'                <img src="/assets/img/blog/{p["slug"]}-card.webp" alt="{H.escape(p["alt"], quote=True)}" width="640" height="427" loading="lazy" decoding="async" class="aspect-[3/2] w-full object-cover">\n'
            f'              </div>\n'
            f'              <div class="p-5">\n'
            f'                <p><span class="badge">{CAT_LABELS[cats.split()[0]]}</span></p>\n'
            f'                <h3 class="mt-3 font-display text-lg font-medium leading-snug text-ink">{H.escape(p["title"])}</h3>\n'
            f'                <p class="muted mt-2 line-clamp-2 text-sm leading-relaxed">{H.escape(p["excerpt"])}</p>\n'
            f'                <p class="mt-4 text-xs text-muted"><time datetime="{p["date"]}">{long_date(p["date"])}</time> <span aria-hidden="true">&middot;</span> {p["read_min"]} min read</p>\n'
            f'              </div>\n'
            f'            </div>\n'
            f'          </a>\n'
            f'        </article>')
    grid = "\n".join(cards)

    chips = []
    counts = {"all": n}
    for p in MAP:
        for c in p["cats"].split():
            counts[c] = counts.get(c, 0) + 1
    for c in CHIP_ORDER:
        label = "All" if c == "all" else CAT_LABELS[c]
        cls = CHIP_ACTIVE if c == "all" else CHIP_INACTIVE
        pressed = "true" if c == "all" else "false"
        chips.append(
            f'          <button class="{cls}" data-filter="{c}" aria-pressed="{pressed}">{label} ({counts.get(c, 0)})</button>')
    chip_html = "\n".join(chips)

    main = (
        f'  <main id="main">\n'
        f'    <div class="container-prose pt-10 text-center sm:pt-14">\n'
        f'      <p class="eyebrow">Blog</p>\n'
        f'      <h1 class="h-display mt-3">iPhone photo cleanup guides.</h1>\n'
        f'      <p class="lede mx-auto mt-5 max-w-prose">{n} expert tips on freeing up storage, finding duplicates, compressing videos, and organizing your photo library &mdash; all using free, on-device tools.</p>\n'
        f'    </div>\n\n'
        f'      <div class="mx-auto mt-10 max-w-3xl">\n'
        f'        <div class="flex flex-wrap items-center justify-center gap-2" role="group" aria-label="Filter by category">\n{chip_html}\n        </div>\n'
        f'        <p class="muted mt-3 text-center text-sm" id="result-count">{n} posts</p>\n'
        f'      </div>\n\n'
        f'      <h2 id="grid-heading" tabindex="-1" class="h-section mx-auto mt-14 max-w-3xl">All posts</h2>\n'
        f'      <div id="blog-list" class="mx-auto mt-6 grid max-w-3xl gap-6 sm:grid-cols-2 lg:grid-cols-3">\n{grid}\n      </div>\n\n'
        f'      <div id="blog-empty" class="mx-auto mt-10 hidden max-w-3xl text-center">\n'
        f'        <p class="muted">No posts in this category yet.</p>\n'
        f'        <p class="mt-3"><a href="/blog" id="blog-empty-all" class="link">View all posts</a></p>\n'
        f'      </div>\n\n'
        f'      <nav aria-label="Blog pagination" class="mx-auto mt-12 max-w-3xl" id="pagination">\n'
        f'        <div class="flex items-center justify-center gap-2">\n'
        f'          <button class="badge cursor-pointer px-3.5 py-1.5 text-sm font-medium transition hover:text-ink" id="prev-btn" disabled aria-label="Previous page">&larr; Previous</button>\n'
        f'          <div id="page-buttons" class="flex gap-1"></div>\n'
        f'          <button class="badge cursor-pointer px-3.5 py-1.5 text-sm font-medium transition hover:text-ink" id="next-btn" aria-label="Next page">Next &rarr;</button>\n'
        f'        </div>\n'
        f'      </nav>\n'
        f'  </main>'
    )
    head = build_head(title=title, description=desc, og_type="website",
                      url=f"{CANON}/blog", image=f"{CANON}/assets/img/icon-1024.png",
                      img_w=1024, img_h=630, extra_scripts=("/assets/js/blog.js",),
                      keep_jsonld=keep)
    page = head + "\n\n<body>\n" + chrome_wrap(body_main=main) + "\n\n</body>\n</html>\n"
    return "site/blog/index.html", emdash_body(page)


# ---------------------------------------------------------------- home

def build_home():
    src = head_version("site/index.html")
    head_src = src.split("</head>")[0]
    m = re.search(r"<title>(.*?)</title>", head_src, re.S)
    title = H.unescape(m.group(1)).strip()
    m = re.search(r'<meta name="description" content="([^"]*)"', head_src)
    desc = m.group(1)
    keep = extract_jsonld_blocks(head_src)
    hero = (LAND / "03-hero.html").read_text()
    m = re.search(r'<source srcset="([^"]+)" type="image/avif"', hero)
    preload_img = m.group(1) if m else None
    sections = ["01-announcement.html"] + [f"0{i}-{n}.html" for i, n in
                [(3, "hero"), (4, "stats"), (5, "how-it-works"), (6, "toolkit"),
                 (7, "storage"), (8, "privacy"), (9, "opensource"), (10, "faq"),
                 (11, "cta")]]
    # 10-faq/11-cta use two-digit names on disk
    sections = ["01-announcement.html", "03-hero.html", "04-stats.html",
                "05-how-it-works.html", "06-toolkit.html", "07-storage.html",
                "08-privacy.html", "09-opensource.html", "10-faq.html", "11-cta.html"]
    main_inner = "\n\n".join((LAND / f).read_text().rstrip() for f in sections)
    main = f"  <main id=\"main\">\n{main_inner}\n  </main>"
    head = build_head(title=title, description=desc, og_type="website", url=f"{CANON}/",
                      image=f"{CANON}/assets/img/icon-1024.png", img_w=1024, img_h=630,
                      preload="/assets/fonts/fredoka-var-latin.woff2" if
                      (SITE / "assets/fonts/fredoka-var-latin.woff2").exists() else None,
                      keep_jsonld=keep)
    # hero image preload (matches the <picture> AVIF source)
    if preload_img:
        head = head.replace(
            '  <link rel="stylesheet" href="/assets/css/styles.css">',
            f'  <link rel="preload" as="image" href="{preload_img}" type="image/avif">\n'
            '  <link rel="stylesheet" href="/assets/css/styles.css">')
    page = head + "\n\n<body>\n" + chrome_wrap(body_main=main, home=True) + "\n\n</body>\n</html>\n"
    return "site/index.html", emdash_body(page)


# ---------------------------------------------------------------- utils

def build_util(name, url, extra_scripts=()):
    src = head_version(f"site/{name}.html")
    head_src = src.split("</head>")[0]
    m = re.search(r"<title>(.*?)</title>", head_src, re.S)
    title = H.unescape(m.group(1)).strip()
    m = re.search(r'<meta name="description" content="([^"]*)"', head_src)
    desc = m.group(1) if m else ""
    keep = extract_jsonld_blocks(head_src)
    main = re.search(r"<main[^>]*>(.*?)</main>", src, re.S).group(1)
    main = migrate_classes(main)
    main = fix_claims(main)
    main = fix_links(main)
    main = emdashes(main)
    main = f"  <main id=\"main\">{main}  </main>"
    m = re.search(r'<meta property="og:image" content="([^"]*)"', head_src)
    img = m.group(1) if m else f"{CANON}/assets/img/icon-1024.png"
    head = build_head(title=title, description=desc, og_type="website", url=url,
                      image=img, img_w=1024, img_h=630,
                      extra_scripts=extra_scripts, keep_jsonld=keep)
    page = head + "\n\n<body>\n" + chrome_wrap(body_main=main) + "\n\n</body>\n</html>\n"
    return f"site/{name}.html", emdash_body(page)


# ---------------------------------------------------------------- main

def main():
    outputs = [build_home(), build_hub()]
    for p in MAP:
        outputs.append(build_post(p["slug"]))
    outputs.append(build_util("support", f"{CANON}/support"))
    outputs.append(build_util("privacy", f"{CANON}/privacy"))
    outputs.append(build_util("changelog", f"{CANON}/changelog"))
    outputs.append(build_util("404", f"{CANON}/404"))
    changed = 0
    for rel, content in outputs:
        dest = ROOT / rel
        if CHECK:
            if not dest.exists() or dest.read_text() != content:
                print(f"DIFFERS: {rel}")
                changed += 1
        else:
            dest.write_text(content)
    print(f"{len(outputs)} pages {'checked' if CHECK else 'written'}"
          + (f", {changed} differ" if CHECK else ""))
    if CHECK and changed:
        sys.exit(1)


main()
