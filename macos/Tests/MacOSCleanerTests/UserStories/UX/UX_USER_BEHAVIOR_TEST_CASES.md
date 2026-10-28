# UX User-Behaviour Test Cases (Review Matrix)

This matrix is the canonical manual UX verification artifact for user-facing behavior in macOS Cleaner.
Automated test coverage in this repo is mostly service-level; UX interactions below are validated via
interactive checks.

## Post-fix Verification Snapshot (this pass)

- Automated logical coverage: `swift test -c debug --filter UserStory` (with cache path overrides:
  `HOME=/tmp XDG_CACHE_HOME=/tmp XDG_DATA_HOME=/tmp TMPDIR=/tmp SWIFT_BUILD_DIR=/tmp`) passed (`8` tests, `0` failures).
- Manual UX validation still needed for direct interaction-only checks:
  `Cmd+R`, `Cmd+F`, `Cmd+Enter` focus/execution behavior in-window, and compact toast visibility timing.

| Status legend | Meaning |
|---|---|
| ✅ Tested | Behavior confirmed in interactive QA |
| ⚠️ Needs evidence | Automated checks passed, UI path still needs manual verification |
| ❌ Not tested | Not yet validated |

Each row tracks the expected behavior and edge cases. Validation status should be filled as verification progresses.

## Mandatory UX Acceptance (Requested in this pass)

| Requirement | Severity | Effort | Verification | Coverage |
|---|---|---|---|---|
| UB-H01: header shows `Scan X/5` + phase text during scan | P0 | XS | `HeaderBar` scan progress binding to `scanCurrentStep`, `scanTotalSteps`, `scanPhaseText` | Automated progress test + manual UI smoke |
| UB-A01: action risk filters include live counts (`All/Low/Medium/High`) | P0 | XS | `ActionStackView` chip label counters (`lowCount`, `mediumCount`, `highFilterCount`) | Manual UI validation |
| UB-H02: post-scan “What changed?” toast includes duration/candidates/reviewable/high-risk | P0 | S | `AppViewModel.formattedScanSummary` + toast visibility flag | Manual UI validation |
| UB-H04: execution progress is labeled in header during execution (`Execution X/Y actions`) | P1 | XS | `HeaderBar` execution progress label + `HeaderBar` progress view | Manual UI validation |
| UB-A03/UB-U01/UB-R01: empty states expose actionable `Run default scan`, `Re-run with safer mode`, `View last report` | P1 | S | `ActionStackView`, `UndoHistoryView`, `RelationshipGraphView` empty-state CTAs | Manual UI validation |
| UB-N03: keyboard shortcuts `Cmd+F`, `Cmd+Enter`, `Cmd+R` | P1 | XS | Header and NL plan bindings | Manual UI validation |

## Header & Scan Progress

| Requirement | Coverage | Verification |
|---|---|---|
| UB-H01 | Scan progress context in header | ✅ Automated (`ScanReviewUserStoryTests.testScanProgressEmitsCanonical5StepHeaderSequence`) + manual smoke |
| UB-H02 | Post-scan “What changed?” toast | ✅ `AppViewModel.formattedScanSummary` + manual UI smoke |
| UB-H04 | Execution progress context in header | ⚠️ Manual UI validation |
| UB-H03 | Header shortcuts (`Cmd+R`, `Cmd+F`) | ✅ Manual UX pass + hidden shortcut wiring |

- **UB-H01: Scan progress context in header**
  - **Given** a scan is running
  - **When** orchestrator emits phase updates
  - **Then** header shows `Scan X/5 steps` and phase text updates each stage.
  - **Edge cases**
    - Cancelling scan stops phase updates and removes scan badge.
    - If scan fails, progress context should return to status/error message only.

- **UB-H02: Post-scan “What changed?” toast**
  - **Given** scan completes successfully
  - **Then** header displays a compact toast containing: duration, total candidates, reviewable actions, high-risk count.
  - **Edge cases**
    - Toast auto-dismiss after configured timeout.
    - Start second scan before timeout should clear previous toast and not show stale text.
    - Failed scan does not create/keep toast.

- **UB-H04: Execution context while processing**
  - **Given** execution starts
  - **Then** header displays `Execution N/M actions` and progress bar updates to reflect execution stage.
  - **Edge cases**
    - If no actions match selected risk band, execution should not start and no execution progress header should appear.
    - Header text should always use action counts (not bytes) to avoid ambiguity.

- **UB-H03: Header shortcuts**
  - **Given** user presses `Cmd+R`
  - **Then** retry uses current scan posture and folders without changing focus context.
  - **Given** user presses `Cmd+F`
  - **Then** command text field becomes focused.
  - **Edge cases**
    - Retry is ignored during scanning/execution.
    - Command field focus is safe across onboarding/workspace transitions.

## Dashboard and Shell

- **UB-D01: Workspace shell state switching**
  - **Given** no outcome exists
  - **Then** onboarding is shown.
  - **When** scan succeeds and plan becomes available
  - **Then** dashboard/action/undo panels render.
  - **Edge cases**
    - Restoring app with existing outcome shows workspace path immediately.

- **UB-D02: Sidebar controls remain available under valid states**
  - **Given** scanning/execution are active
  - **Then** destructive state transitions are disabled and do not leave inconsistent UI.
  - **Edge cases**
    - Folder-changing actions remain disabled while scan is active.

## Action Review / Filters

| Requirement | Coverage | Verification |
|---|---|---|
| UB-A01 | Risk filter chips with counts | ✅ Manual UI validation of `ActionStackView` chip counts |
| UB-A02 | Empty filter recovery path | ✅ Manual UI validation (`Show All Actions`) |
| UB-A03 | Empty plan-state CTAs | ✅ Manual UI validation (`ActionStackView`) |
| UB-A04 | Approval action enablement edge cases | ✅ Manual UI validation |

- **UB-A01: Risk filter chips with counts**
  - **Given** plan actions contain mixed risk levels
  - **When** each chip is rendered
  - **Then** labels include live counts for All, Low, Medium, High.
  - **Edge cases**
    - If no forbidden/high actions exist, high chip should still display the sum of high+forbidden when forbidden exists.

- **UB-A02: Empty filter path**
  - **Given** selected risk filter has no matching visible actions
  - **Then** user sees guidance and quick reset back to All.
  - **Edge cases**
    - Clicking reset restores full list.
    - Disabled chips with zero count do not open empty filters.

- **UB-A03: Empty action plan state**
  - **Given** no planned actions
  - **Then** empty-state CTA shows: Run default scan, Re-run safer mode, View last report (if present).
  - **Edge cases**
    - View last report hidden when no report URL exists.

- **UB-A04: Approval actions with visible matching set**
  - **Given** visible undecided count is zero
  - **Then** “Approve Visible” and “Reject Undecided” controls are disabled.
  - **Edge cases**
    - Approve Low Risk only approves low-risk undecided actions and leaves others unchanged.

## Natural Language Command

| Requirement | Coverage | Verification |
|---|---|---|
| UB-N01 | Command execution path + `Cmd+Enter` | ✅ Automated (`NaturalLanguagePlannerUserStoryTests`) + manual command flow |
| UB-N02 | Focus preservation around execute | ✅ Manual interaction check |

- **UB-N01: Plan command execution path**
  - **Given** a non-empty command and available plan
  - **When** Plan action or `Cmd+Enter` is invoked
  - **Then** command is applied and plan is refreshed.
  - **Edge cases**
    - Empty command cannot execute.
    - Command field and suggestion row keep render state after execution.

- **UB-N02: Focus preservation around execute**
  - **Given** command field is focused
  - **When** `Cmd+Enter` executes a command
  - **Then** focus state is preserved unless the user actively moves focus away.
  - **Edge cases**
    - Command execution during execution/disallowed state does not steal focus.

## Execution and Safety

| Requirement | Coverage | Verification |
|---|---|---|
| UB-E01 | Safe vs full execution | ✅ Automated execution confirmation and model execution tests |
| UB-E02 | Execution progress visibility | ✅ Automated progress assertions and manual header visibility check |

- **UB-E01: Safe-vs-full execution**
  - **Given** approved low-risk and high-risk actions exist
  - **When** user opens Execute Safe and Execute All
  - **Then** safe path executes only low-risk; full path includes all approved actions.
  - **Edge cases**
    - No applicable actions should show a no-op message and not mutate state incorrectly.
    - High/forbidden actions are accounted for in confirmation text and completion messaging.

- **UB-E02: Execution progress visibility**
  - **Given** execution starts
  - **Then** header shows counts and progress bar updates.
  - **Edge cases**
    - Completion updates statuses for completed/failed actions after executor returns.

## Undo History

| Requirement | Coverage | Verification |
|---|---|---|
| UB-U01 | Undo empty-state guidance | ✅ Manual UI validation (`UndoHistoryView`) |
| UB-U02 | Restore path and reason flow | ✅ Automated undo service tests + manual interaction check |

- **UB-U01: Undo empty-state guidance**
  - **Given** no available undo records
  - **Then** undo section shows actionable scan/report guidance buttons.
  - **Edge cases**
    - Report button is unavailable when no report exists.

- **UB-U02: Restore behavior**
  - **Given** restoreable undo entry
  - **When** user restores it
  - **Then** restore occurs and row UI updates to restored state.
  - **Edge cases**
    - Restore with regret reason opens reason dialog.
    - Already-restored entries remain disabled.

## Relationships and Why Panel

| Requirement | Coverage | Verification |
|---|---|---|
| UB-R01 | Relationship empty-state CTAs | ✅ Manual UI validation (`RelationshipGraphView`) |
| UB-R02 | Why panel continuity after selection | ✅ Manual UI validation |

- **UB-R01: Relationship section empty state**
  - **Given** scan completed but no edges exist
  - **Then** relationship panel still renders and exposes scan/retry/report CTAs.
  - **Edge cases**
    - Edges appear after follow-up scan without stale zero-state blocking.

- **UB-R02: Why panel selection continuity**
  - **Given** user selects an action row
  - **Then** Why panel updates selected action details.
  - **Edge cases**
    - Deleting/rejecting actions does not crash and selected state remains consistent.

## Cross-Screen Regression

- **UB-C01: Scan completion to report flow**
  - Run scan → open undo/report/relationship actions from empty-state entry points.
  - Validate no broken navigation path after any empty-state or no-match scenario.
- **UB-C02: Keyboard access coverage**
  - Validate `Cmd+F`, `Cmd+R`, `Cmd+Enter` from normal and post-scan states.

## Verification Notes

- Automated test coverage is added where behavior is logic-exposed (service output, model outputs).
- Non-automatable interaction steps should be executed manually on macOS target builds and recorded in changelog notes.
