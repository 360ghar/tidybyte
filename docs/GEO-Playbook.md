# GEO / AEO Playbook — TidyByte

**What this document is.** On-site work (pages, schema, `llms.txt`) makes TidyByte *eligible* to be cited by AI answer engines and featured in search results. Off-site work is what makes it *likely*. This playbook is the off-site half: where to get listed, what to write, and how to measure whether it worked.

**Who does what.** Everything in §1–§4 needs a human with an account on each platform. Nothing here is automated, and none of it should be faked: fabricated reviews, astroturfed Reddit posts and paid "best of" placements are detectable, get removed, and can damage the brand permanently.

Last updated: 2026-10-18.

---

## 1. Why off-site matters more for AI answers than for classic SEO

AI answer engines (ChatGPT, Perplexity, Claude, Gemini, Copilot) build their answers from a mix of sources: the site itself, third-party pages that discuss the product, and community discussions. For a small app, the third-party sources often carry more weight than the site, because they look independent.

Practical consequences:

1. **Entity consistency beats volume.** The name, category, price and platform must read identically everywhere: "TidyByte", free iPhone/iPad photo and storage cleaner, iOS 17+, no ads, no subscription, no account, on-device, MIT open source. Contradictions make an entity unreliable, and unreliable entities do not get cited.
2. **A listing on a comparison site is worth more than a blog post nobody links to.** The comparison sites are what the answer engines read.
3. **Reddit threads get cited constantly.** A genuinely useful answer in an existing thread about iPhone storage is one of the highest-leverage things available, and one of the easiest to do wrong.

---

## 2. Off-site listings (do these first)

Each row is a page that answers "what are the best iPhone storage cleaner / photo cleaner apps". Ordered by expected return per hour of work.

| # | Platform | What to do | Notes |
|---|---|---|---|
| 1 | **AlternativeTo** | Create the TidyByte listing: category Photo Cleaner / Utilities, free, iOS, no account. Add the 5 closest alternatives (CleanMyPhone, Smart Cleaner, Slidebox, Gemini Photos, Cleanup) and mark the differences. | AlternativeTo pages rank well and are read by AI crawlers. Free and takes ~20 minutes. |
| 2 | **Product Hunt** | Launch once, with the free/open-source/no-upload angle as the hook. Prepare 4-6 screenshots and a 60-second demo. | One shot per product. Do it when the listing and screenshots are final. |
| 3 | **GitHub (already live)** | The repo is the strongest trust signal available. Add topics (`ios`, `swiftui`, `photo-cleaner`, `on-device`, `privacy`, `storage`), a README badge row, and a "why this exists" section stating the positioning. | `sameAs` in the site schema already points here. Keep the repo description identical to the App Store subtitle. |
| 4 | **Slant** | Answer "What are the best iPhone photo cleaner apps?" with a short, factual entry. | Slant pages get cited for "best X" questions. |
| 5 | **Apple's App Store review volume** | Ask satisfied users for a rating at a natural moment (after a completed cleanup session). Never incentivise it. | Ratings are the one signal the App Store itself ranks on. A prompt after a successful cleanup is honest and effective. |
| 6 | **awesome-list PRs** | Submit to `awesome-ios` (Apps section) and any privacy-tools or self-hosted-adjacent lists that accept iOS apps. | Small traffic, but these lists are heavily crawled. |
| 7 | **Wikipedia / Wikidata** | Not yet viable at this scale — noted so it is not attempted prematurely. Revisit only with independent third-party coverage. | Do not create a Wikipedia article for your own app; it will be deleted and it wastes credibility. |

---

## 3. Community participation (highest risk, highest reward)

The subreddits and forums where this conversation happens: r/iphone, r/ios, r/apple, r/iphonehelp, r/techsupport, r/privacy, r/applehelp, and the MacRumors forums.

**The rule: answer the question first, mention the app only when it is genuinely the answer.** A comment that solves someone's storage problem with built-in iOS steps and *then* notes "if you want to clear duplicates in bulk, I built a free open-source cleaner that does it on-device" is fine. A comment that opens with the app is an ad, and moderators remove ads.

Practical guidance:

- **Read each subreddit's self-promotion rules before posting.** Several ban it outright without prior participation history.
- **Contribute for weeks before mentioning anything.** Answer storage questions with no mention of the app at all.
- **Disclose that you are the developer.** Every time. Undisclosed promotion is the fastest way to lose an account and the trust of exactly the audience you want.
- **Never post the same comment in multiple subreddits.** That is what spam filters are built to catch.
- **Prefer answering existing threads over starting new ones.** "How do I free up storage on my iPhone?" is asked daily; a good answer there is read for years.

The comparison-intent threads ("CleanMyPhone alternative?", "is Smart Cleaner worth it?") are the highest-value targets, because the person is already shopping and an honest free alternative is a real answer to their question.

---

## 4. Content that earns citations

On-site, the pages that get cited by AI answers share three properties: a short direct answer near the top, specific verifiable numbers, and a clear statement of what the product does *not* do. The tool landing pages were built with those in mind. When adding new content, keep them:

- **Lead with the answer.** The quick-answer box exists for this. One paragraph, 40–60 words, no preamble.
- **State limits.** "No app can clear system data on iOS" earns more trust than a claim that it can, and answer engines quote the honest version.
- **Use real numbers with units.** "350-400 MB per minute of 4K video at 60 fps" is quotable; "videos are big" is not.
- **Name the competitor categories, not competitors.** "Subscription cleaners upload your photos to analyse them" is fair comment. Naming a specific competitor disparagingly invites a complaint and reads as marketing.
- **Keep one page per intent.** A page that tries to rank for storage cleaner, video compression and duplicates at once ranks for none of them.

---

## 5. Measurement

Track these monthly. All are free.

| Signal | Where | What "working" looks like |
|---|---|---|
| Indexed pages | Google Search Console → Pages | All 67 routes indexed, no "Discovered - currently not indexed" on tool pages |
| Impressions on the money queries | Search Console → Queries | `storage cleaner iphone`, `duplicate photo cleaner`, `compress video iphone`, `image compressor iphone` start appearing with impressions |
| Click-through rate | Search Console → Queries | CTR above 3% on tool pages once they rank in the top 20 |
| FAQ rich results | Search Console → Enhancements → FAQ | Valid items, no errors |
| AI answer spot checks | Manual | Once a month, ask ChatGPT / Perplexity / Gemini / Claude: "best free iPhone storage cleaner", "free photo cleaner no subscription", "how do I find duplicate photos on my iPhone". Record whether TidyByte is named, and what the answer says about it. |
| Referral traffic | Netlify analytics or Search Console → Links | AlternativeTo and Reddit referrals appearing |
| App Store impressions | App Store Connect → Analytics | Impressions and conversion rate on the App Store search terms in §4 of `APP_STORE_LISTING.md` |

Keep a simple log of the AI spot checks with the date and the answer text. It is the only reliable way to see whether citations are accumulating, because no analytics tool reports them yet.

---

## 6. What not to do

- **No fake reviews or ratings.** It violates the App Store guidelines, and it is the one thing that can get the app removed.
- **No invented `aggregateRating` or `Review` schema on the site.** Google penalises structured data that does not reflect visible, genuine reviews. The site deliberately ships without them.
- **No doorway pages.** One thin page per keyword variation gets the whole domain demoted. Sixteen substantial pages beat a hundred spun ones.
- **No paid "top 10 cleaners" placements without disclosure.** They are frequently detected, and they age badly.
- **No astroturfing.** Undisclosed promotion in communities, at any scale, is the fastest route to a ban and to a reputation that is hard to repair.
