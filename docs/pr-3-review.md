# PR #3 review validation

Reviewed commits: `95294e8` and `59584ac`. All 42 inline comments and both additional CodeRabbit notes were checked against their callers and the approved feature scope: 40 fixed, four not applied. Duplicate findings share fixes.

## Inline comments

| Review comment | Decision | Validation and change |
| --- | --- | --- |
| [4102441737](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102441737) | Fixed | Show only nonzero skip counts and use singular wording for one photo. |
| [4102441757](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102441757) | Fixed | Preserve the applied query while pruning; show an update message only when entries were removed. |
| [4102441771](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102441771) | Fixed | CI explicitly selects Xcode 26.3 instead of the runner default Xcode 16.4. |
| [4102441788](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102441788) | Fixed | Accept absent exclusions. Retaining them also preserves exclusion-only queries. |
| [4102441807](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102441807) | Fixed | Limit snapshot scans to two attempts, then use generic reminder text without publishing stale statistics. |
| [4102469482](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469482) | Fixed | Concurrent requests share one snapshot task; the debounce skips epochs already written by the launch/permission scan. |
| [4102469488](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469488) | Fixed | Original deletion attempts keep the previous notice until confirmed deletions replace it. |
| [4102469494](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469494) | Fixed | The cleanup card accessibility label includes Start here for the recommended tool. |
| [4102469502](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469502) | Fixed | Chat badges fetch album IDs only and intersect with the existing media summaries. |
| [4102469509](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469509) | Not applicable | Unknown-size assets cannot meet a positive large-file threshold. The count and bytes cover only confirmed qualifying files; removed the unused unknown-size field. |
| [4102469514](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469514) | Fixed | Stamp snapshot dates after enumeration and permission, epoch, and threshold validation. |
| [4102469518](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469518) | Fixed | RootView observes threshold preferences, covering both Settings and Large Files. Refreshes are debounced and update widgets and reminders. |
| [4102469523](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469523) | Not applied | The approved scope requires local analysis images and skipped-asset reporting. loadThumbnail permits network access and degraded images; keep the deliberate local-image-only path. |
| [4102469530](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469530) | Fixed | A current scheduling attempt removes the pending request when preferences or notification permission no longer permit scheduling. |
| [4102469536](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469536) | Fixed | Preserve completed search queries across unchanged and reduced indexes. |
| [4102469541](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469541) | Fixed | Declined deletion errors retain already-absent IDs. Callers reconcile those rows while recording zero deletions. |
| [4102469544](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469544) | Fixed | Direct label search handles punctuation and simple connector words. Unknown content words, negation, and unsupported operators still fail. |
| [4102469552](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469552) | Fixed | Absent exclusions are retained and match no labels, instead of rejecting the whole query. |
| [4102469560](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469560) | Fixed | Remove obsolete pendingPrune state. Scans with changed epochs remain rejected before publication. |
| [4102469564](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469564) | Fixed | Bound snapshot retries to two and share concurrent enumeration. |
| [4102469572](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469572) | Not applied as proposed | Keep a complete scan with progress and cancellation so Worst Shots remains globally ordered. A cap omits eligible photos; streaming changes deck ordering and undo semantics. Batch asset resolution removes the per-photo metadata fetch. |
| [4102469577](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469577) | Fixed | Apply the same staggered entrance to the Worst Shots card. |
| [4102469593](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469593) | Fixed | Add the Camera Formats skeleton at the matching position in Storage. |
| [4102469601](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469601) | Fixed | Remove the stale fixed tool count from documentation. |
| [4102469604](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469604) | Fixed | Use photo for one skipped image and photos otherwise. |
| [4102469613](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469613) | Fixed | Check cancellation between blur, exposure, and aesthetics work. |
| [4102469623](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469623) | Fixed | Split the skip messages, omit zero clauses, and pluralize each count. |
| [4102469632](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469632) | Fixed | Cache media filtering, sorting, visible selections, and size labels; rebuild only after relevant state changes. |
| [4102469634](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469634) | Fixed | Fallback failures explain that no supported label query was formed instead of claiming a label search ran. |
| [4102469643](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469643) | Fixed | Remove largeFileUnknownSizeCount and its always-true notification guard. |
| [4102469651](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469651) | Fixed | Use a controlled AsyncStream gate and await the search task instead of fixed sleeps and polling. |
| [4102469659](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469659) | Fixed | Remove pre-attempt notice dismissal from the shared deletion pipeline and all other affected callers. |
| [4102469670](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469670) | Fixed | Do not show No matching photos while a search is in progress. |
| [4102469679](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469679) | Fixed | Prune using an identifier-limited query and modification dates, with no resource metadata or whole-library pass. |
| [4102469684](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469684) | Fixed | An unavailable snapshot does not overwrite the previous widget figures or scan timestamp with zeros. |
| [4102469692](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469692) | Fixed | Swipe commits preserve the previous notice after decline, cancellation, or failure. |
| [4102469696](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102469696) | Fixed | Skip unsupported smudge requests and recheck support only after a nil result. |

## Additional review notes

| Note | Decision | Validation and change |
| --- | --- | --- |
| [Worst Shots asset lookup](https://github.com/360ghar/tidybyte/pull/3#pullrequestreview-5315130966) | Fixed | Resolve candidate PHAssets in one batch, then use the asset overload for local analysis images. |
| [Chat badge summary lookup](https://github.com/360ghar/tidybyte/pull/3#pullrequestreview-5315130966) | Fixed | The identifier-only album query replaces repeated AssetSummary and resource reads. |

## Follow-up comments on `59584ac`

| Review comment | Decision | Validation and change |
| --- | --- | --- |
| [4102698363](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102698363) | Fixed | Track callers of the shared snapshot task. Cancelling its last caller cancels and releases the task; other active callers retain their shared scan. Reject cancelled results and skip the statistics pass after a cancelled fetch. Synchronous PhotoKit work already in progress finishes before the next cancellation check. |
| [4102698369](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102698369) | Fixed | Album identifier queries include all burst assets, matching the tool's album fetch. |
| [4102698378](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102698378) | Not applied | Requiring non-nil dates removes unchanged photos with missing dates every time results are pruned. Apple documents that Photos updates modificationDate after content or metadata changes. No case was established where an edited asset retains a nil date. Keep the identifier and optional-date comparison; verify edited assets on a physical device. |
| [4102698398](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102698398) | Fixed | Apply the matching staggered entrance to the Camera Formats skeleton. |
| [4102698406](https://github.com/360ghar/tidybyte/pull/3#discussion_r4102698406) | Fixed | Re-read the current library epoch and threshold after the debounce, so a scan completed during the delay is not repeated. |

The modification-date decision follows Apple's [PHAsset.modificationDate contract](https://developer.apple.com/documentation/photos/phasset/modificationdate). The proposed nil-date exclusion does not distinguish an edit from an unchanged asset with an unavailable date.

## General comments

The notification security note is partly actionable. Scheduling now checks Photos authorization immediately before constructing the body and after adding the request. A changed or revoked scope cannot publish fresh counts from the previous scope. A local repeating notification cannot execute an authorization check at delivery while the app is inactive. Previously scheduled dated counts can remain until the app next runs; the request refreshes on activation and observed permission changes. This is a platform limitation of the requested count-bearing weekly reminder.

The docstring-coverage warning is a reviewer default, not a repository CI requirement. New service operations and concurrency boundaries are documented; redundant comments were not added to simple UI helpers to meet a percentage. Qodo subscription status and the Netlify preview comment contain no code findings.

## Validation

- All 277 unit tests passed locally with Xcode 27, including seven new regression tests from these review fixes. Existing asynchronous search tests now use explicit synchronization.
- The original CI failure was verified in its build log: Xcode 16.4 could not import FoundationModels. The workflow now selects Xcode 26.3, which is listed in the [macOS 15 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
- All three feature UI tests passed on both iPhone and iPad; both iPad layout tests passed. The iPhone run skipped the two iPad-only layout tests as expected.
- [GitHub CI for `59584ac`](https://github.com/360ghar/tidybyte/actions/runs/36112731748) passed with Xcode 26.3. The follow-up changes also passed all 277 local unit tests.
- Physical-device checks remain in [cleanup-validation.md](cleanup-validation.md).
