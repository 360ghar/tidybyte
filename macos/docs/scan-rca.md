# Scan RCA — why scans took so long and appeared to return nothing

Root-cause analysis of the two complaints "the scan takes forever" and "it
almost never returns anything", with the fixes shipped alongside this document
and the work still deferred.

## Why scans were slow

Ranked by wall-clock impact, all verified in source.

1. **`~/Library` was crawled single-threaded, last.** `FileCrawler.crawl` ran
   three sequential tiers with at most `maxParallelFolders` (8) folders in
   flight each, and `crawlOrder` sorted every folder named `Library` into
   tier 2 — so the largest tree on any developer Mac was one synchronous job
   crawled after everything else. The 1M-record budget caps memory, not
   traversal. *Fixed: a `Library` work unit is now expanded like a root, and
   its direct children become parallel work units (still tier 2, still last,
   bounded expansion depth).*
2. **Per-record filesystem round-trips in the rule engine.**
   `CleanerRuleEngine.isAllowed` called `PathSafetyPolicy.decide`, which
   resolves symlink ancestors (`resolvingSymlinksInPath`) — one syscall per
   record, up to three times per record (the findings loop, the policy
   pre-filter, and the app-leftover pass). *Fixed: `allowsCleanupTarget(_:)`
   gates on the risk flags the crawler already recorded plus the never-delete
   containment check (plain string work), computed once per record.
   `SafetyAuditor` still re-decides with full symlink resolution before any
   deletion, so analyze-time speed does not weaken execution-time safety.*
3. **Package-manager probes on the critical path.** `PackageManagerScanner`
   runs external commands with fixed timeouts (brew's two sequential dry-runs
   alone can take ~16s) and does not depend on crawl results, but the
   orchestrator awaited it after crawl + analysis. *Fixed: the probes start
   before the crawl and overlap it.*
4. **Sequential duplicate quick-hashing.** Every same-size candidate was
   quick-hashed on the actor thread, one file at a time, with no cancellation
   inside the loop. *Fixed: quick hashing runs in the same bounded worker
   group as full hashing, and cancellation is checked between groups and
   before full hashing.*
5. **Finalize persistence.** Up to 1M file records are JSON-encoded into one
   SQLite transaction plus nine further sequential saves, all under a single
   "Finalizing scan" progress step. *Deferred: bounded, and only dominant on
   budget-sized scans.*
6. **First-scan duplicate hashing and Vision feature prints** (full SHA-256 of
   every size+quick-match survivor ≤ 2 GB; up to 20,000 image feature prints).
   The persistent hash cache only helps rescans of unchanged files. *Deferred:
   disk-bound by design; workers already bounded.*
7. **AI on the critical path when enabled** — 3 attempts × 30s timeout plus
   backoff ≈ up to ~100s. Failure degrades gracefully. *Deferred.*
8. **Per-item crawl overhead** — a Launch Services package probe per
   extension-bearing directory, a second full subtree walk for every package
   and rolled-up folder, and string policy work per item. *Deferred: the
   largest win here is eliminating the double walk, which needs an
   enumerator-key redesign.*

Stage durations are now logged (`ScanOrchestrator`, `os.Logger`, category
`ScanOrchestrator`) so a slow scan can be attributed to a stage after the
fact.

## Why results looked empty

1. **Cancelling discarded everything.** The orchestrator persisted a
   `.cancelled` session with no findings and threw; and because `~/Library`
   (the main source of cache/leftover findings) was crawled last, anyone who
   pressed Stop on a slow scan saw an empty review that read as "clean".
   *Fixed: a stopped scan finalizes what it crawled so far — and because a
   stop usually lands during the crawl, before any analysis, the fast rule
   pass (project detection + rules + organization) still runs over the
   partial file set off the cancelled task. Duplicate detection is skipped on
   partial results: it is the expensive stage and its in-flight work is not
   recoverable. Memory rules still apply to the partial plan, and the records
   stay in memory (the bulk SQLite write is skipped) so Stop returns
   promptly. The session stays `.cancelled`, `ScanOutcome.wasCancelled` is
   set, and the UI shows "Scan stopped early — showing what was found so
   far."*
2. **Silent permission degradation.** Without Full Disk Access,
   `Containers`/`Group Containers` were skipped without a trace
   (`FullDiskAccess.closedAppDataFolders`), section roots were dropped via
   `try?` in `PermissionManager.roots`, and crawl errors only went to
   `os.Logger`. The FDA banner fired on mode + permission only, never on the
   scan's actual results. *Fixed: scans now carry `ScanNotice`s (FDA-skipped
   app data, unreadable locations, Spotlight-off sections) rendered in the
   status strip; the Overview lists a "Could not read" count; review empty
   states say when locations were unreadable; the FDA banner is result-driven
   (broad mode + off + few findings or errors).*
3. **Fail-closed sections.** `uninstalledAppData` needs Spotlight
   (`mdutil`/`mdfind`) and returns empty — silently — when indexing is off.
   *Fixed: MoCleanScanner emits a notice telling the person why the section is
   empty and how to fix it.*
4. **Policy over-denial.** With iCloud "Desktop & Documents" sync on, every
   Desktop/Documents file carries `cloudSyncedLocalPath` and can never be a
   finding or duplicate candidate; `sourceOrConfig` denies all
   `.json/.md/.yaml/…` files. This is deliberate (the safety model and
   `SafetyAuditor` depend on it) and is documented here as intentional, not a
   defect. *Deferred: relaxing it needs a product decision.*
5. **High absolute thresholds** — caches need > 1 MB, large files ≥ 1 GB, app
   leftovers > 50 MB and unmatched by any installed app, old downloads need
   30 days + Downloads + a known extension. Legitimately small results are
   possible; the notices above exist so small results are not confused with
   blind ones.

## UX changes shipped with this RCA

- Live crawl progress: the subtitle shows "Crawling… N items · folder" while
  the crawl runs (the 5-step progress contract is unchanged).
- The scan-summary toast (duration, candidates, high-risk) is now actually
  rendered; it was computed and auto-cleared but never displayed.
- Scan notices in the status strip with per-notice dismissal.
- "Could not read" count and a "stopped early" note in Overview's Latest Scan.
- Partial results survive Stop, with an explicit state in Overview.

## Deferred work

- Eliminate the double walk of packages/rolled-up folders (enumerator prefetch
  keys instead of per-item Launch Services probes).
- Batch/stream the 1M-record persistence, and split the "Finalizing scan"
  step into visible sub-steps.
- AI retry/timeout tuning; per-stage watchdogs.
- Incremental rescans (FSEvents or a persistent path index) instead of full
  crawls.
- A product decision on cloud-synced and source-file policy denials.
