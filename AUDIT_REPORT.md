# TidyByte — Full-Platform Audit Report

Date: 2026-08-01 · Scope: iOS app core (4 tabs + 10 cleanup tools), widget, App Intents, marketing site
Method: 9 parallel deep audits (file-by-file, flow-by-flow) + direct verification of findings + baseline build/test run.
Every finding below cites file:line. Severity: CRASH > DATA-LOSS > LOGIC > UX > PERF.

---

## 1. Master User-Story List (verified against code)

Each story: trigger → expected behavior → verdict. Full traces were produced per area; this is the consolidated register.

| ID | Feature | Story | Verdict |
|---|---|---|---|
| US-S1 | Swipe | Home offers 4 filters + default-filter hero; tap pushes a fresh session route | VERIFIED |
| US-S2 | Swipe | Specific Album picker loads albums, defers push until sheet fully dismissed | VERIFIED |
| US-S3 | Swipe | Storage bucket deep-link → pendingSwipeFilter → session; one-shot consume; >500 IDs logged | VERIFIED (silent mid-session interruption, SWIPE-11) |
| US-S4 | Swipe | Session loads assets + prefetch(10), shows spinner, empty state incl. "all swiped" | VERIFIED (no fetch-error state, SWIPE-09) |
| US-S5 | Swipe | 3-card stack, drag thresholds, rotation, haptics, accessibility actions | VERIFIED (double-swipe race, SWIPE-05) |
| US-S6 | Swipe | Keep/Delete/Add-to-album/Skip; deletions deferred until commit; full LIFO undo incl. album removal | VERIFIED |
| US-S7 | Swipe | Completion: stats, Confirm/Skip deletion, retry; commit via one performChanges | VERIFIED (exit buttons bypass confirm, SWIPE-02) |
| US-S8 | Swipe | notSwipedYet excludes records; skip/keep write records, deletions write none (asset gone) | VERIFIED (perf: full-table fetch per write, SWIPE-03) |
| US-S9 | Swipe | customAssetIds deck in creationDate order | VERIFIED (unbatched query, perf risk) |
| US-S10 | Swipe | Programmatic dismissal (deep link) cancels swipe task; in-app back routes via endSession | VERIFIED (inconsistent paths, SWIPE-11) |
| US-S11 | Swipe | Library change mid-session: no re-fetch; commit skips missing IDs (safe, stats may overstate) | VERIFIED as designed |
| US-C1 | Cleanup home | Badge counts per tool; generation-based refresh (500ms debounce); pull-to-refresh | VERIFIED |
| US-D1 | Duplicates | Exact scan: dimension pre-filter → SHA-256 streaming → groups → BestAssetSelector | VERIFIED (iCloud stall, DUP-03) |
| US-D2 | Duplicates | Visual scan: 300px feature prints → O(n²) pairwise 0.5 threshold → greedy grouping | VERIFIED (perf, DUP-01) |
| US-D3 | Duplicates | Groups per type; `.all` = exact + visual concatenated (not merged) | VERIFIED (overlap double-count, DUP-07) |
| US-D4 | Duplicates | Comparison pager: 600px thumbs, metadata, Keep-This-Best, mark-for-deletion | VERIFIED (album lookup blocks, DUP-06) |
| US-D5 | Duplicates | Delete All → confirm → atomic delete → groups <2 collapse; survivor leaves selection | VERIFIED (UX flaws, DUP-04) |
| US-D6 | Similar | Time-window chain clustering → Vision subgroups → composite quality keeper with reason | VERIFIED (degraded thumbs, DUP-08; nil-date, DUP-11) |
| US-D7 | Both | Empty states ("No Duplicates", "No Similar"); delete errors alert | VERIFIED (error state unreachable, de-slop) |
| US-E1 | Screenshots | mediaSubtypes bitmask detection; list/sort/select/delete; savings math | VERIFIED (no wallpaper misclassification) |
| US-E2 | Blurry | 512px analysis image (network off) + thumbnail fallback; blur/dark/overexposed tabs; sensitivity pref | VERIFIED (false-blurry on degraded fallback, D-03) |
| US-E3 | Smart Categories | classify → buckets → chips (non-empty only) → per-category actions | VERIFIED (accuracy risks, D-05/D-06) |
| US-E4 | D tools | Scans run in unstructured button Tasks; Task.isCancelled checks are unreachable; no cancel UI | FLAWED (D-01) |
| US-F1 | Large Files | Threshold slider re-filters live; sort options; sizes via KVC fileSize (nil-safe) | VERIFIED (label mismatch, LF-05) |
| US-F2 | Large Files | Share/export streams resources to temp folder, progress, cleanup on dismiss | VERIFIED (leak paths, LF-09) |
| US-F3 | Bursts | fetchBurstPhotos groups by burstIdentifier (representsBurst gate); best = favorite→pixels→first | PARTIAL (device-behavior risk, LF-03) |
| US-F4 | Bursts | Non-best pre-selected; keep-best; delete rest; auto-clean; groups collapse | VERIFIED (selection clobber, LF-01/LF-02) |
| US-F5 | Both | Delete: atomic performChanges, selection preserved on error, retry alert | VERIFIED |
| US-G1 | Live Photos | List, preview w/ playback, convert single/all (date/location/favorite preserved), delete | VERIFIED (duplicate risk on delete failure, COMP-02) |
| US-G2 | Video compression | Selection, presets, disk gate, batch export w/ progress polling, size-verified, save+delete, history | VERIFIED (hang risk, COMP-03; sub-1080p, COMP-11) |
| US-G3 | Photo compression | HEIC re-encode w/ size check, save+delete, history | VERIFIED (memory, COMP-07) |
| US-G4 | History | SwiftData records, mediaType defaulted, totals | VERIFIED (failed rows corrupt totals, COMP-01) |
| US-H1 | Storage | Live categories/donut; disjoint win buckets; device capacity; iCloud; 30-day trend | VERIFIED (widget parity, APP-04) |
| US-H2 | Storage | By-year buckets → customAssetIds swipe sessions | VERIFIED (huge sets, re-review of swiped) |
| US-H3 | Settings | Reminders toggle/weekday; large-file threshold; reset swipe history; about | VERIFIED (default mismatch, APP-13) |
| US-H4 | Widget | Timeline (hourly fallback), ring, links, placeholder | VERIFIED (links dead, APP-11; stale, APP-03) |
| US-H5 | Intents | 3 AppIntents → PendingRoute → drained on warm/cold launch | VERIFIED |
| US-I1 | App shell | Cold launch: container fallback, permission gate, daily scan, widget write, reminder | VERIFIED (double-scan race, APP-01) |
| US-I2 | App shell | Deep links: widget URLs + intents; onOpenURL + PendingRoute ordering | VERIFIED (scheme unregistered, APP-11) |
| US-I3 | App shell | Permission lifecycle: request → authorized/limited/denied; gate per tab | VERIFIED (grant doesn't trigger scan, APP-02) |
| US-I4 | Services | Continuation bridging: resume-exactly-once, 20s timeouts, iCloud fallbacks | VERIFIED (2 gaps: loadAVAsset, share export) |
| US-I5 | Services | Library change observation → debounced generation → Cleanup/Storage re-sync | VERIFIED (swipe/widget not covered) |
| US-J1 | Site | Home page sections, CTAs, FAQ, footer | VERIFIED (CTA mislabel, SITE-09) |
| US-J2 | Site | Blog: 54 posts, hub with filter/pagination | FLAWED (all posts 404, SITE-01/02) |
| US-J3 | Site | SEO: sitemap, robots, llms, canonical, structured data | FLAWED (54 dead sitemap URLs, SITE-03) |
| US-J4 | Site | Support/privacy/404 consistency | VERIFIED (FAQ schema mismatch, SITE-11) |

---

## 2. Error Registry (documented, to be fixed)

### App shell & navigation
| ID | Sev | Finding | Location |
|---|---|---|---|
| APP-01 | PERF+DATA | Cold launch double-fire race: `.task` + `.onChange(scenePhase)` both enter handleSceneActivation before the once-per-day marker is written → two full library enumerations + two StorageSnapshot rows/day | TidybyteApp.swift:31-38, 82 |
| APP-02 | UX | First-launch permission grant never triggers the daily scan (no re-invoke on authorization) → empty widget/trend/reminder on day one | TidybyteApp.swift:42-46; PhotoPermissionHandler |
| APP-03 | UX | Widget + storage trend stale after in-app cleanup — snapshot only written on activation, never on LibraryChangeMonitor generation | TidybyteApp.swift:118-170 |
| APP-04 | LOGIC | Widget reclaimable ≠ dashboard: large videos not halved, two win buckets missing → contradictory numbers | TidybyteApp.swift:123-133 vs StorageDashboardViewModel.swift:188-296 |
| APP-05 | UX | Haptic fires on programmatic tab switches (widget/intent/deep-link), not just user taps | RootView.swift:56-58 |
| APP-06 | LOGIC | Threshold re-derived `Int64(mb*1_000_000)` in 3 places instead of AppPreferences.largeFileThresholdBytes() | TidybyteApp.swift:119,194; CleanupHomeViewModel.swift:67 |
| APP-07 | UX | External dismissal of a swipe session drops pending deletions without review (in-app back routes through endSession) | SwipeSessionView.swift:121-123 |
| APP-08 | PERF | SwipeRecord fetch: full-table fetch per swipe/undo + per session load | SwipeSessionViewModel.swift:349-354, 380-387 |
| APP-09 | PERF | Main-actor O(n) asset passes (9 filter/reduce passes over whole library) during daily scan | TidybyteApp.swift:84-211 |
| APP-10 | PERF | SwipeHomeView holds `let photoService = PhotoLibraryService()` in a View struct → new actor per body eval | SwipeHomeView.swift:17 |
| APP-11 | LOGIC | **Widget deep links dead: `tidybyte://` scheme never registered** (no CFBundleURLTypes anywhere) | project.yml; Tidybyte/Info.plist; StorageWidgetView.swift:34 |
| APP-12 | LOGIC | Widget "N to clean" double-counts screenshots ≥ threshold | StorageWidgetView.swift:27 |
| APP-13 | LOGIC | Reminder weekday default mismatch (@AppStorage 1 vs AppPreferences 0) → daily refresh never updates reminder copy | SettingsView.swift:30; AppPreferences.swift:112-114 |
| APP-14 | LOGIC | Weekday change with revoked notification permission silently no-ops | SettingsView.swift:178-181 |
| APP-15 | DATA | StorageSnapshot rows never pruned (30-day read filter only); race can insert 2/day | StorageDashboardViewModel.swift:386-393; TidybyteApp.swift:108 |
| APP-16 | PERF | Dashboard pull-to-refresh not serialized vs generation sync → concurrent enumerations | StorageDashboardViewModel.swift:102-129 |
| APP-17 | LOGIC | CLAUDE.md/AGENTS.md claim "iPhone only" — app is universal (TARGETED_DEVICE_FAMILY 1,2) | docs |

### Swipe
| ID | Sev | Finding | Location |
|---|---|---|---|
| SWIPE-01 | PERF | Prefetch cache never released mid-session; stopCaching unused; plain-back path never stops caching; service retained by home view | SwipeSessionViewModel.swift:133-139,316-322; PhotoLibraryService.swift:487-507 |
| SWIPE-02 | LOGIC | "Start Another Session" doesn't start a session (pops home) and both completion nav buttons silently discard pending deletions | SessionCompletionView.swift:106,119,135 |
| SWIPE-03 | PERF | upsertSwipeRecord fetches entire table per write, filters in Swift (quadratic with history) | SwipeSessionViewModel.swift:327-365 |
| SWIPE-04 | PERF | Session startup: 1–2 full-library passes + full record fetch before first card | SwipeSessionViewModel.swift:116-131 |
| SWIPE-05 | LOGIC | Double-swipe within 200ms: swipeTask cancel vs sleep race → dropped advance or card yank | SwipeSessionView.swift:385-392 |
| SWIPE-06 | LOGIC | undo() allowed while album picker presented → deck rewinds under sheet | SwipeSessionViewModel.swift:238-276 |
| SWIPE-07 | UX | Video cards show poster only; no playback affordance while swiping | CardView.swift:22-30 |
| SWIPE-08 | LOGIC | "Storage Freed" overstates when assets vanished externally before commit | SwipeSessionViewModel.swift:278-291 |
| SWIPE-09 | UX | Fetch failure surfaces as "All Caught Up!" (fetchAssets can't throw) | SwipeSessionView.swift:318-357 |
| SWIPE-10 | LOGIC | SwipeFilter.id uses Set.hashValue (per-process randomized identity) | SwipeHomeView.swift:257 |

### Duplicates & Similar
| ID | Sev | Finding | Location |
|---|---|---|---|
| DUP-01 | PERF | Visual scan O(n²) over ALL photos, no pre-filter; comparison phase dominates wall time | DuplicateDetectionService.swift:96-114 |
| DUP-02 | UX | No cancellation anywhere: unstructured button Task, no cancel UI, scan survives leaving screen, re-entry double-scans | DuplicateFinderView.swift:77; SimilarPhotosView.swift:110-115 |
| DUP-03 | PERF | Exact scan downloads every non-local asset (20s cap each, network allowed) — hours on iCloud libraries; isLocallyAvailable unused | PhotoLibraryService.swift:455-497; DuplicateDetectionService.swift:31-66 |
| DUP-04 | UX | "Delete All" deletes union of all group selections; no per-group delete, no Delete-Selected bar, no Select/Deselect All; "Delete 0 Items" + success haptic | DuplicateFinderView.swift:25-33,44-49 |
| DUP-05 | UX | No way to change scan type after results (no "New Scan"; Similar has one) | DuplicateFinderView.swift |
| DUP-06 | PERF | Album membership O(assets × albums) sync fetches block thumbnails | DuplicateComparisonView.swift:151-155; SimilarGroupDetailView.swift:139-143 |
| DUP-07 | LOGIC | Same asset can appear in exact AND visual group; counts double-count | DuplicateFinderViewModel.swift:47-53 |
| DUP-08 | LOGIC | Similar quality scores on degraded 300px fastFormat thumbnails → unreliable keeper on iCloud | SimilarPhotosViewModel.swift:150-152 |
| DUP-09 | UX | Delete has no feedback (isDeleting never surfaced) | DuplicateFinderViewModel.swift:101; SimilarPhotosViewModel.swift:198 |
| DUP-10 | LOGIC | Post-delete best re-pick duplicates BestAssetSelector with divergent criteria | DuplicateFinderViewModel.swift:146-152 |
| DUP-11 | EDGE | nil-creationDate photos cluster together at .distantPast (O(n²) risk) | SimilarPhotosViewModel.swift:90-93 |
| DUP-12 | UX | Progress bar stalls at 0% during candidates/Phase-1; comparison phase under-reports | DuplicateDetectionService.swift:92,115 |

### Screenshots / Blurry / Smart Categories
| ID | Sev | Finding | Location |
|---|---|---|---|
| D-01 | UX | Scans launched from unstructured button Tasks; no cancel button; Task.isCancelled unreachable; re-entry double-scans (all 3 tools) | BlurryPhotosView.swift; SmartCategoriesView.swift; ScreenshotCleanerView.swift |
| D-02 | LOGIC | Blurry VM doesn't clear selectedIds on rescan (SmartCategories does) → stale selections persist | BlurryPhotosViewModel.swift:23-25 |
| D-03 | LOGIC | iCloud fallback uses degraded fastFormat thumbnail → soft image → false "blurry" flags | BlurryPhotosViewModel.swift:44-50 |
| D-04 | LOGIC | Blurry analyzes ALL images incl. screenshots + Live Photo stills (fetchAllPhotos = mediaType image) — eligibility review | PhotoLibraryService.swift:195-204 |
| D-05 | ACCURACY | taxonomyToBucket identifier matching untested against real VN identifiers | PhotoCategorizationService.swift |
| D-06 | UX | "Saved from Apps" bucket is recall-heavy by design (documented) — huge category for many users | PhotoCategorizationService.swift |
| D-07 | UX | Screenshots empty state has no refresh affordance | ScreenshotCleanerView.swift |

### Large Files & Bursts
| ID | Sev | Finding | Location |
|---|---|---|---|
| LF-01 | DATA-LOSS-ADJ | refresh() recomputes best frames + re-selects all non-best, discarding user's keep choices | BurstCleanerViewModel.swift:75-91 |
| LF-02 | DATA-LOSS-ADJ | Post-delete selectNonBestFrames() re-arms explicitly deselected (kept) frames for deletion | BurstCleanerViewModel.swift:136; same pattern DuplicateFinderViewModel.swift:108 |
| LF-03 | LOGIC | Grouping requires asset.representsBurst — if representative-only (Apple docs reading), tool always empty on device; unverifiable on simulator | PhotoLibraryService.swift:205-217 |
| LF-04 | UX | Burst preview passes frozen snapshot; in-preview delete leaves stale pager | BurstCleanerView.swift:73-78,143-151 |
| LF-05 | UX | "Min size: 10 MB" decimal vs ByteCountFormatter binary → threshold files display "9.5 MB" | LargeFilesView.swift:30; Int64+FileSize.swift:5 |
| LF-06 | LOGIC | thresholdMB in-memory copy diverges from live defaults when Settings changes while tool open | LargeFilesViewModel.swift:34-44 |
| LF-07 | PERF | filteredAssets uncached; 5× sort per render | LargeFilesViewModel.swift:46-87 |
| LF-08 | PERF | Full-library enumeration + per-asset resource calls on every push; home runs 4-5 concurrent enumerations | LargeFilesViewModel.swift:94-102; CleanupHomeViewModel.swift:52-77 |
| LF-09 | ROBUST | Temp export folder leaks: all-fail path and VM-dealloc-mid-export path | LargeFilesViewModel.swift:141-179 |
| LF-10 | ROBUST | fileSize KVC=0 silently hides huge assets from the tool | PhotoLibraryService.swift:555-563 |
| LF-11 | UX | No pull-to-refresh in empty states | LargeFilesView.swift:57-66; BurstCleanerView.swift:21-25 |
| LF-12 | LOGIC | setBest force-inserts old best even when user explicitly deselected it | BurstCleanerViewModel.swift:93-98 |
| LF-13 | ROBUST | `sorted[0]`/`assets[0]` assume non-empty | BurstCleanerViewModel.swift:56,183 |

### Live Photos / Compression
| ID | Sev | Finding | Location |
|---|---|---|---|
| COMP-01 | LOGIC | History "Total saved" sums failed records (compressedSize=0) → giant green savings for failures; "-0 B" rows | CompressionHistoryView.swift:7-9,82-85 |
| COMP-02 | DATA | Delete-original failure leaves saved replacement → duplicate; retry duplicates again; no rollback | LivePhotosConverterViewModel.swift:226; VideoCompressionService.swift:161; PhotoCompressionService.swift:119 |
| COMP-03 | ROBUST | loadAVAsset has no timeout (bare continuation, no ContinuationResumer) → video hangs in .exporting forever on stalled iCloud | VideoCompressionService.swift:173-193 |
| COMP-04 | UX | Skipped items silently vanish from list after batch (no "No savings" explanation) | VideoCompressionViewModel.swift:208; PhotoCompressionViewModel.swift:208 |
| COMP-05 | UX | MediaPreviewView delete leaves deleted item in pager (assets captured at presentation; onChange never fires) | MediaPreviewView.swift:33,48; VideoCompressionView.swift:90-97 |
| COMP-06 | MEM | "High Quality" preset decodes full-res bitmap (no MaxPixelSize cap) — jetsam risk on 48MP | PhotoCompressionService.swift:150-165 |
| COMP-07 | LOGIC | iCloud-only: fileSize KVC=0 → savings check trivially true, original replaced, 0-size history record | VideoCompressionService.swift:195-205; PhotoCompressionService.swift:185-194 |
| COMP-08 | UX | No cancellation for batches; unstructured Tasks continue after leaving screen; cancelExport never called | VideoCompressionView.swift:52-57; VideoCompressionViewModel.swift:144 |
| COMP-09 | LOGIC | Convert All reports only last error; success haptic even when all items failed | LivePhotosConverterViewModel.swift:126-131 |
| COMP-10 | LOGIC | Default 1080p preset fails on sub-1080p sources (common first-run failure) | VideoCompressionService.swift:12; VideoCompressionViewModel.swift:35-38 |
| COMP-11 | UX | Per-item error alert pops mid-batch while loop continues | VideoCompressionViewModel.swift:186-205 |
| COMP-12 | LOGIC | Batch order nondeterministic (Set iteration) | VideoCompressionViewModel.swift:144 |
| COMP-13 | PERF | LivePhotoPreviewView album lookup O(items × albums) serial | LivePhotoPreviewView.swift:47-54 |
| COMP-14 | MEM | LivePhotoPlayerView teardown only in dismantleUIView; TabView keeps adjacent pages alive | LivePhotoPlayerView.swift:63-66 |
| COMP-15 | ROBUST | Photo album restore silent try? without logging (video/live log it) | PhotoCompressionService.swift:115-117 |
| COMP-16 | DATA | Re-compression of already-compressed media not excluded (no history check) → quality degradation | VideoCompressionViewModel.swift:36-39 |
| COMP-17 | DATA | Live Photo/video/photo conversion drops `hidden` state (and burst linkage); photo alert discloses, video/live don't | LivePhotosConverterViewModel.swift:200-210 |
| COMP-18 | LOGIC | Preview Convert enabled during Convert All → double-spinner, double counts | LivePhotoPreviewView.swift:258-280 |

### Shared infra & services
| ID | Sev | Finding | Location |
|---|---|---|---|
| SHARED-01 | LOGIC | deleteAssets all-or-nothing: one undeletable asset fails the whole batch, user retries forever | PhotoLibraryService.swift:511-516 |
| SHARED-02 | LOGIC | addToAlbum/removeFromAlbum throw misleading albumNotFound | PhotoLibraryService.swift:525-534,544-553 |
| SHARED-03 | UX | 0 fileSize renders "Zero KB" in metadata + delete confirmations | Int64+FileSize.swift:4 |
| SHARED-04 | UX | AsyncThumbnailView resets state before cache consult → skeleton flash on every re-appear | AsyncThumbnailView.swift:28-36 |
| SHARED-05 | LOGIC | Degraded fastFormat thumbnails cached for session; after download, grids stay soft until eviction | AsyncThumbnailView.swift:42-43 |
| SHARED-06 | UX | Failed preview image load never retries (loadedAssetId set early) | MediaPreviewView.swift:309-318 |
| SHARED-07 | ROBUST | writeResourceToTemp wires timeout AFTER issuing request; write has no cancellation API; orphaned timeout task + folder cleanup race | PhotoLibraryService.swift:708-725 |
| SHARED-08 | LOGIC | ImageCache never invalidated on library change → stale thumbnails after Photos edits | ImageCache.swift |

### Marketing site
| ID | Sev | Finding | Location |
|---|---|---|---|
| SITE-01 | LOGIC | **All 54 blog posts 404 in production**: extensionless links/canonicals/sitemap vs .html files; no /blog/* rewrite in netlify.toml, _redirects, or serve.py | netlify.toml; _redirects; site/blog/* |
| SITE-02 | LOGIC | Blog hub inline JS blocked by CSP script-src 'self' → filters/pagination dead | blog/index.html:782; netlify.toml:24 |
| SITE-03 | SEO | Sitemap: 59 URLs, 54 dead (consequence of SITE-01) | sitemap.xml |
| SITE-04 | LOGIC | Missing assets: favicon.svg (~20 posts), logo.svg (~8 posts JSON-LD) | blog/*.html |
| SITE-05 | LOGIC | Stale versioning: "v1.0 — Latest" changelog, softwareVersion 1.0; app is 1.0.2 | changelog.html:72; index.html:51; llms-full.txt:107 |
| SITE-06 | LOGIC | False "iPad compatibility mode" claim in 6 places; app is universal | index.html:172-175,507-510; support.html:285-288; changelog.html:118; llms.txt:11; llms-full.txt:11 |
| SITE-07 | SEO | og:image is 1.38MB SVG — unsupported by social scrapers → no preview cards | index.html:15; all posts |
| SITE-08 | PERF | Hero LCP is 2.98MB preloaded PNG | index.html:33,249 |
| SITE-09 | UX | "How it works" CTA → #features instead of #how-it-works | index.html:242 vs 266 |
| SITE-10 | LOGIC | 3 dead in-content blog links (5 occurrences) | how-to-clean-up-blurry-shaky-photos.html:290,306-307; swipe-left-right-organize-photos.html:204 |
| SITE-11 | SEO | support.html FAQPage schema (7 Qs) ≠ visible FAQ (8 Qs); duplicate FAQPage schemas on index+support | support.html:36-56 |
| SITE-12 | SEO | article:published_time format inconsistent (T00:00:00Z vs date-only) | blog posts |
| SITE-13 | UX | dark-mode class inconsistency; theme-color advertises non-existent light mode | blog posts; index.html |
| SITE-14 | DOC | README references assets/img/downloads/ that doesn't exist | site/README.md:31-32 |

---

## 3. De-Slop Registry (removal/consolidation candidates)

Confirmed dead code (definition-only, grep-verified):
1. `AppLog.ui` — AppLog.swift:17
2. `PhotoPermissionView` .limited/.authorized branches unreachable (gate handles them) — PhotoPermissionView.swift:69-88
3. Color+Theme: `secondaryBackground`, `tertiaryBackground`, `appAccent`, `photoCategory`, `videoCategory`, `screenshotCategory`, `livePhotoCategory`, `elevatedSurface`, `accentGradient`, `headerGradient`, `destructiveGradient`, `successGradient`, `glowShadow`, `CornerRadius.extraLarge` — Color+Theme.swift
4. `View.regularWidthPadding` + modifier — View+Responsive.swift:63-76
5. `SkeletonCard` — SkeletonView.swift:159-173
6. `EmptyStateView.appeared` — EmptyStateView.swift:9
7. `ShimmerOverlayModifier.cornerRadius` — SkeletonView.swift:5
8. `LivePhotoPlayerView.onPlaybackStart/onPlaybackEnd` (+ coordinator mirror) — LivePhotoPlayerView.swift:17-18
9. `PhotoLibraryService.requestAuthorization()`, `currentAuthorizationStatus()`, `stopObservingChanges()` (deinit covers), `PhotoServiceError.unauthorized` — PhotoLibraryService.swift:42-51,68-73,887-888
10. `ScanState.error` — never assigned; errorView dead in Duplicate/Similar/Blurry/SmartCategories
11. `StorageAction.url` case — StorageDashboardView.swift:800-802
12. `ReclaimWin.icon` field — StorageDashboardViewModel.swift:254-282
13. Widget: unreachable `default: mediumView` (supportedFamilies fixed); `WidgetSnapshot.libraryBytes` written never rendered — StorageWidgetView.swift:12-13; WidgetSnapshot.swift:7
14. `CompressionProgress` — VideoCompressionService.swift:18-22; `estimateCompressedSize` (service) — :50-62; `CompressionState.saving` unreachable — :36
15. `SwipeSessionViewModel.resetForNewSession()` — tests only; `SessionStats.totalReviewed` — tests only; `CardView.isLoadingImage` — written never read
16. `fetchAssets(filter:swipedIdentifiers:)` param + service `.notSwipedYet` case — no caller passes the param
17. `AssetSummary.formattedFileSize` re-implements Int64+FileSize — AssetSummary.swift:51
18. `AlbumPickerSheet` inline AsyncAlbumThumbnail ≈ verbatim copy of AsyncThumbnailView — AlbumPickerSheet.swift:255-276
19. `GlassCard` struct vs `glassCard` modifier — duplicate rendering paths
20. `preferredBestAsset` duplicates BestAssetSelector — DuplicateFinderViewModel.swift:146-152; BurstCleanerViewModel.swift:179-184

Consolidation targets (aggressive de-slop, behavior-preserving):
- `MediaLibraryStats` shared builder: TidybyteApp.recordStorageSnapshot + StorageDashboardViewModel.buildCategories + widget reclaimable math (fixes APP-04)
- `DeviceCapacityReader` shared: TidybyteApp.readDeviceCapacity + StorageDashboardViewModel.fetchDeviceStorage
- Threshold: single `AppPreferences.largeFileThresholdBytes()` everywhere (fixes APP-06, LF-06-related)
- Selection machinery: Duplicate/Similar/Burst VMs share the same selection/delete pattern (~60 lines × 3)
- StorageDashboardView 806 lines → extract skeleton + 8 section views
- Video/Photo compression stacks near-total duplication (stable; consolidate cautiously — lower priority)
- Swipe haptics → HapticHelper (minor)
- `DuplicateGroup: Hashable` lives in DuplicateFinderView.swift; `ScanState` in DuplicateFinderViewModel.swift; `Array.safe` global in DuplicateComparisonView.swift → move to shared locations

---

## 4. Work-Package Assignment (Phase 3)

| WP | Owner | Files | Bugs |
|---|---|---|---|
| WP-1 | Core shell | TidybyteApp, RootView, AppNavigation(partial), AppPreferences, LibraryChangeMonitor, NotificationService, StorageDashboard V+VM, widget, AppIntents, Info.plist, project.yml, shared components/extensions/utilities, PhotoLibraryService, AssetSummary, CleanupHomeViewModel | APP-01..06, APP-09, APP-11..17, SHARED-01..03,07, de-slop 1-4,6-9,11-13,17-19 |
| WP-2 | Swipe | SwipeHomeView, SwipeSessionView, SwipeSessionViewModel, CardView, SessionCompletionView, SwipeSessionRoute | SWIPE-01..11, APP-07, APP-08, APP-10, de-slop 15,16 |
| WP-3 | Duplicates/Similar | Duplicate* files, Similar* files, DuplicateDetectionService, VisionAnalysisService(usage), BestAssetSelector, SelectAllToolbarButton wiring | DUP-01..12, de-slop 10,20 |
| WP-4 | D tools | Screenshot*, Blurry*, SmartCategories*, PhotoCategorizationService | D-01..07 |
| WP-5 | LargeFiles/Bursts | LargeFiles*, Bursts*, (burst fetch change routed via WP-1 service edit) | LF-01..13 |
| WP-6 | Compression | LivePhotos*, VideoCompression*, PhotoCompression*, CompressionHistoryView, services, MediaPreviewView | COMP-01..18, SHARED-06 |
| WP-7 | Site | site/*, blog/*, src/, netlify.toml, serve.py | SITE-01..14 |

---

## 5. Validation protocol (Phase 4)

1. `xcodebuild -project Tidybyte.xcodeproj -scheme Tidybyte -destination 'platform=iOS Simulator,name=iPhone 13 Pro Max,OS=26.5' test` — all existing 43 tests + new tests must pass
2. `npm run build` (site) must succeed
3. No new warnings introduced in build output
4. Re-read of every modified file (no dead code left behind, conventions preserved)

---

## 6. Resolution status (post-fix, 2026-08-01)

All registered issues were fixed by 7 parallel work packages (WP-1 app shell/core services, WP-2 swipe, WP-3 duplicates/similar, WP-4 screenshots/blurry/categories, WP-5 large files/bursts, WP-6 compression/live photos, WP-7 site). Fix counts per registry: APP 17/17, SWIPE 10/10, DUP 12/12, D-01..07 (7/7), LF 12/13, COMP 18/18, SHARED 8/8, SITE 14/14 — plus 20 de-slop removals/consolidations.

### Key fixes by area
- **App shell**: once-per-day scan race eliminated (`WidgetSnapshotCoordinator` with `isScanning` guard); permission-grant now triggers the scan; widget refreshes after in-app cleanups (generation-driven, debounced); **`tidybyte://` scheme registered in Info.plist — widget deep links now work**; reclaimable math unified via `MediaLibraryStats` + `ReclaimBucketer` (widget == dashboard, parity-tested); haptics only on user tab taps; reminder weekday default unified to 1; snapshots pruned >60 days; `deleteAssets` retries per-item and reports partial failures; burst grouping now by `burstIdentifier` alone (no `representsBurst` gate).
- **Swipe**: prefetch cache released per-window and on every exit; pending deletions can never be dropped silently (completion review gate on all exits, incl. deep-link dismissal); "Start Another Session" renamed and gated; swipe animations serialized (no dropped advances); lazy album-membership resolution; predicate-based SwipeRecord upserts; video playback on cards; retry on fetch-failure empty state.
- **Duplicates/Similar**: visual scan pre-filtered by perceptual hash (no raw O(n²)); scans cancellable + guarded against double-run; iCloud-only assets skipped in exact scan with count surfaced; per-group delete + Delete-Selected bar + Select All; New Scan button; `.all` no longer double-lists assets across exact/visual; quality scoring uses high-res analysis images; nil-date cluster cap; shared `SelectionState`.
- **Screenshots/Blurry/Categories**: cancellable scans in all three tools; blurry rescan clears selection; fallback-analysis flagged in UI; screenshots excluded from blurry analysis (count surfaced); robust taxonomy normalization + tests; saved-from-apps caption; empty-state refresh.
- **Large Files/Bursts**: user keep-choices preserved across refresh and post-delete (no more re-arming kept frames); best-pick semantics fixed (`setBest` no longer force-inserts deselected frames); live preview data (no frozen snapshot); threshold slider backed by shared preference; filtered list cached; share-export folder leak paths closed; unknown-size count surfaced; empty-state refresh; index-safety guards.
- **Compression**: history totals exclude failed records; delete-failure now rolls back the saved replacement (no duplicates); `loadAVAsset` timeout (no more infinite export hang); skipped items stay visible with reasons; preview pager resolves assets live; full-res decode capped (6144px); iCloud-only size-unknown items skipped; batch cancellation; aggregated error summaries; deterministic batch order; memoized album names; live-photo teardown on page switch; `isHidden` preserved; already-compressed items skipped; default preset never upscales.
- **Shared**: `deleteAssets` per-item retry; corrected `albumChangeFailed` error; `displaySize` for unknown sizes; cache invalidation on library change; timeout wiring fixed for share export; `AsyncThumbnailView` cache-first read; failed preview loads retry.
- **Site**: all 54 blog posts now resolve (netlify.toml + serve.py rewrite); blog hub JS moved to `blog.js` (CSP-safe); sitemap 59/59 live; favicon.svg + logo.svg created; versioning updated to 1.0.2 (changelog + schema); iPad "compatibility mode" claims corrected in 6 places; og:image switched to PNG; hero preload removed; CTA fixed; dead links retargeted; FAQ schema aligned; published_time normalized; README corrected. **0 broken links across 1,701 href/src in 60 files.**

### Corrections to the original audit
- **LF-05 was a false positive**: `ByteCountFormatter` with `.file` style is decimal (10,000,000 B → "10 MB"), so the "decimal label vs binary row" mismatch never existed. The fix (single shared label builder) still landed as hygiene; the regression test pins the label == rows invariant.
- **LF-03 (burst predicate)**: fixed in the service as suspected; grouping by `burstIdentifier` alone is the safer reading of Apple's docs.
- **COMP-06**: decode cap set to 6144px (not 8192) — 8192 wouldn't bound a 48MP decode; 6144 halves the peak bitmap while leaving ≤12MP photos untouched.

### Validation results
- Baseline: 43 tests passed on the untouched tree.
- Final: **108 tests, 0 failures** (65 new regression tests added), app build clean, `plutil` lint OK, `npm run build` exit 0, netlify.toml parses, site link-check 0 broken.
- One integration bug found during validation and fixed: `SelectionState.setBest`'s no-op path cleared the deletion set (guard added).
- The Xcode project file is generated (`xcodegen` from `project.yml`); regenerated to include all new files. New files: `MediaLibraryStats`, `WidgetSnapshotCoordinator`, `SharedSelection`, `AlbumMembershipLoader`, `Array+Safe`, 6 new test files, site `blog.js`/`favicon.svg`/`logo.svg`.

