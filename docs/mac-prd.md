# TidyByte for macOS — Product Requirements

Tech-agnostic feature spec. Describes **what** the Mac app does and how it
behaves, not how it is built. Source: the shipped iOS app in `Tidybyte/`
plus `docs/prd.md`.

Locked decisions for v1:

1. Folder Mode **and** Full Mac Mode both ship in v1.
2. Deletes move files to the **Trash** (recoverable until emptied).
3. Ships via **both** the Mac App Store and direct download.

---

## 1. Scope model

### 1.1 Folder Mode

1. User picks any folder through the system folder picker.
2. The app lists **all nested files recursively**, not just top-level items.
3. Hidden files and system metadata (e.g. `.DS_Store`) are excluded silently.
4. Switching folders re-scans; per-folder review state persists across launches.

### 1.2 Full Mac Mode

Scans these preset locations in one pass:

1. Pictures, Movies, Music, Downloads, Documents, Desktop.
2. The user can toggle any location off before scanning.
3. System paths (`/System`, `/Library`, `~/Library`, app bundles) are **never
   listed and never deletable**.

### 1.3 What gets listed

In-scope file kinds: images, videos, PDFs, audio, documents, archives.
Alias/symlink files are shown with their target path and trashed as links
(the target is never followed for deletion).

---

## 2. Previews

Every review surface shows a real preview, not just a filename:

1. **Images** — full preview with zoom.
2. **Video** — thumbnail plus duration; inline playback with scrubber.
3. **PDF** — first-page thumbnail; page-through preview with page count.
4. **Audio** — inline playback with duration and waveform-or-progress UI.
5. **Anything else** — system Quick Look preview as the fallback.

Each preview carries one metadata line: file size, kind-specific facts
(dimensions, duration, page count), and last-modified date.

---

## 3. Swipe review (core flow)

Mirrors the iOS card stack, adapted for desktop input.

### 3.1 Gestures and keys

| Action | Trackpad / mouse | Keyboard |
|---|---|---|
| Move to Trash | Swipe/drag left, or ✕ button | `Delete` |
| Keep | Swipe/drag right, or ✓ button | `→` |
| Move to folder | Swipe/drag up, or folder button | `↑` opens folder picker |
| Skip | ➤ button | `Space` |

A half-finished drag snaps back. Trashing a file never asks twice inside a
session; the single end-of-session confirm covers the batch.

### 3.2 Session filters

1. **Not Reviewed Yet** (default) — files with no review record.
2. **Everything Here** — every listed file, newest first.
3. **Before a Date** — files modified on or before a chosen date.
4. **One Subfolder** — scope the session to a single nested folder.
5. **Largest First** — files sorted by size descending.

### 3.3 Session end

The completion screen shows trashed / kept / moved / skipped counts plus
total size moved to Trash, with two buttons: **Start Another Session** and
**Go to Cleanup Tools**.

---

## 4. Cleanup tools

Home screen groups tools exactly like iOS: **Free Up Space**
(delete what you don't need), **Review & Organize** (decide what's worth
keeping), **Reclaim Without Deleting** (keep everything, use less room).
Each tool shows a live item-count badge; tools needing a full scan show
"Not scanned" until one runs.

### 4.1 Free Up Space

1. **Duplicates** — exact matches by content hash plus visual near-matches
   for images. Groups shown as thumbnail strips; one file per group is
   pre-marked "Best" (highest quality, then newest). "Delete all others"
   per group plus "Auto-clean all" with a confirm dialog.
2. **Similar Files** — files created/modified within a short window
   (default 5 seconds, adjustable). Sharpest/earliest kept by default;
   user confirms before the rest are trashed.
3. **Blurry Images** — out-of-focus, too-dark, and overexposed images in
   three tabs with a subtle quality indicator per thumbnail.
4. **Large Files** — everything sorted by size descending with a minimum-size
   slider (default 10 MB). The delete button shows a running total
   ("Delete 3 items · 847 MB"). Filters: All / Images / Videos / Documents.
5. **Burst Sequences** — filenames with burst/sequence patterns grouped;
   best frame pre-selected, "delete rest" per group plus auto-clean-all.
6. **Screen Recordings** — grid review scoped to screen-capture videos,
   with sort (newest/oldest/largest) and batch trash.

### 4.2 Review & Organize

1. **Screenshots** — grid of all screenshots, newest first, with sort,
   multi-select, batch trash, and "Review with Swipe".
2. **Smart Categories** — images sorted into Memes / Documents / Food /
   Pets / Nature / Selfies / Saved-from-Apps / Other, each reviewable and
   trashable as a batch. Sensitivity adjustable (Strict / Balanced / Broad).
3. **Downloads & Chat Media** — files from messaging/download folders with
   an explicit note that trashing removes the local copy only, not the copy
   inside the chat app.

### 4.3 Reclaim Without Deleting

1. **Video Compression** — presets 1080p / 720p / 480p with estimated output
   size shown before running. Original is trashed only after the compressed
   copy verifies. Per-file progress, max two concurrent jobs, history log
   with before/after sizes.
2. **Image Compression** — quality presets with estimated savings, same
   verify-then-trash flow and history as video.
3. **Duplicate-Format Pairs** — RAW+JPEG, HEIC+JPEG, and Live-Photo-style
   still/video pairs (Mac photo libraries and camera imports); convert or
   keep-one-side with savings shown first.

---

## 5. Storage dashboard

1. **Folder breakdown** — donut chart of Images / Videos / Documents /
   Audio / Archives / Other with item counts and sizes; legend rows for
   actionable categories jump to the matching tool.
2. **Reclaim hero** — "You Could Free" card with tappable segments per
   opportunity and one primary "Review now" button for the biggest win.
3. **Volume bar** — used vs available space on the scanned volume, with a
   written "Almost full" warning above 90% (never color alone).
4. **Where Space Goes** — buckets by year and by source folder; each row
   opens a swipe session scoped to that bucket.
5. **Trend** — daily size snapshots with a line chart once two exist, plus
   an honest span label ("Library shrank by 2.1 GB in 6 days").
6. **Trash shortcut** — space only returns when the Trash is emptied, so a
   permanent card shows the Trash size with an "Empty Trash" action.

---

## 6. Activity & Savings

Lifetime ledger of everything the app trashed or compressed:

1. Hero total (size + item count) with the note that space returns after
   the Trash is emptied.
2. 30-day bar chart of reclaimed space.
3. Per-tool breakdown (which tool freed what).
4. Recent 25 events with date, tool, item count, and size.

---

## 7. Settings and reminders

1. Similar-file time window slider (1–60 seconds).
2. Blur sensitivity (Low / Medium / High).
3. Smart-category sensitivity (Strict / Balanced / Broad).
4. Large-file threshold slider (5–500 MB).
5. Default swipe filter picker.
6. Compression default presets (video + image).

Separately: an optional **weekly cleanup reminder** (day picker, off by
default) quoting the last scan's real numbers, e.g. "214 screenshots
(1.2 GB) to review." Tapping it opens Cleanup. Plus **Reset Review
History** with a confirm dialog, and an About section (version, build,
"all processing happens on this device").

---

## 8. Safety contract

1. Every delete moves to the **Trash**. Nothing is permanently deleted
   by the app, ever.
2. Destructive batch actions confirm once, stating exactly what happens.
3. System and app-bundle paths can never appear in any review list.
4. After any trash batch, a dismissible notice states the count and size
   moved to Trash and how to empty it. Cancelled or failed runs show nothing.
5. The app holds no accounts and sends no data anywhere; all scanning and
   analysis runs on the device.

---

## 9. Cross-cutting behavior

1. **Progress + cancel** — every scan, analysis, and compression shows live
   progress and a working cancel button. The UI never locks.
2. **Freshness** — results refresh when files change on disk; stale counts
   are marked "Not scanned" rather than shown.
3. **States** — skeleton placeholders while loading; every empty list gets
   an icon plus a one-line explanation (including a full-access onboarding
   primer on first launch).
4. **Keyboard-first** — every action has a key equivalent; full VoiceOver
   labels on cards, counts, and charts.
5. **Deep links** — the reminder and any shortcuts route to Cleanup, Swipe,
   or Activity directly.

---

## 10. Out of scope for v1

1. Cloud or networked drives (local disks and mounted folders only if they
   behave like local paths; cloud-only placeholder files are listed but
   flagged "not downloaded" and skipped by scans).
2. Photo-library management inside Apple Photos (albums, faces, iCloud
   optimization tips) — file-level cleanup only.
3. Syncing review state between Macs.
4. Anything that permanently deletes, encrypts, or modifies file contents
   outside the two compression tools.
