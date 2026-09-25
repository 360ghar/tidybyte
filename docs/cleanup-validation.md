# Cleanup feature validation

Implementation uses Apple frameworks and retains the iOS 17 deployment target. New Vision and Foundation Models requests have runtime availability checks. Analysis images are loaded without network access. Model sessions use only `SystemLanguageModel.default`; there is no remote model fallback.

## Automated checks

Validated with Xcode 27 and the iOS 27 simulator runtime:

- 270 unit tests passed, including 16 new feature tests.
- All 3 new feature UI tests passed on iPhone 17e and iPad Pro 13-inch (M5) at Accessibility XXXL. The tests grant Photos access through the system prompt and do not delete media.
- The existing 4 iPhone Dynamic Type tests passed.
- The existing 6 iPad UI checks passed. The final targeted run passed all new feature tests without skips on both devices.
- `git diff --check` passed.

The review added regression checks for incomplete resource sizes, permission changes during search, exclusion searches with unanalyzed photos, deletion notices when a completion screen is on another tab, and storage-history scans across midnight. Permission changes also invalidate cached counts and gate open cleanup screens; reminder scans reject results if access or the library changes during enumeration.

The review UI run exposed a delayed Photos permission prompt in test setup. The test now keeps invoking the interruption handler while waiting. The final rerun passed all three feature tests on both devices with no skips; the existing Dynamic Type and iPad layout checks also passed during the review.

Generate the project with `xcodegen generate`. Run the full suite with an installed simulator destination:

```sh
xcodebuild -project Tidybyte.xcodeproj -scheme Tidybyte \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  CODE_SIGNING_ALLOWED=NO test
```

## Physical-device checks before release

Use a test photo library with disposable copies. Simulator results do not validate PhotoKit mutations, camera subtype metadata, Vision accuracy, or installed on-device models.

| Area | Device checks still required |
| --- | --- |
| Weekly reminders | Enable reminders; confirm one `weekly-cleanup-reminder` request at the selected weekday and 10:00. Relaunch on the same day, change the library and Photos permission, and disable reminders during a refresh. Check dated counts, limited-access wording, missing sizes, zero candidates, and scheduling errors. Storage history must gain at most one row per day. |
| Deletion notice | Commit and discard swipe deletions; cancel the Photos prompt; test a partial failure, externally removed items, and unavailable sizes. Delete originals after compression and Live Photo conversion. Confirm that only successful deletions enter the notice, original bytes are used, and compression savings are unchanged. Navigate immediately, dismiss the notice, and test Photos opening plus the manual fallback. |
| Tools and formats | Add recordings with the public subtype and mixed-case `RPReplay_Final*.MP4` filenames. Put the same photo in two chat albums; rename and remove albums; change Photos access. Verify no initial selections, largest-first recordings, unknown sizes, visible-selection deletion, playback, Activity, and deep links. Check overlapping Cinematic/Spatial media and the unavailable-format explanation. |
| Vision and local AI | Use iOS 18 for Worst Shots and supported iOS 26+ hardware for smudge detection. Confirm favorites, screenshots, and utility images are excluded from Worst Shots. Cancel scans and change the library mid-scan. On an Apple Intelligence device with its model installed, disable networking and check card reasons and search. Test unavailable models, unsupported languages and conditions, unknown label terms, rapid swipes, obsolete queries, and uncategorized photos. |
| Compatibility and accessibility | Run on iOS 17, an iOS 18 device, and supported iOS 26+ hardware. Check VoiceOver order and actions, Accessibility XXXL scrolling, and iPad rotation. Review the deletion notice and populated grids, not only empty states. |

Chat Media groups Photos albums; it does not verify app provenance or clear chat-app storage. Camera formats describe library size, not savings. The deletion notice describes one confirmed cleanup, not the remaining Recently Deleted balance or immediately available device space.
