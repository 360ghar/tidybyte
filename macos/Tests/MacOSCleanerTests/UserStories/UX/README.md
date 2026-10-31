# UX Behavior QA

This folder is the UX behavior validation home for user-facing stories in this pass.

## Folder structure

- `UX_USER_BEHAVIOR_TEST_CASES.md` — canonical behavior matrix by screen and flow, including edge cases and required evidence.
- Additional `.swift` tests in `Tests/MacOSCleanerTests/UserStories/*.swift` cover service-level UX-visible logic (NL, planning, execution, undo, scan review).

Keep this folder as the source of truth when GUI automation is unavailable; manual interaction evidence should be logged in `UX_USER_BEHAVIOR_TEST_CASES.md`.
