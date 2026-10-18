// Tool landing pages: one page per cleanup tool plus a hub.
//
// Why this file exists: the site previously had a single product page (/)
// competing for every query. These entries give each commercial intent its
// own route, its own primary keyword, and its own answer-engine blocks.
//
// Everything machine-readable is generated from here so the schema and the
// visible page can never drift apart:
//   - src/lib/tool-page.ts   renders the <main> body (hero, comparison
//                            table, FAQ, related links) from these objects
//   - toolPageMeta()         builds the PageMeta (title/description/JSON-LD)
//   - src/pages/[page].astro + [page].md.ts + llms.txt pick the routes up
//
// FAQ text lives here (not in the content file) because the same strings
// are emitted twice: once as visible <details> markup and once inside the
// FAQPage JSON-LD. Google requires the two to match.
import type { PageMeta } from "./page-meta";

export interface ToolFaq {
  q: string;
  a: string;
}

export interface ToolCompare {
  caption: string;
  columns: [string, string, string];
  rows: { label: string; cells: [string, string, string] }[];
}

export interface Tool {
  /** URL segment: /<slug> */
  slug: string;
  /** Short label for breadcrumbs and link lists */
  name: string;
  /** <title>, keep under 60 characters */
  title: string;
  /** Meta description, 140-158 characters */
  description: string;
  h1: string;
  badge: string;
  lede: string;
  /** 40-60 word direct answer. Rendered near the top and marked speakable. */
  quickAnswer: string;
  keywords: string[];
  /** Basename under /assets/img/screenshots (a -768 avif/webp pair exists) */
  screenshot: { name: string; alt: string; caption: string };
  compare: ToolCompare;
  faqs: ToolFaq[];
  relatedTools: string[];
  /** Blog routes, rendered as cards */
  relatedPosts: string[];
  ctaHeading: string;
  ctaBody: string;
  /** Hub pages list their children instead of a prose body */
  hub?: boolean;
}

const SCREENSHOT_W = 353;
const SCREENSHOT_H = 768;

export const TOOLS: Tool[] = [
  {
    slug: "photo-cleaner",
    name: "Photo cleaner",
    title: "iPhone Photo Cleaner & Image Cleaner App | TidyByte",
    description:
      "TidyByte is a free iPhone photo cleaner and image cleaner: duplicates, screenshots, blur, bursts and big files, plus video and image compression. 100% on-device.",
    h1: "The best free iPhone photo cleaner and image cleaner.",
    badge: "Photo &amp; image cleaner",
    lede:
      "One free app that clears every kind of photo clutter &mdash; duplicates, similar shots, screenshots, screen recordings, chat media, blur, bursts, Live Photos and oversized videos. Nothing ever leaves your iPhone.",
    quickAnswer:
      "TidyByte is a free iPhone photo cleaner and image cleaner that removes duplicate photos, similar shots, screenshots, screen recordings, chat media, blurry pictures and burst sequences, then compresses videos and photos. It runs entirely on-device with Apple&rsquo;s Photos and Vision frameworks, so no image is ever uploaded. No ads, no subscription, no account.",
    keywords: [
      "iphone photo cleaner",
      "image cleaner",
      "photo cleaner app",
      "free photo cleaner",
      "clean up photos iphone",
      "image cleaner app",
    ],
    screenshot: {
      name: "02-cleanup-tools",
      alt: "TidyByte cleanup tools screen showing twelve tools for duplicates, similar photos, screenshots, screen recordings, chat media, blurry photos, large files, bursts, Live Photos, compression and AI search.",
      caption: "Twelve cleanup tools, one library map.",
    },
    compare: {
      caption:
        "How TidyByte compares as a photo cleaner (verified against how each option ships in 2026)",
      columns: ["TidyByte", "Apple Photos (built-in)", "Typical paid cleaner"],
      rows: [
        {
          label: "Price",
          cells: ["Free forever", "Included with iOS", "$3-$10 / week or / year"],
        },
        {
          label: "Ads and paywalls",
          cells: ["None, no in-app purchases", "None", "Ads or a hard paywall"],
        },
        {
          label: "Duplicate and similar-photo grouping",
          cells: [
            "Exact (SHA-256) plus visual (Vision feature prints)",
            "Merged duplicates album, exact matches only",
            "Usually exact matches only",
          ],
        },
        {
          label: "Swipe review of every photo",
          cells: ["Yes", "No", "Rarely"],
        },
        {
          label: "Image and video compression",
          cells: ["Both, with size verified after export", "No", "Sometimes, video only"],
        },
        {
          label: "Where your photos are processed",
          cells: ["On-device, no network access", "On-device", "Often a cloud service"],
        },
        {
          label: "Source code auditable",
          cells: ["MIT licensed on GitHub", "Closed", "Closed"],
        },
      ],
    },
    faqs: [
      {
        q: "What is the best free photo cleaner app for iPhone?",
        a: "The best free iPhone photo cleaner is one that finds every type of clutter, lets you review each item before anything is deleted, and does not upload your library. TidyByte covers duplicates, similar shots, screenshots, screen recordings, chat media, blurry photos, bursts, Live Photos, large files, compression and on-device AI search, costs nothing, and processes everything on-device with Apple's Vision and Photos frameworks.",
      },
      {
        q: "What is the difference between a photo cleaner and an image cleaner?",
        a: "Nothing functional. &ldquo;Photo cleaner&rdquo; is the common phrase for iPhone cleanup apps, while &ldquo;image cleaner&rdquo; is how the same job is often searched for on the web and on Android-adjacent tools. TidyByte is both: it cleans still images, video, screenshots and Live Photos from one library.",
      },
      {
        q: "Is TidyByte really free, or is there a catch?",
        a: "It is free with no in-app purchases, no subscription, and no ads. There is no catch and no upsell screen, because the app has no backend to pay for: it performs no networking at all, and the source is MIT licensed on GitHub so the claim is verifiable.",
      },
      {
        q: "Can a photo cleaner app delete the wrong photos?",
        a: "It can if it deletes without review. TidyByte never deletes while you work: swipes and tool selections collect on a review screen, and the final delete goes through the standard iOS Photos confirmation. Deleted items then sit in Recently Deleted for 30 days, so a mistake costs nothing.",
      },
      {
        q: "Does TidyByte work on iPad as well as iPhone?",
        a: "Yes. TidyByte is a universal app for iOS 17 and later. Every cleanup tool works on iPad, the swipe interface adapts to the larger screen, and iPad supports all orientations while iPhone stays portrait for the swipe layout.",
      },
    ],
    relatedTools: [
      "storage-cleaner",
      "duplicate-photo-cleaner",
      "blurry-photo-cleaner",
      "image-compression",
    ],
    relatedPosts: [
      "/blog/best-free-photo-cleaner-apps-iphone-2026",
      "/blog/how-to-use-tidybyte",
      "/blog/are-photo-cleaner-apps-safe",
    ],
    ctaHeading: "Clean your photo library for free.",
    ctaBody:
      "Download TidyByte and clear the clutter in one sitting. No account, no subscription, no uploads.",
    hub: true,
  },
  {
    slug: "storage-cleaner",
    name: "Storage cleaner",
    title: "iPhone Storage Cleaner — Free Up Space Fast | TidyByte",
    description:
      "A free iPhone storage cleaner that shows what is using your space, then clears duplicates, big videos, screenshots and Live Photos. On-device, no ads.",
    h1: "The best free iPhone storage cleaner.",
    badge: "Storage cleaner",
    lede:
      "See exactly what is filling your iPhone, then clear it: duplicates, oversized videos, screenshots, blurry shots and Live Photos. Free, on-device, nothing uploaded.",
    quickAnswer:
      "TidyByte is a free iPhone storage cleaner that maps your photo library into photos, videos, screenshots, Live Photos and other, then removes what wastes the most space and compresses what is worth keeping. It runs 100% on-device, so no file is uploaded, and it has no ads, no subscription and no account.",
    keywords: [
      "iphone storage cleaner",
      "storage cleaner app",
      "free up storage iphone",
      "clean up iphone storage",
      "best storage cleaner",
    ],
    screenshot: {
      name: "03-storage-dashboard",
      alt: "TidyByte storage dashboard with a donut chart splitting the library into photos, videos, screenshots, Live Photos and other, plus the largest files.",
      caption: "The storage dashboard: every gigabyte accounted for.",
    },
    compare: {
      caption:
        "iPhone storage cleaners compared: what each one can actually reclaim in 2026",
      columns: ["TidyByte", "iOS Storage settings", "Typical paid cleaner"],
      rows: [
        {
          label: "Shows what the photo library contains",
          cells: [
            "Donut chart by type plus largest files",
            "A single total for Photos",
            "Usually a total only",
          ],
        },
        {
          label: "Clears duplicates and similar shots",
          cells: ["Yes, with review", "Duplicates album for exact matches", "Yes"],
        },
        {
          label: "Clears app caches and system data",
          cells: [
            "No, and no app can on iOS",
            "Offload app, delete app",
            "Claims vary, usually impossible",
          ],
        },
        {
          label: "Shrinks videos and photos",
          cells: ["Yes, with size verified", "No", "Sometimes"],
        },
        {
          label: "Tracks space freed over time",
          cells: ["Activity &amp; savings ledger, 30-day chart", "No", "Sometimes"],
        },
        {
          label: "Cost",
          cells: ["Free, no in-app purchases", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "What is the best free storage cleaner for iPhone?",
        a: "The best free iPhone storage cleaner shows where the space actually went and lets you reclaim it without uploading anything. TidyByte maps your photo library by type, surfaces the largest files, clears duplicates and screenshots, and compresses videos and photos, all on-device and free with no subscription or ads.",
      },
      {
        q: "How much space can a storage cleaner actually free on an iPhone?",
        a: "On a library that has never been cleaned, the recoverable space usually comes from three places: duplicate copies, screenshots and screen recordings, and large 4K videos. TidyByte shows you the total for each before you delete anything, so you decide what is worth removing rather than trusting a marketing number.",
      },
      {
        q: "Can any iPhone app clear system data or &ldquo;Other&rdquo; storage?",
        a: "No. iOS sandboxes every app to its own container, so no third-party cleaner can empty caches or system data belonging to other apps, whatever the App Store listing claims. TidyByte only touches your photo and video library, where the reclaimable space genuinely is, and it says so plainly.",
      },
      {
        q: "Will a storage cleaner delete photos from iCloud too?",
        a: "Deleting a photo removes it from your library, so if iCloud Photos is enabled the removal syncs to iCloud as well, exactly as it would if you deleted the photo in the Photos app. Nothing leaves Recently Deleted for 30 days, and TidyByte always routes deletion through the standard iOS confirmation.",
      },
      {
        q: "Why is my iPhone storage full when I have few photos?",
        a: "Common causes are large video files, screenshots and screen recordings, Live Photos, and photos restored from a backup that already existed in iCloud. TidyByte's storage dashboard breaks the library into photos, videos, screenshots, Live Photos and other, so the real culprit is visible before you delete anything.",
      },
    ],
    relatedTools: [
      "photo-cleaner",
      "large-file-cleaner",
      "video-compression",
      "image-compression",
    ],
    relatedPosts: [
      "/blog/how-to-clean-iphone-storage-without-deleting-photos",
      "/blog/iphone-storage-full-free-up-space",
      "/blog/how-to-check-iphone-storage-breakdown",
    ],
    ctaHeading: "Find your wasted gigabytes.",
    ctaBody:
      "Download TidyByte, open the storage dashboard, and see what is really filling your iPhone.",
  },
  {
    slug: "duplicate-photo-cleaner",
    name: "Duplicate cleaner",
    title: "Duplicate Photo Cleaner for iPhone — Free | TidyByte",
    description:
      "Free duplicate photo cleaner for iPhone. Finds exact copies by SHA-256 and visually similar shots with Vision, then deletes them after your review. On-device.",
    h1: "Duplicate photo cleaner for iPhone.",
    badge: "Duplicate cleaner",
    lede:
      "Exact copies matched byte-for-byte, plus near-identical shots grouped by Apple&rsquo;s Vision framework. Review every group, keep the best, delete the rest.",
    quickAnswer:
      "TidyByte is a free duplicate photo cleaner for iPhone. It finds exact duplicates by comparing SHA-256 hashes of the file data and near-duplicates with Apple Vision feature prints, groups them side by side, pre-selects the keeper, and deletes only after you confirm. Everything runs on-device.",
    keywords: [
      "duplicate photo cleaner",
      "duplicate photo finder iphone",
      "remove duplicate photos iphone",
      "delete duplicates free",
      "exact duplicate photos",
    ],
    screenshot: {
      name: "02-cleanup-tools",
      alt: "TidyByte cleanup tools screen with the Duplicates tool highlighted among the cleanup options.",
      caption: "Duplicates and similar photos live under one roof.",
    },
    compare: {
      caption: "Duplicate detection compared: hash matching versus visual matching",
      columns: ["TidyByte", "Apple Photos duplicates album", "Typical paid cleaner"],
      rows: [
        {
          label: "Exact duplicates",
          cells: ["SHA-256 hash of file data", "Detected and merged", "Usually file name and size"],
        },
        {
          label: "Near-duplicates (resized, re-saved, edited)",
          cells: ["Vision feature prints", "Not detected", "Rarely"],
        },
        {
          label: "Keeper selection",
          cells: [
            "Highest quality copy pre-selected, changeable",
            "Apple chooses",
            "Varies",
          ],
        },
        {
          label: "Side-by-side comparison before deleting",
          cells: ["Yes, with metadata", "Merged automatically", "Limited"],
        },
        {
          label: "iCloud-only files",
          cells: ["Skipped with a count shown", "Handled by iOS", "Often stalls"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How does TidyByte find duplicate photos?",
        a: "Exact duplicates are matched with a streaming SHA-256 hash of the underlying file, so two photos are only paired when their bytes are genuinely identical. Near-duplicates are matched with Apple Vision feature prints: each image is reduced to a numerical signature and compared, which catches the same shot saved twice at different sizes.",
      },
      {
        q: "What is the difference between exact duplicates and similar photos?",
        a: "Exact duplicates are byte-for-byte copies, usually created by restores or sync conflicts. Similar photos are different files of the same moment: bursts, HDR variants, or the same scene from a slightly different angle. TidyByte handles both, with separate tools so you review the safer group first.",
      },
      {
        q: "Which copy does TidyByte keep?",
        a: "For each group TidyByte pre-selects a keeper using resolution, file size and favourite status, then shows every copy side by side with its metadata so you can override the choice. Nothing is deleted until you confirm, and you can exclude any group entirely.",
      },
      {
        q: "Does the duplicate scan work with iCloud-only photos?",
        a: "Yes. Assets stored only in iCloud are reported with their own count rather than silently blocking the scan. Because downloading them is slow on a large library, TidyByte surfaces how many it skipped so you can decide whether to download them first and run the scan again.",
      },
      {
        q: "Are duplicate photos safe to delete?",
        a: "Yes, once you have seen the group. TidyByte never deletes a photo that has no copy left: the keeper stays, and deletion happens through the iOS Photos confirmation. Removed photos sit in Recently Deleted for 30 days, so any mistake is reversible for a month.",
      },
    ],
    relatedTools: [
      "similar-photo-cleaner",
      "photo-cleaner",
      "storage-cleaner",
      "burst-photo-cleaner",
    ],
    relatedPosts: [
      "/blog/find-delete-duplicate-photos-iphone",
      "/blog/why-are-there-duplicate-photos-in-my-iphone",
      "/blog/duplicate-photo-finder-iphone-free",
    ],
    ctaHeading: "Clear the duplicates today.",
    ctaBody:
      "Run one scan, review the groups, and reclaim the space those copies have been holding.",
  },
  {
    slug: "similar-photo-cleaner",
    name: "Similar photos",
    title: "Similar Photo Cleaner for iPhone — Keep the Best | TidyByte",
    description:
      "Find near-identical photos on iPhone and keep only the best shot. TidyByte groups similar photos with on-device Apple Vision analysis and deletes the rest, free.",
    h1: "Similar photo cleaner for iPhone.",
    badge: "Similar photos",
    lede:
      "Twenty shots of the same moment, one worth keeping. Group them, score them, keep the best &mdash; without a subscription.",
    quickAnswer:
      "TidyByte is a free similar photo cleaner for iPhone. It groups near-identical shots taken close together, scores each frame on sharpness and exposure, recommends the keeper with a reason, and deletes the rest only after you review the group. All analysis runs on-device using Apple Vision.",
    keywords: [
      "similar photo cleaner",
      "find similar photos iphone",
      "near duplicate photos",
      "keep best photo",
      "photo similarity app",
    ],
    screenshot: {
      name: "05-swipe-session",
      alt: "TidyByte photo review screen showing one photo at a time with keep and delete controls.",
      caption: "One photo, one decision, no group left unreviewed.",
    },
    compare: {
      caption: "Similar-photo grouping compared",
      columns: ["TidyByte", "Apple Photos", "Typical paid cleaner"],
      rows: [
        {
          label: "Finds visually similar shots",
          cells: ["Vision feature prints", "No dedicated tool", "Sometimes"],
        },
        {
          label: "Explains which shot it keeps",
          cells: ["Quality score with a written reason", "Not applicable", "Rarely"],
        },
        {
          label: "Runs off-device analysis",
          cells: ["Never", "No", "Often"],
        },
        {
          label: "Group size limit",
          cells: ["No practical limit", "Not applicable", "Often capped by plan"],
        },
        {
          label: "Time-window grouping",
          cells: ["Groups shots taken minutes apart", "Not available", "Sometimes"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I find similar photos on my iPhone?",
        a: "Open TidyByte's Similar Photos tool and start a scan. It walks your library, groups photos taken within a short window that also look alike according to Apple Vision feature prints, and presents each group as a decision: keep the recommended shot or pick a different one. Nothing is deleted without your confirmation.",
      },
      {
        q: "Are similar photos the same as duplicates?",
        a: "No. Duplicates are identical files, often created by sync conflicts or backup restores. Similar photos are genuinely different frames of the same scene: a burst, a few steps to the left, or a slightly different expression. Duplicates are safe to clear automatically; similar photos deserve a quick look.",
      },
      {
        q: "How does TidyByte decide which photo to keep?",
        a: "Each frame is scored on sharpness, exposure and resolution using on-device Vision analysis, and the highest scorer is recommended. The app states the reason in plain language, and you can override the pick with one tap before deleting anything.",
      },
      {
        q: "Will similar-photo detection delete photos by mistake?",
        a: "The tool only pre-selects the frames you did not choose as the keeper, and every group is shown before deletion with a side-by-side view. Deletions go through the iOS Photos confirmation and land in Recently Deleted for 30 days, so a wrong pick is easy to undo.",
      },
      {
        q: "Does similar-photo scanning slow down my iPhone?",
        a: "The scan reads reduced-size image data rather than full-resolution files, so it stays light, and it runs in the background while you use the app. You can stop a scan at any time and the groups found so far remain available for review.",
      },
    ],
    relatedTools: [
      "duplicate-photo-cleaner",
      "burst-photo-cleaner",
      "blurry-photo-cleaner",
      "photo-cleaner",
    ],
    relatedPosts: [
      "/blog/find-similar-photos-on-iphone",
      "/blog/how-to-stop-duplicate-photos-iphone",
      "/blog/best-app-to-delete-similar-photos-iphone-free",
    ],
    ctaHeading: "Keep the best shot, drop the rest.",
    ctaBody:
      "Download TidyByte Free and let the quality scores do the arguing for you.",
  },
  {
    slug: "screenshot-cleaner",
    name: "Screenshot cleaner",
    title: "Screenshot Cleaner for iPhone — Clear Them Fast | TidyByte",
    description:
      "Free screenshot cleaner for iPhone. Find every screenshot and screen recording, sort them, and delete in one pass after review. On-device, no ads, no subscription.",
    h1: "Screenshot cleaner for iPhone.",
    badge: "Screenshot cleaner",
    lede:
      "Screenshots pile up faster than any other kind of photo. Find them all, review them in one list, clear them in a single pass.",
    quickAnswer:
      "TidyByte is a free screenshot cleaner for iPhone. It detects screenshots and screen recordings by media subtype, lists them with sizes and dates, and deletes the ones you select in one pass after review. Processing is on-device, and deleted screenshots stay in Recently Deleted for 30 days.",
    keywords: [
      "screenshot cleaner",
      "delete screenshots iphone",
      "clear screenshots",
      "screen recording cleaner",
      "iphone screenshot storage",
    ],
    screenshot: {
      name: "02-cleanup-tools",
      alt: "TidyByte cleanup tools screen showing the Screenshots tool among the cleanup options.",
      caption: "Screenshots, gathered in one list.",
    },
    compare: {
      caption: "Screenshot cleanup compared",
      columns: ["TidyByte", "Apple Photos", "Typical paid cleaner"],
      rows: [
        {
          label: "Finds screenshots specifically",
          cells: ["Yes, by media subtype", "Screenshots album", "Yes"],
        },
        {
          label: "Includes screen recordings",
          cells: ["Yes", "Screenshots album for some", "Sometimes"],
        },
        {
          label: "Sort by size or date",
          cells: ["Both", "Date only", "Varies"],
        },
        {
          label: "Bulk delete after review",
          cells: ["Yes", "Manual selection", "Yes"],
        },
        {
          label: "Shows how much space it will free",
          cells: ["Before deletion", "No", "Rarely"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I delete all screenshots from my iPhone at once?",
        a: "Open TidyByte's Screenshots tool, review the list it builds, tap Select All, and confirm. It finds screenshots and screen recordings by their media subtype rather than by guessing from file names, shows the total size of your selection, and deletes through the standard iOS confirmation.",
      },
      {
        q: "How much space do screenshots take up on an iPhone?",
        a: "Screenshots are usually under 5 MB each, but they accumulate in the thousands over years, and screen recordings are far larger. TidyByte lists every screenshot with its file size and shows the combined total before you delete, so you can see whether the cleanup is worth your two minutes.",
      },
      {
        q: "Will I lose screenshots I still need?",
        a: "Only if you delete them. The tool shows a scrollable list with thumbnails and dates, so you can spot the receipts, tickets and reference images worth keeping and deselect them. Anything deleted stays in Recently Deleted for 30 days.",
      },
      {
        q: "Does TidyByte detect screenshots saved from apps or the web?",
        a: "Those images are saved as ordinary photos, so no tool can detect them reliably by subtype. TidyByte's Smart Categories groups photos that look like they came from apps or the web, which is the honest way to review that pile rather than pretending it can be detected exactly.",
      },
      {
        q: "Can it clean screenshots on iPad too?",
        a: "Yes. The same tool runs on iPad, and screenshots are detected identically there. Deletions sync through Photos, so an iPad cleanup shows up on your iPhone if iCloud Photos is on.",
      },
    ],
    relatedTools: [
      "photo-cleaner",
      "blurry-photo-cleaner",
      "storage-cleaner",
      "large-file-cleaner",
    ],
    relatedPosts: [
      "/blog/how-to-clean-up-screenshots-on-iphone",
      "/blog/how-to-delete-screenshots-from-iphone",
      "/blog/how-to-clean-up-iphone-photo-library-fast",
    ],
    ctaHeading: "Clear your screenshot pile.",
    ctaBody:
      "Download TidyByte Free and turn years of screenshots into free space in a single pass.",
  },
  {
    slug: "blurry-photo-cleaner",
    name: "Blurry photos",
    title: "Blurry Photo Finder & Cleaner for iPhone | TidyByte",
    description:
      "Find blurry, dark and overexposed photos on your iPhone and delete them in one pass. Free, on-device blur detection with a sensitivity control and no subscription.",
    h1: "Blurry photo finder for iPhone.",
    badge: "Blurry photos",
    lede:
      "Sharpness, darkness and overexposure scored on-device, with a sensitivity control you can tune. Keep the memories, bin the misses.",
    quickAnswer:
      "TidyByte is a free blurry photo finder and cleaner for iPhone. It scores every photo for sharpness, darkness and overexposure using on-device Vision analysis, groups the results into blurry, dark and overexposed tabs, and deletes what you select after review. No uploads, no ads, no subscription.",
    keywords: [
      "blurry photo finder",
      "find blurry photos iphone",
      "delete blurry photos",
      "out of focus photos",
      "low light photo cleaner",
    ],
    screenshot: {
      name: "05-swipe-session",
      alt: "TidyByte reviewing photos one at a time so out-of-focus shots can be deleted quickly.",
      caption: "Review the flagged shots, keep the ones that still work.",
    },
    compare: {
      caption: "Blur detection compared",
      columns: ["TidyByte", "Apple Photos", "Typical paid cleaner"],
      rows: [
        {
          label: "Sharpness analysis",
          cells: ["Per-photo score, on-device", "None", "Sometimes, cloud based"],
        },
        {
          label: "Dark and overexposed detection",
          cells: ["Separate tabs", "None", "Rarely"],
        },
        {
          label: "Sensitivity control",
          cells: ["Adjustable threshold", "Not applicable", "Rare"],
        },
        {
          label: "Explainable results",
          cells: ["Shows which score flagged it", "Not applicable", "No"],
        },
        {
          label: "Screenshots excluded from analysis",
          cells: ["Yes, with the skipped count shown", "Not applicable", "No"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I find blurry photos on my iPhone?",
        a: "Open TidyByte's Blurry Photos tool and run a scan. Every photo is scored for sharpness on-device, and the soft ones are collected into a list you can review. Separate tabs cover photos that are too dark or overexposed, because those are different problems that call for different decisions.",
      },
      {
        q: "Does blur detection ever flag a photo that is actually sharp?",
        a: "It can, usually when a photo is intentionally soft: shallow depth of field, motion-blurred backgrounds, or artistic shots. That is why TidyByte has a sensitivity control and shows the score behind each flag, and why nothing is deleted until you review the list and confirm.",
      },
      {
        q: "Can I recover a blurry photo that has already been deleted?",
        a: "Yes. Deletions go to the iOS Recently Deleted album and stay there for 30 days, so restoring a photo you changed your mind about is a two-tap job in Photos. TidyByte never removes anything permanently on its own.",
      },
      {
        q: "Does TidyByte analyse photos stored only in iCloud?",
        a: "It analyses what the system can give it. Photos downloaded to the device are analysed at full size; for iCloud-only assets the app requests a working copy and marks results when a reduced-size image was used, so you always know which recommendations are certain.",
      },
      {
        q: "Is there a limit on how many photos it can scan?",
        a: "No. Scans are streamed rather than limited by count, and a scan can be stopped and restarted at any time. On a 40,000-photo library the first scan takes a few minutes, and subsequent scans only revisit photos that changed.",
      },
    ],
    relatedTools: [
      "similar-photo-cleaner",
      "screenshot-cleaner",
      "photo-cleaner",
      "photo-organizer",
    ],
    relatedPosts: [
      "/blog/find-blurry-photos-iphone",
      "/blog/how-to-finish-photo-cleanup-in-one-session",
      "/blog/how-to-delete-photos-fast-on-iphone",
    ],
    ctaHeading: "Clear the shots that missed.",
    ctaBody:
      "Download TidyByte Free and get the out-of-focus, too-dark and blown-out frames out of the way.",
  },
  {
    slug: "large-file-cleaner",
    name: "Large files",
    title: "Find Large Files on iPhone and Delete Them | TidyByte",
    description:
      "Find the largest files in your iPhone photo library, sort by size, share before deleting, or compress instead. Free, on-device, no ads and no subscription.",
    h1: "Find large files on iPhone and clear them.",
    badge: "Large files",
    lede:
      "The few files that eat most of your storage are videos. Sort them by size, decide file by file, then delete or compress.",
    quickAnswer:
      "TidyByte is a free large-file finder for iPhone. It lists the biggest videos and photos in your library with exact sizes, sorts them by size or date, lets you share or export before deleting, and can compress a file instead of removing it. All processing happens on-device.",
    keywords: [
      "find large files iphone",
      "largest videos iphone",
      "biggest files photo library",
      "free up space large videos",
      "large file finder",
    ],
    screenshot: {
      name: "03-storage-dashboard",
      alt: "TidyByte storage dashboard listing the largest files in the photo library with their sizes.",
      caption: "Sorted by size, so the worst offenders are first.",
    },
    compare: {
      caption: "How each option surfaces your largest files",
      columns: ["TidyByte", "iOS Storage settings", "Typical paid cleaner"],
      rows: [
        {
          label: "Shows individual large files",
          cells: ["Sorted list with sizes", "Only an app total", "Usually only a total"],
        },
        {
          label: "Adjustable size threshold",
          cells: ["Yes, from a few megabytes up", "No", "Rarely"],
        },
        {
          label: "Share or export before deleting",
          cells: ["Yes, multi-select export", "One file at a time", "Rarely"],
        },
        {
          label: "Compress instead of delete",
          cells: ["Yes, video and photo presets", "No", "Sometimes"],
        },
        {
          label: "Files with unknown size reported",
          cells: ["Yes, counted separately", "No", "No"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I find the largest files on my iPhone?",
        a: "TidyByte's Large Files tool lists the biggest items in your photo library with their exact sizes and sorts them by size or date. On most libraries the top of that list is 4K video, followed by screen recordings and ProRAW photos, which is why the tool is usually the fastest way to reclaim real space.",
      },
      {
        q: "Why do videos take so much more space than photos?",
        a: "A 4K clip records roughly 350 MB for every minute, while a single photo is usually 2 to 5 MB. A handful of long videos can outweigh thousands of photos, so clearing or compressing them returns far more space per decision than deleting images.",
      },
      {
        q: "Can I keep a video but make it smaller?",
        a: "Yes. TidyByte's Video Compression tool re-encodes the clip at a preset you choose, verifies the resulting file is genuinely smaller, saves it to your library, and only then offers to remove the original. You keep the memory and lose the excess bitrate.",
      },
      {
        q: "What happens to files whose size the app cannot read?",
        a: "Some iCloud-only assets do not report a size until they are downloaded. TidyByte counts those separately instead of pretending they are zero bytes, so the totals you see are honest and you can decide whether to download them before cleaning.",
      },
      {
        q: "Is it safe to delete the largest files first?",
        a: "It is the highest-yield approach, but only after you have looked at them. Export the ones you want to keep elsewhere, then delete. Everything removed goes to Recently Deleted for 30 days, which is your safety net if you change your mind.",
      },
    ],
    relatedTools: [
      "storage-cleaner",
      "video-compression",
      "burst-photo-cleaner",
      "photo-cleaner",
    ],
    relatedPosts: [
      "/blog/how-to-find-large-files-in-iphone-photo-library",
      "/blog/iphone-storage-full-but-no-photos",
      "/blog/compress-videos-iphone",
    ],
    ctaHeading: "See your biggest files first.",
    ctaBody:
      "Download TidyByte Free, sort by size, and clear the handful of files holding gigabytes hostage.",
  },
  {
    slug: "burst-photo-cleaner",
    name: "Burst photos",
    title: "Burst Photo Cleaner for iPhone — Pick the Best | TidyByte",
    description:
      "Clean up burst photos on iPhone: group every sequence, keep the best frame automatically, delete the rest in one pass. Free, on-device, no ads, no subscription.",
    h1: "Burst photo cleaner for iPhone.",
    badge: "Burst photos",
    lede:
      "A ten-second burst is thirty photos, and twenty-nine of them are waste. Group them, keep the best frame, clear the rest.",
    quickAnswer:
      "TidyByte is a free burst photo cleaner for iPhone. It groups every burst sequence, picks the sharpest and best-exposed frame as the keeper, leaves the remaining frames pre-selected for deletion, and lets you change the pick or deselect anything before you confirm.",
    keywords: [
      "burst photo cleaner",
      "delete burst photos iphone",
      "find burst photos",
      "keep best photo from burst",
      "burst photo storage",
    ],
    screenshot: {
      name: "05-swipe-session",
      alt: "TidyByte review screen used to compare frames from a burst sequence before deleting the rest.",
      caption: "Compare the frames, keep one, clear the sequence.",
    },
    compare: {
      caption: "Burst-frame cleanup compared",
      columns: ["TidyByte", "Apple Photos", "Typical paid cleaner"],
      rows: [
        {
          label: "Groups burst sequences",
          cells: ["By burst identifier", "Bursts album", "Rarely"],
        },
        {
          label: "Picks the keeper automatically",
          cells: ["Sharpness, exposure, resolution", "Favourite or first frame", "No"],
        },
        {
          label: "Pre-selects the rest for deletion",
          cells: ["Yes, fully reversible", "Manual selection", "No"],
        },
        {
          label: "Respects your manual choice on re-scan",
          cells: ["Yes", "Not applicable", "No"],
        },
        {
          label: "Shows space reclaimed per sequence",
          cells: ["Yes", "No", "Rarely"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I delete burst photos on my iPhone?",
        a: "Open TidyByte's Burst Photos tool. It groups each sequence, recommends the best frame, and pre-selects the others. Review the groups, change any keeper you disagree with, then confirm once. Deleting a burst this way takes seconds per sequence instead of hunting through the Bursts album by hand.",
      },
      {
        q: "How much space do burst photos take up?",
        a: "Each frame is a full-resolution photo, so a thirty-frame burst is thirty photos: often 60 to 150 MB from a few seconds of holding the shutter. Keeping one frame and removing the rest is one of the fastest ways to cut a library down without losing anything you wanted.",
      },
      {
        q: "Does iOS keep the original burst after I delete frames?",
        a: "Deleting individual frames is supported and safe, and the sequence keeps its remaining photos. TidyByte deletes only the frames you left deselected, so the keeper remains a normal photo in your library and can be edited, shared or favourited afterwards.",
      },
      {
        q: "How does TidyByte choose the best frame in a burst?",
        a: "Each frame is scored for sharpness, exposure and resolution using on-device analysis, and the highest scorer is recommended as the keeper. There is no hidden preference for the first frame, and you can override the choice with one tap before anything is deleted.",
      },
      {
        q: "Will my choices survive if I run the tool again?",
        a: "Yes. Frames you explicitly kept are respected on the next run and are not re-armed for deletion, which matters because re-scanning a cleaned library should never undo your decisions.",
      },
    ],
    relatedTools: [
      "similar-photo-cleaner",
      "duplicate-photo-cleaner",
      "large-file-cleaner",
      "photo-cleaner",
    ],
    relatedPosts: [
      "/blog/how-to-find-burst-photos-on-iphone",
      "/blog/how-to-delete-photos-fast-on-iphone",
      "/blog/how-to-organize-thousands-of-photos-iphone",
    ],
    ctaHeading: "Keep one frame, clear the sequence.",
    ctaBody:
      "Download TidyByte Free and turn every burst into a single keeper plus a pile of reclaimed space.",
  },
  {
    slug: "live-photo-converter",
    name: "Live Photo converter",
    title: "iPhone Live Photo Converter — Save Space | TidyByte",
    description:
      "Convert Live Photos to still images on iPhone and reclaim the space the motion clips use. Free, on-device conversion that keeps date, location and album.",
    h1: "Live Photo converter for iPhone.",
    badge: "Live Photos",
    lede:
      "Every Live Photo carries a short video you rarely watch. Keep the still, lose the motion, keep the metadata.",
    quickAnswer:
      "TidyByte is a free Live Photo converter for iPhone. It turns Live Photos into still images on-device, preserving the capture date, location, favourite status and album membership, then lets you delete the originals once you are happy. No uploads, no account, no subscription.",
    keywords: [
      "live photo converter",
      "convert live photos to stills",
      "live photo to still iphone",
      "live photo storage",
      "save space live photos",
    ],
    screenshot: {
      name: "02-cleanup-tools",
      alt: "TidyByte cleanup tools screen showing the Live Photos conversion tool among the cleanup options.",
      caption: "Live Photos conversion, next to the other cleanup tools.",
    },
    compare: {
      caption: "Live Photo conversion compared",
      columns: ["TidyByte", "Apple Photos", "Typical paid cleaner"],
      rows: [
        {
          label: "Convert Live Photos to stills in bulk",
          cells: ["Yes, single or full batch", "One photo at a time", "Yes"],
        },
        {
          label: "Keeps capture date and location",
          cells: ["Yes, preserved", "Yes", "Varies"],
        },
        {
          label: "Keeps album membership",
          cells: ["Yes", "Yes", "Often lost"],
        },
        {
          label: "Reports the space reclaimed",
          cells: ["Per item and in total", "No", "Rarely"],
        },
        {
          label: "Removes the original afterwards",
          cells: ["Optional, after verification", "Manual", "Automatic, no review"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I convert Live Photos to still images on iPhone?",
        a: "Open TidyByte's Live Photos tool, pick the photos you want to change, and start the conversion. Each Live Photo becomes a still image with the same capture date, location and album, and the app reports the space each conversion returned before you decide what to do with the originals.",
      },
      {
        q: "How much space do Live Photos actually use?",
        a: "A Live Photo is a still plus roughly three seconds of video, which usually makes it two to three times the size of the still alone. On a library with thousands of Live Photos, converting them to stills commonly returns several gigabytes without losing the photo itself.",
      },
      {
        q: "Do I lose the photo if I convert a Live Photo?",
        a: "No. The still image is kept: conversion drops the motion clip, not the picture. TidyByte writes the still into your library first and only offers to delete the original Live Photo once the conversion is confirmed, so there is never a gap where the photo exists nowhere.",
      },
      {
        q: "Can I convert only some Live Photos?",
        a: "Yes. You can select individual photos in the preview, or convert everything in a batch and review the results afterwards. Nothing is deleted in either mode until you confirm, and deletions sit in Recently Deleted for 30 days.",
      },
      {
        q: "Does this work with Live Photos stored in iCloud?",
        a: "Yes, though the download can take a moment per item because the motion data has to come down first. TidyByte processes each item as it arrives and keeps the batch running without blocking the rest of the app.",
      },
    ],
    relatedTools: [
      "image-compression",
      "storage-cleaner",
      "large-file-cleaner",
      "photo-cleaner",
    ],
    relatedPosts: [
      "/blog/convert-live-photos-to-stills-iphone",
      "/blog/how-to-manage-live-photos-iphone",
      "/blog/how-much-space-do-live-photos-take",
    ],
    ctaHeading: "Turn motion clips into space.",
    ctaBody:
      "Download TidyByte Free and convert your Live Photos to stills without losing a single date or location.",
  },
  {
    slug: "video-compression",
    name: "Video compression",
    title: "Video Compression for iPhone — Shrink Videos | TidyByte",
    description:
      "Compress videos on iPhone without uploading them. Choose a preset, shrink 4K clips to a fraction of the size, and verify the result before deleting the original.",
    h1: "Video compression for iPhone.",
    badge: "Video compression",
    lede:
      "4K clips are what fill iPhones. Re-encode them at a preset you choose, check the real file size, then decide what to do with the original.",
    quickAnswer:
      "TidyByte is a free iPhone video compressor. It re-encodes large videos on-device at presets from 4K down to smaller sizes, verifies the exported file is genuinely smaller than the original, saves it to your library, and offers to remove the original only after that check passes.",
    keywords: [
      "video compression iphone",
      "compress video",
      "video compressor app",
      "shrink video file size",
      "reduce 4k video size",
    ],
    screenshot: {
      name: "03-storage-dashboard",
      alt: "TidyByte storage dashboard showing videos as the largest category in the photo library.",
      caption: "Videos are usually the biggest line on the chart.",
    },
    compare: {
      caption: "Ways to compress video on iPhone compared",
      columns: ["TidyByte", "iMovie export", "Cloud video compressors"],
      rows: [
        {
          label: "Works offline",
          cells: ["Yes, fully on-device", "Yes", "No, upload required"],
        },
        {
          label: "Batch multiple clips",
          cells: ["Yes, with progress and cancel", "One project at a time", "Sometimes"],
        },
        {
          label: "Verifies the new file is smaller",
          cells: ["Yes, before offering deletion", "No", "No"],
        },
        {
          label: "Keeps resolution options explicit",
          cells: ["Presets listed by size and quality", "Single export setting", "Varies"],
        },
        {
          label: "Handles iCloud-only videos",
          cells: ["Downloads first, reports size honestly", "Downloads first", "Downloads first"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Paid plans, often per file"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I compress a video on my iPhone without losing quality?",
        a: "Use a preset that matches how you will actually watch the clip. Dropping 4K to 1080p typically cuts a file to less than half its size while looking identical on a phone screen, and shorter travel or social clips survive aggressive presets well. TidyByte shows you the saved size per file, so you can stop at the first preset that still looks right.",
      },
      {
        q: "Does compressing a video delete the original?",
        a: "Not unless you tell it to. TidyByte exports the compressed version, compares the two file sizes, saves the new file to your library, and only then offers to remove the original. If the export happens to be larger, it says so and keeps the original untouched.",
      },
      {
        q: "How much smaller will my videos get?",
        a: "The answer depends on the source: 4K footage from a recent iPhone compresses the most because it carries far more detail than a phone screen needs. Lower-resolution clips that are already efficient compress far less. TidyByte reports the actual result for each file rather than promising a fixed percentage.",
      },
      {
        q: "Can I compress several videos at once?",
        a: "Yes. Select the clips, choose a preset, and the batch runs with per-file progress you can cancel. Finished items stay in the list with their before and after sizes, so you always know what happened to each video.",
      },
      {
        q: "What happens with videos stored only in iCloud?",
        a: "The app downloads the asset first, which takes time on a large file, and then compresses it locally. Nothing is uploaded at any point, and if a video cannot be downloaded within the timeout, it is reported as skipped instead of hanging the batch.",
      },
    ],
    relatedTools: [
      "image-compression",
      "large-file-cleaner",
      "storage-cleaner",
      "photo-cleaner",
    ],
    relatedPosts: [
      "/blog/compress-videos-iphone",
      "/blog/how-to-find-large-files-in-iphone-photo-library",
      "/blog/iphone-storage-full-free-up-space",
    ],
    ctaHeading: "Shrink your biggest videos.",
    ctaBody:
      "Download TidyByte Free, pick a preset, and watch a 4K clip turn into a fraction of its size.",
  },
  {
    slug: "image-compression",
    name: "Image compression",
    title: "Image Compression for iPhone — Compress Photos | TidyByte",
    description:
      "Compress images on iPhone without uploading them. Re-encode large photos at the quality you choose, verify the size saved, and keep the originals until you decide.",
    h1: "Image compression for iPhone.",
    badge: "Image compression",
    lede:
      "Re-encode the photos that are larger than they need to be, choose the quality, and see exactly how many megabytes each one returned.",
    quickAnswer:
      "TidyByte is a free image compression app for iPhone. It re-encodes large photos on-device at a quality preset you choose, checks the new file is genuinely smaller, saves it to the library with the original metadata, and offers to delete the original afterwards. Nothing is uploaded and there is no subscription.",
    keywords: [
      "image compression iphone",
      "compress images",
      "photo compression app",
      "reduce photo file size",
      "compress photos free",
    ],
    screenshot: {
      name: "02-cleanup-tools",
      alt: "TidyByte cleanup tools screen showing the Photo Compression tool among the cleanup options.",
      caption: "Photo compression sits alongside the deletion tools.",
    },
    compare: {
      caption: "Image compression compared",
      columns: ["TidyByte", "iOS Mail or Shortcuts", "Web image compressors"],
      rows: [
        {
          label: "Stays on-device",
          cells: ["Yes, no network access", "Yes", "No, your photos are uploaded"],
        },
        {
          label: "Batch a whole selection",
          cells: ["Yes, with per-file progress", "One image at a time", "Sometimes, by upload"],
        },
        {
          label: "Verifies real size reduction",
          cells: ["Yes, per file", "No", "No"],
        },
        {
          label: "Keeps EXIF data and album placement",
          cells: ["Date, location and album preserved", "Often stripped", "Usually stripped"],
        },
        {
          label: "Shows a history of what was compressed",
          cells: ["Yes, on-device ledger", "No", "No"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Ads or paid tiers"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I compress images on my iPhone?",
        a: "Open TidyByte's Photo Compression tool, select the images, and pick a quality preset. Each photo is re-encoded on-device, the new file size is compared against the original, and the result is saved into your library. You then choose whether to keep the original or let it go.",
      },
      {
        q: "Will compressing photos make them look worse?",
        a: "Compression always removes some data, but at moderate settings the difference is invisible at normal viewing sizes. Screenshots and text-heavy images lose crispness first, which is why TidyByte reports the actual saving per file so you can stop before the trade stops being worth it.",
      },
      {
        q: "Does compressing a photo delete the original?",
        a: "No. The compressed version is written to your library first and verified, and the original is only offered for removal once that succeeds. If the re-encode comes out larger than the original, the app reports that and leaves everything as it was.",
      },
      {
        q: "Can I compress images in bulk?",
        a: "Yes. Select as many photos as you like and the batch runs with per-item progress and a cancel option. Items that would not shrink are reported as skipped with the reason, rather than quietly disappearing from the list.",
      },
      {
        q: "Is there a limit on how many images I can compress for free?",
        a: "No. There is no daily cap, no credit system and no paid tier, because the work happens on your own device and costs nothing to run. The app is free with no in-app purchases and the source is MIT licensed.",
      },
    ],
    relatedTools: [
      "video-compression",
      "live-photo-converter",
      "storage-cleaner",
      "photo-cleaner",
    ],
    relatedPosts: [
      "/blog/how-to-compress-photos-on-iphone",
      "/blog/free-up-icloud-storage-without-deleting-photos",
      "/blog/how-to-clean-up-iphone-photo-library-fast",
    ],
    ctaHeading: "Make big photos small.",
    ctaBody:
      "Download TidyByte Free and re-encode the oversized images without sending a single one to a server.",
  },
  {
    slug: "photo-organizer",
    name: "Photo organizer",
    title: "Photo Organizer for iPhone — Sort by Category | TidyByte",
    description:
      "Organize thousands of photos on iPhone with on-device smart categories, year and album views, and swipe sorting. Free, private, and built for big libraries.",
    h1: "Photo organizer for iPhone.",
    badge: "Photo organizer",
    lede:
      "Sort thirty thousand photos without renaming a single file: browse by category, year or album, and make keep-or-delete decisions in one pass.",
    quickAnswer:
      "TidyByte is a free photo organizer for iPhone. It classifies your library into smart categories on-device, breaks it down by year and album, and turns organizing into swipe decisions: keep, delete or add to an album. Nothing is uploaded and no files are renamed or moved.",
    keywords: [
      "photo organizer iphone",
      "organize photos",
      "sort photos by category",
      "iphone photo library organization",
      "photo sorting app",
    ],
    screenshot: {
      name: "06-album-picker",
      alt: "TidyByte album picker for choosing which album to review one photo at a time.",
      caption: "Albums and categories, reviewed one card at a time.",
    },
    compare: {
      caption: "Photo organizing approaches compared",
      columns: ["TidyByte", "Apple Photos", "Typical paid organizer"],
      rows: [
        {
          label: "Automatic classification",
          cells: ["On-device Vision categories", "Search and Memories", "Cloud tagging"],
        },
        {
          label: "Organizing as a decision workflow",
          cells: ["Swipe keep, delete or album", "Manual selection", "Mostly manual"],
        },
        {
          label: "Organizes by year and album",
          cells: ["Yes, deep links into a swipe session", "Yes", "Sometimes"],
        },
        {
          label: "Leaves files where they are",
          cells: ["No moves, no renames", "Not applicable", "Sometimes re-imports"],
        },
        {
          label: "Works offline",
          cells: ["Always", "Yes", "Often needs a server"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "What is the fastest way to organize thousands of photos on an iPhone?",
        a: "Review them as decisions rather than browsing them. TidyByte loads a deck of photo cards and you swipe right to keep, left to delete, or up to add to an album, which processes a library far faster than tapping through grid views and selecting items one by one.",
      },
      {
        q: "Does TidyByte move or rename my photos?",
        a: "No. It never moves, renames or re-imports files, so your library stays exactly where iOS expects it. Organizing happens through albums and deletions, which means undo works the way it does everywhere else in Photos.",
      },
      {
        q: "How does it sort photos by category?",
        a: "Each photo is classified on-device with Apple Vision: screenshots, documents, receipts, food, pets, people and more. The categories come from on-device image analysis, not from a server, so the classification works in airplane mode and your photos are never uploaded.",
      },
      {
        q: "Can I organize only one album or one year?",
        a: "Yes. Pick any album, or drill into a year from the storage breakdown and jump straight into a swipe session scoped to that subset. That is usually the difference between an organizing session you finish and one you abandon.",
      },
      {
        q: "Does it work on iPad as well?",
        a: "Yes. TidyByte is a universal app for iOS 17 and later, and the organizing flows work on both iPhone and iPad, with the swipe layout adapting to the larger screen and all iPad orientations.",
      },
    ],
    relatedTools: [
      "photo-cleaner",
      "screenshot-cleaner",
      "blurry-photo-cleaner",
      "storage-cleaner",
    ],
    relatedPosts: [
      "/blog/how-to-organize-iphone-photos",
      "/blog/how-to-organize-thousands-of-photos-iphone",
      "/blog/swipe-left-right-organize-photos",
    ],
    ctaHeading: "Organize a library you actually enjoy.",
    ctaBody:
      "Download TidyByte Free and turn sorting thirty thousand photos into a few evenings of swiping.",
  },
  {
    slug: "free-photo-cleaner-no-subscription",
    name: "Free, no subscription",
    title: "Free Photo Cleaner App — No Subscription, No Ads | TidyByte",
    description:
      "A genuinely free photo cleaner for iPhone: no subscription, no ads, no in-app purchases, no account, and no uploads. MIT open source, 100% on-device.",
    h1: "A free photo cleaner with no subscription and no ads.",
    badge: "Free, no subscription",
    lede:
      "No paywall on the delete button. No weekly plan. No ads between photos. Free because the app does no networking and has nothing to pay for.",
    quickAnswer:
      "TidyByte is a free iPhone photo cleaner with no subscription, no ads, no in-app purchases and no account. It performs no networking at all, so there is no server to fund and nothing to upsell. Every tool is unlocked for everyone, and the source code is MIT licensed on GitHub.",
    keywords: [
      "free photo cleaner app",
      "photo cleaner no subscription",
      "cleaner app no ads",
      "iphone cleaner no in app purchase",
      "free iphone storage app",
    ],
    screenshot: {
      name: "04-settings",
      alt: "TidyByte settings screen showing reminders, large-file threshold and preferences, with no purchase options.",
      caption: "Settings, not storefronts: there is nothing to buy.",
    },
    compare: {
      caption: "What &ldquo;free&rdquo; usually means, and what it means here",
      columns: ["TidyByte", "Freemium cleaners", "Subscription cleaners"],
      rows: [
        {
          label: "Deleting photos",
          cells: ["Unlimited, free", "Limited then paywalled", "Paywalled"],
        },
        {
          label: "Ads",
          cells: ["None", "Common", "Sometimes"],
        },
        {
          label: "In-app purchases",
          cells: ["None in the binary", "Typically yes", "Yes"],
        },
        {
          label: "Account required",
          cells: ["No account, ever", "Often required", "Required"],
        },
        {
          label: "Data collected",
          cells: ["None, no analytics SDK", "Usage analytics, ad SDKs", "Analytics plus uploads"],
        },
        {
          label: "Source code",
          cells: ["MIT licensed, readable", "Closed", "Closed"],
        },
      ],
    },
    faqs: [
      {
        q: "Is TidyByte really free, or is there a hidden limit?",
        a: "It is free with no limits on features or photos. There are no in-app purchases in the binary, no credit system, no trial that ends, and no upgrade prompt. The app has no backend and performs no networking, so there is no cost to recover and nothing to sell you.",
      },
      {
        q: "Why would a developer give away a photo cleaner?",
        a: "Because this one runs entirely on your device, so it costs nothing to operate. TidyByte is MIT open source: the source is public on GitHub, anyone can audit or build it, and there is no analytics or ad SDK inside that would need paying for.",
      },
      {
        q: "Does the free version upload my photos to a server?",
        a: "No version uploads anything. The app performs no network requests at all, and all analysis runs locally with Apple's Vision and Photos frameworks. You can verify this by reading the source or by watching your network activity while you use it.",
      },
      {
        q: "Do free cleaner apps sell my data?",
        a: "Apps that upload your photos to fund themselves can, and many freemium cleaners do collect usage data through analytics and ad SDKs. TidyByte ships with none of those libraries and has no server to send anything to, which removes the question entirely.",
      },
      {
        q: "What do I give up by not paying for a cleaner app?",
        a: "Nothing that matters. Paid cleaners mostly charge for the same functions, sometimes behind credits. TidyByte includes duplicates, similar photos, screenshots, screen recordings, chat media, blur, bursts, Live Photos, large files, video and photo compression, smart categories with AI search, and the storage dashboard, with no paid tier.",
      },
    ],
    relatedTools: [
      "photo-cleaner",
      "storage-cleaner",
      "duplicate-photo-cleaner",
      "image-compression",
    ],
    relatedPosts: [
      "/blog/best-iphone-cleaner-app-no-subscription",
      "/blog/best-free-photo-cleaner-apps-iphone-2026",
      "/blog/open-source-iphone-photo-cleaner",
    ],
    ctaHeading: "Free, and it stays free.",
    ctaBody:
      "Download TidyByte Free and clean your library without a subscription screen ever appearing.",
  },
  {
    slug: "screen-recording-cleaner",
    name: "Screen recordings",
    title: "Screen Recording Cleaner for iPhone — Clear Them | TidyByte",
    description:
      "Find and delete screen recordings on your iPhone in one pass. Free, on-device cleanup that shows the real size of each recording before you delete anything.",
    h1: "Screen recording cleaner for iPhone.",
    badge: "Screen recordings",
    lede:
      "Screen recordings are the largest files nobody remembers making. Find every one, see its size, and clear them in a single pass.",
    quickAnswer:
      "TidyByte is a free screen recording cleaner for iPhone. It detects screen recordings by their media subtype, lists them with real file sizes and dates, and deletes the ones you select after review. Screen recordings are usually 50 to 200 MB each, so clearing them returns space faster than deleting photos.",
    keywords: [
      "screen recording cleaner",
      "delete screen recordings iphone",
      "screen recordings storage",
      "clear screen recordings",
      "iphone screen recording size",
    ],
    screenshot: {
      name: "02-cleanup-tools",
      alt: "TidyByte cleanup tools screen showing the Screen Recordings tool alongside the other cleanup options.",
      caption: "Screen recordings, separated from the screenshots.",
    },
    compare: {
      caption: "Clearing screen recordings compared",
      columns: ["TidyByte", "Apple Photos", "Typical paid cleaner"],
      rows: [
        {
          label: "Finds screen recordings specifically",
          cells: ["Yes, by media subtype", "Mixed into a Screenshots album", "Rarely separated"],
        },
        {
          label: "Shows each file's real size",
          cells: ["Yes, sortable by size", "No", "Sometimes"],
        },
        {
          label: "Bulk delete after review",
          cells: ["Yes, one confirmation", "Manual selection", "Yes"],
        },
        {
          label: "Total space in the selection",
          cells: ["Shown before deleting", "No", "Rarely"],
        },
        {
          label: "Uploads anything",
          cells: ["No, on-device", "No", "Often yes"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I find screen recordings on my iPhone?",
        a: "Open TidyByte's Screen Recordings tool. Recordings are detected by their media subtype in the photo library, so the list is exact rather than a guess from dimensions or dates. Each entry shows its real size and duration, and sorting by size puts the biggest offenders first.",
      },
      {
        q: "How much space do screen recordings take up?",
        a: "More than most people expect. A screen recording is a full video file at the device's resolution, so two minutes commonly lands between 50 and 200 MB, and long recordings of games or video calls can pass a gigabyte. Clearing a handful of them often returns more space than deleting thousands of photos.",
      },
      {
        q: "Can I delete all screen recordings at once?",
        a: "Yes. Select all, check the total size the app reports for your selection, and confirm once. The deletion goes through the standard iOS confirmation and the files sit in Recently Deleted for 30 days, so a recording you still need can be restored from the Photos app.",
      },
      {
        q: "Are screen recordings different from screenshots?",
        a: "They are both flagged by iOS in the photo library, but recordings are video and far larger. TidyByte keeps them in separate tools so you can clear the recordings first, which is where the space is, and then review the screenshots with a lighter touch.",
      },
      {
        q: "Does deleting a screen recording affect anything else?",
        a: "No. The file is removed from your photo library like any other video; nothing else in the system depends on it. If the recording was shared or saved elsewhere, that copy is unaffected.",
      },
    ],
    relatedTools: [
      "screenshot-cleaner",
      "large-file-cleaner",
      "video-compression",
      "storage-cleaner",
    ],
    relatedPosts: [
      "/blog/how-to-delete-screenshots-from-iphone",
      "/blog/how-to-clean-up-screenshots-on-iphone",
      "/blog/how-to-find-large-files-in-iphone-photo-library",
    ],
    ctaHeading: "Clear the recordings you forgot.",
    ctaBody:
      "Download TidyByte Free, sort screen recordings by size, and take back the largest easy win in your library.",
  },
  {
    slug: "chat-media-cleaner",
    name: "Chat media",
    title: "Chat Media Cleaner — Clear WhatsApp Photos | TidyByte",
    description:
      "Reclaim space from chat apps: find the photos and videos WhatsApp, Telegram and other messengers saved to your library, review them by album, delete in one pass.",
    h1: "Chat media cleaner for iPhone.",
    badge: "Chat media",
    lede:
      "Every chat app quietly saves photos and videos into your library. Review them by album and clear the ones you never meant to keep.",
    quickAnswer:
      "TidyByte is a free chat media cleaner for iPhone. It finds the media that messaging apps saved into your photo library by looking at your albums, starting with the ones WhatsApp, Telegram, Signal, Messenger, Viber, LINE and WeChat create, and lets you review and delete it in one pass. On-device, no uploads.",
    keywords: [
      "chat media cleaner",
      "delete whatsapp photos iphone",
      "whatsapp storage iphone",
      "telegram media cleanup",
      "messaging app photos storage",
    ],
    screenshot: {
      name: "06-album-picker",
      alt: "TidyByte album picker used to select which chat media albums to review and clean.",
      caption: "Pick the chat albums, review the media, clear it.",
    },
    compare: {
      caption: "Clearing chat media compared",
      columns: ["TidyByte", "WhatsApp storage settings", "Typical paid cleaner"],
      rows: [
        {
          label: "Finds media saved by chat apps",
          cells: ["Recognised chat albums, and any album you pick", "Only its own data", "Rarely"],
        },
        {
          label: "Shows what is in the library, not the chat",
          cells: ["Yes, the Photos copies", "Chat storage only", "Varies"],
        },
        {
          label: "Sort and bulk delete",
          cells: ["By size or date, one confirmation", "Chat by chat", "Yes"],
        },
        {
          label: "Works across all messengers",
          cells: ["Yes", "WhatsApp only", "Sometimes"],
        },
        {
          label: "Uploads anything",
          cells: ["No, on-device", "No", "Often yes"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free", "Subscription"],
        },
      ],
    },
    faqs: [
      {
        q: "How do I find photos WhatsApp saved to my iPhone?",
        a: "WhatsApp and other messengers save received media into albums in your photo library, usually named after the app. TidyByte recognises the albums created by WhatsApp, WhatsApp Business, Telegram, Signal, Messenger, Viber, LINE and WeChat, and you can add any other album. It then lists that media with sizes so you can review and clear it.",
      },
      {
        q: "Does deleting these photos remove them from the chat?",
        a: "No, and that is worth understanding. TidyByte deletes the copy in your photo library, which is what counts against your storage and syncs to iCloud. The chat app keeps its own copy in its private storage, which you clear inside that app. Removing the library copy is safe and does not break the conversation.",
      },
      {
        q: "How much space does chat media take up?",
        a: "It varies enormously, because group chats share videos. It is common to find several gigabytes of saved images and video clips in chat albums, most of them memes, forwarded clips and screenshots of conversations that nobody has looked at since the day they arrived.",
      },
      {
        q: "Will clearing chat media delete anything I sent?",
        a: "It removes the library copies of what the app saved, including media you sent if auto-save was enabled for both directions. Because deletion goes through the standard iOS confirmation and lands in Recently Deleted for 30 days, anything you actually need can be restored afterwards.",
      },
      {
        q: "Why not just disable auto-save in the chat app?",
        a: "You should, and it is the right long-term fix. It does not help with the years of media already saved, though, which is why a cleanup pass and the setting work best together: clear the backlog once, then stop the refill.",
      },
    ],
    relatedTools: [
      "screenshot-cleaner",
      "large-file-cleaner",
      "photo-cleaner",
      "storage-cleaner",
    ],
    relatedPosts: [
      "/blog/how-to-clean-up-iphone-photo-library-fast",
      "/blog/iphone-storage-full-free-up-space",
      "/blog/how-to-organize-thousands-of-photos-iphone",
    ],
    ctaHeading: "Clear the chat backlog.",
    ctaBody:
      "Download TidyByte Free, review what your messengers saved, and turn years of forwarded memes into free space.",
  },
  {
    slug: "on-device-ai-photo-search",
    name: "AI photo search",
    title: "On-Device AI Photo Search for iPhone | TidyByte",
    description:
      "Search your photo library in plain English — &ldquo;dogs on a beach&rdquo; — with on-device AI. No uploads, no cloud, works offline. Free, private, no subscription.",
    h1: "On-device AI photo search for iPhone.",
    badge: "On-device AI",
    lede:
      "Describe what you are looking for and let local AI find it. The model runs on your iPhone, so nothing is uploaded and the search works offline.",
    quickAnswer:
      "TidyByte adds on-device AI search to your photo library: type a description like &ldquo;dogs on a beach&rdquo; and it matches photos by their content labels. On iPhones with Apple's on-device language model available, the search is interpreted by that model; elsewhere the same words are matched against the labels directly. Nothing is uploaded.",
    keywords: [
      "ai photo search",
      "natural language photo search",
      "on-device ai photos",
      "private photo search",
      "search photos by description iphone",
    ],
    screenshot: {
      name: "01-swipe-home",
      alt: "TidyByte home screen with the filters and entry points used to start an AI-assisted photo search.",
      caption: "Describe the photo, then act on what comes back.",
    },
    compare: {
      caption: "AI photo search compared",
      columns: ["TidyByte", "Google Photos", "Apple Photos search"],
      rows: [
        {
          label: "Where the AI runs",
          cells: ["On your iPhone", "Google's servers", "On-device"],
        },
        {
          label: "Requires an account",
          cells: ["No account exists", "Google account", "iCloud account"],
        },
        {
          label: "Works offline",
          cells: ["Yes", "No", "Partly"],
        },
        {
          label: "What it can search",
          cells: ["Visible content labels", "Content, places, people, text", "Content, places, people, text"],
        },
        {
          label: "Falls back gracefully",
          cells: ["Keyword label matching when local AI is unavailable", "Cloud only", "Varies"],
        },
        {
          label: "Cost",
          cells: ["Free", "Free with account and uploads", "Free"],
        },
      ],
    },
    faqs: [
      {
        q: "What is on-device AI photo search?",
        a: "It means the language understanding happens on your iPhone rather than on a server. You type a description in ordinary words, the on-device model turns it into content labels, and the app matches those labels against the photos it has already classified locally. Nothing is sent anywhere and it works in airplane mode.",
      },
      {
        q: "Which photos can AI search find?",
        a: "Searches match visible content: subjects like dogs, beaches, food, receipts or screens. Dates, place names, people's names and text inside images are not indexed by this feature, and the app says so in the search field rather than pretending otherwise. For those, the Photos app remains the better tool.",
      },
      {
        q: "Does the AI send my photos to a server?",
        a: "No. TidyByte performs no network requests at all, so there is no path for a photo to leave the device. On iPhones where Apple's on-device language model is available, that model interprets your search text locally; when it is not available, the app matches your words against the same local labels directly.",
      },
      {
        q: "Which iPhones support the local language model?",
        a: "It depends on Apple Intelligence availability for your device, language and region. TidyByte does not require it: when the model is unavailable, the app falls back to keyword matching against its on-device labels, and tells you which method was used in the search result.",
      },
      {
        q: "Can I delete photos directly from a search result?",
        a: "Yes. Search results behave like any other photo list in the app: select what you no longer need, confirm once, and the files move to Recently Deleted for 30 days. That makes a content search a practical way to clear a specific kind of photo, like every screenshot of a receipt.",
      },
    ],
    relatedTools: [
      "photo-organizer",
      "photo-cleaner",
      "screenshot-cleaner",
      "storage-cleaner",
    ],
    relatedPosts: [
      "/blog/how-to-organize-thousands-of-photos-iphone",
      "/blog/how-to-organize-iphone-photos",
      "/blog/how-to-use-tidybyte",
    ],
    ctaHeading: "Search your library by description.",
    ctaBody:
      "Download TidyByte Free and let local AI find the photos you have been scrolling past for years.",
  },
];

/** Rendered width/height attributes for the screenshot frames. */
export const SCREENSHOT_SIZE = { w: SCREENSHOT_W, h: SCREENSHOT_H };

export function toolBySlug(slug: string): Tool | undefined {
  return TOOLS.find((t) => t.slug === slug);
}

/** Every generated route, in render order. */
export const TOOL_ROUTES: string[] = TOOLS.map((t) => `/${t.slug}`);

// A typo in relatedTools would silently drop an internal link (the renderer
// filters unresolvable slugs), so fail the build instead.
for (const t of TOOLS) {
  for (const slug of t.relatedTools) {
    if (!TOOLS.some((x) => x.slug === slug)) {
      throw new Error(`tools.ts: ${t.slug}.relatedTools lists unknown slug "${slug}"`);
    }
  }
}

const SITE = "https://tidybyte.360ghar.com";

/** Strip the small entity set used in copy, for JSON-LD values and text lists. */
export function plain(s: string): string {
  return s
    .replace(/<[^>]+>/g, "")
    .replace(/&mdash;/g, "—")
    .replace(/&ndash;/g, "–")
    .replace(/&rsquo;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&ldquo;/g, '"')
    .replace(/&rdquo;/g, '"')
    .replace(/&amp;/g, "&")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Attribute-safe text: strip entities for display, then escape the double
 * quotes that would otherwise terminate an HTML attribute. Meta tags use
 * double-quoted attributes, so a raw " in a description breaks the page.
 */
function attr(s: string): string {
  return plain(s).replace(/"/g, "&quot;");
}

export function toolCanonical(slug: string): string {
  return `${SITE}/${slug}`;
}

/**
 * Build the PageMeta for one tool page. JSON-LD emitted here:
 *   WebPage  — ties the page to the app entity defined on the home page
 *              (#app) so answer engines resolve one product, not thirteen
 *   FAQPage  — mirrors the visible <details> list exactly
 * BreadcrumbList is added at render time by src/layouts/build-page.ts.
 */
export function toolPageMeta(t: Tool): PageMeta {
  const url = toolCanonical(t.slug);
  const webPage = {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "@id": `${url}#webpage`,
    url,
    name: plain(t.h1),
    description: plain(t.description),
    isPartOf: { "@id": `${SITE}/#website` },
    about: { "@id": `${SITE}/#app` },
    primaryImageOfPage: {
      "@type": "ImageObject",
      url: `${SITE}/assets/img/og/${t.slug}.jpg`,
      width: 1200,
      height: 630,
    },
    dateModified: "2026-10-18",
    inLanguage: "en",
    speakable: {
      "@type": "SpeakableSpecification",
      cssSelector: ["[data-quick-answer]"],
    },
  };
  const faqPage = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    "@id": `${url}#faq`,
    url,
    isPartOf: { "@id": `${url}#webpage` },
    mainEntity: t.faqs.map((f) => ({
      "@type": "Question",
      name: plain(f.q),
      acceptedAnswer: { "@type": "Answer", text: plain(f.a) },
    })),
  };
  const json = (o: unknown) =>
    JSON.stringify(o, null, 2)
      .split("\n")
      .map((l) => `  ${l}`)
      .join("\n");

  // The hub lists every tool, so it also declares the tool set as an
  // ItemList: answer engines read that as "these are the features" rather
  // than inferring it from prose.
  const children = TOOLS.filter((x) => !x.hub);
  const itemList = t.hub
    ? {
        "@context": "https://schema.org",
        "@type": "ItemList",
        "@id": `${url}#tools`,
        name: "TidyByte cleanup tools",
        description:
          "Every cleanup tool in TidyByte, the free on-device iPhone storage and photo cleaner.",
        numberOfItems: children.length,
        itemListElement: children.map((x, i) => ({
          "@type": "ListItem",
          position: i + 1,
          name: x.name,
          description: plain(x.description),
          url: toolCanonical(x.slug),
        })),
      }
    : null;

  return {
    route: `/${t.slug}`,
    title: attr(t.title),
    description: attr(t.description),
    robots: "index, follow",
    ogType: "website",
    ogImage: `${SITE}/assets/img/og/${t.slug}.jpg`,
    ogWidth: "1200",
    ogHeight: "630",
    ogUrl: url,
    canonical: url,
    fontPreload: null,
    extraScripts: [],
    headTail:
      `\n\n  <!-- Structured Data: WebPage -->\n  <script type="application/ld+json">\n${json(webPage)}\n  </script>\n` +
      (itemList
        ? `\n  <!-- Structured Data: ItemList (the tool set) -->\n  <script type="application/ld+json">\n${json(itemList)}\n  </script>\n`
        : "") +
      `\n  <!-- Structured Data: FAQPage -->\n  <script type="application/ld+json">\n${json(faqPage)}\n  </script>\n`,
    contentFile: `tool-${t.slug}`,
  };
}

export const TOOL_PAGES: PageMeta[] = TOOLS.map(toolPageMeta);
