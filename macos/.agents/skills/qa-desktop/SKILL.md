---
name: qa-desktop
description: >
  QA tests for the macOS Cleaner desktop app. Tests the native SwiftUI macOS
  application including onboarding, scanning, action review, execution, undo,
  natural language commands, settings, report generation, the menu bar,
  dashboard and visualizations, keyboard shortcuts, notifications, and
  error-path flows.
  Uses agent-browser for desktop GUI testing.
---

# QA Tests: macOS Cleaner Desktop App

## Testing Target

This is a local-only macOS desktop app. There are no preview deployments or remote environments.

**How to get a running app for testing:**

1. Build from the current branch: `swift build` (from project root)
2. The binary is at `.build/debug/MacOS-Cleaner`
3. Launch the app: `open .build/debug/MacOS-Cleaner.app` or run the binary directly
4. Use agent-browser to interact with the launched app window

**CRITICAL:** Always test against the current branch's built binary. Never test against a previously installed version or a different branch.

If the build fails, report ALL tests as BLOCKED: "Build failed -- cannot test branch code."

## App Configuration Notes

- **Window size:** Minimum 1100x720. The app enforces this.
- **Three-panel layout:** Sidebar (280px) | Main workspace (scrollable) | Why Panel (360px)
- **Onboarding view** shows when no scan has been completed (`showOnboarding == true`)
- **Main workspace** shows after a scan completes
- **No user authentication** -- the app opens directly to the main interface
- **Local-only mode** works without any API key
- **AI features** require an optional BYOK OpenAI-compatible key stored in Keychain
- **Notifications** require macOS permission grant (may show system dialog)

## Available Test Flows

### Flow 1: Onboarding

**When to run:** Diff changes `Sources/MacOSCleanerAppKit/UI/ContentView.swift` (OnboardingView), or `Sources/MacOSCleanerAppKit/App/AppViewModel.swift` (showOnboarding, chooseFolders), or first-launch experience.

**Steps:**
1. Launch the app (fresh state, no prior scans)
2. Verify the onboarding view appears with three step cards
3. Verify step 1: "Pick a safe scan mode" with description text
4. Verify step 2: "Choose privacy" with description text
5. Verify step 3: "Review before action" with description text
6. Verify "Select Folders" button is present and enabled
7. Verify "Start Scan" button is disabled (no folders selected yet in selectedFolders mode)
8. Verify the optional API key section is present
9. Verify the API key text field has placeholder text
10. Verify the "Save" button is disabled when API key input is empty

**Success criteria:** Onboarding view renders correctly with all three steps, folder button enabled, scan button disabled, API key section visible.

### Flow 2: Scan

**When to run:** Diff changes ScanOrchestrator, FileCrawler, DuplicateDetector, CleanerRuleEngine, ProjectDetector, ContentExtractor, PackageManagerScanner, or scan-related ViewModel methods.

**Steps:**
1. From onboarding, click "Select Folders" to open the folder picker
2. Select a test directory with known files (e.g., a directory with a few files including some caches/duplicates)
3. Verify the folder path appears in the sidebar "Scan Roots" section
4. Verify the scan mode picker shows "Selected Folders" selected
5. Click "Scan" button in the header bar
6. Verify the status message changes to indicate scanning
7. Wait for the scan to complete
8. Verify the main workspace view appears (dashboard, action stack)
9. Verify the dashboard shows at least some metrics (Files Seen > 0, Scanned bytes > 0)

**Success criteria:** Scan completes, dashboard appears with non-zero metrics, proposed actions are listed.

### Flow 3: Review Actions + Why Panel

**When to run:** Diff changes ActionRow, WhyPanelView, PlannedAction model, or display logic.

**Steps:**
1. After a scan completes, verify "Proposed Actions" section header is visible
2. Verify action rows are listed (each with icon, reason, metadata, approve/reject buttons)
3. Click on an action row to select it
4. Verify the Why Panel (right side, 360px) updates to show the selected action's details
5. Verify the Why Panel shows: action type label, risk level label, reason text
6. Verify "Targets" section lists file details (file name, display path)
7. Verify "Always" and "Never Here" buttons appear at the bottom

**Success criteria:** Action rows render correctly, selecting an action populates the Why Panel with details and targets.

### Flow 4: Approve/Reject/Always/Never

**When to run:** Diff changes AppViewModel approve/reject/alwaysDoThis/neverDoThisHere, MemoryEngine, or action status logic.

**Steps:**
1. After a scan, click the approve (checkmark) button on an action
2. Verify the action status changes to "approved"
3. Click the reject (xmark) button on another action
4. Verify the action status changes to "rejected"
5. Select an action and click "Always" in the Why Panel
6. Verify the action status changes to "approved"
7. Select another action and click "Never Here" in the Why Panel
8. Verify the action status changes to "rejected"

**Success criteria:** Approve/reject buttons correctly update action status. Always/Never Here buttons update status and trigger memory learning.

### Flow 5: Execute Actions

**When to run:** Diff changes ActionExecutor, SafetyAuditor, or execution logic.

**Steps:**
1. After approving at least one action, verify the "Execute" button in the header becomes enabled
2. Click "Execute" button
3. Verify the status message changes to "Executing approved actions..."
4. Wait for execution to complete
5. Verify the execution summary appears (operations count, failures count)
6. Verify executed actions show "completed" status
7. If any failures occurred, verify the failure count is shown and is red

**Success criteria:** Execute button works, approved actions are processed, summary shows correct counts, failures (if any) are reported in red.

### Flow 6: Undo

**When to run:** Diff changes UndoManagerService, UndoManager, or undo-related UI.

**Steps:**
1. After executing actions, scroll to the "Undo History" section
2. Verify undo records appear (each with status icon, action type, path, restore button)
3. Verify available undo records show the "arrow.uturn.backward.circle" icon in terracotta
4. Click the restore (arrow.uturn.backward) button on an available undo record
5. Verify the status message changes to "Undo completed."
6. Verify the undo record status changes from "available" to "restored"
7. Verify the restore button becomes disabled for the restored record

**Success criteria:** Undo history shows executed actions, restore button works, status updates correctly.

### Flow 7: Natural Language Command

**When to run:** Diff changes PlannerAgent, NaturalLanguagePlanView, or NL command processing.

**Steps:**
1. After a scan completes, locate the natural language input field
2. Verify the placeholder text is present: "Ask for a targeted plan, for example: Clean Python caches in old projects"
3. Verify the "Plan" button is disabled when input is empty
4. Type a command like "Clean cache files"
5. Verify the "Plan" button becomes enabled
6. Click "Plan" button
7. Verify the status message updates to "Command converted into a reviewable plan."
8. Verify the action list updates with new/modified actions

**Success criteria:** NL input accepts text, Plan button enables/disables correctly, command is processed and plan updates.

### Flow 8: Settings

**When to run:** Diff changes SettingsView, ProviderSettings, or privacy mode logic.

**Steps:**
1. Open Settings (via macOS Settings menu or Cmd+,)
2. Verify the Settings window opens with 560px width
3. Verify "Provider" section with: provider name, API base URL, text model, max tokens stepper, temperature slider
4. Verify "Privacy" section with: privacy mode picker (5 options), AI enable toggle
5. Change a setting value (e.g., adjust temperature slider)
6. Change privacy mode selection
7. Close and reopen Settings -- verify values persist

**Success criteria:** Settings window renders correctly with all fields, values are interactive and persist.

### Flow 9: Report Generation

**When to run:** Diff changes ReportGenerator or report-related UI.

**Steps:**
1. After a scan completes, click the "Report" button in the dashboard footer
2. Verify the status message updates to "Local PDF report generated."
3. Verify the generated report URL appears in the sidebar
4. Verify the PDF file exists at the reported path
5. Verify the file has non-zero size

**Success criteria:** Report generates successfully, PDF file exists and has content.

### Flow 10: Menu Bar

**When to run:** Diff changes `Sources/MacOSCleanerAppKit/App/MacOSCleanerApp.swift` (MenuBarExtra, MenuBarView, AppDelegate), or the AppViewModel methods the menu bar calls (runScan, loadUndoHistory, restore).

**Goal:** Verify the sparkle menu bar extra offers all six commands and that keyboard shortcuts (Cmd+O, Cmd+,, Cmd+Q) trigger them, including reopening the main window after it is closed.

**Preconditions:**
- The app is running with the menu bar extra visible (sparkle icon). The extra lives in the system menu bar, outside the app window; agent-browser may need keyboard shortcuts or AX-level driving (see Known Failure Modes).
- At least one executed action with an available undo record for Undo Last Action.

**Steps (Given/When/Then):**
1. Given the app is running, when the user opens the sparkle menu bar icon, then the menu shows: Open macOS Cleaner, Quick Scan Downloads, Storage Overview, Undo Last Action, Settings…, Quit.
2. Given the main window is closed (the app keeps running because the delegate returns false for applicationShouldTerminateAfterLastWindowClosed), when the user clicks "Open macOS Cleaner" or presses Cmd+O, then the main window reappears and comes to front.
3. Given a completed scan, when the user clicks "Quick Scan Downloads", then the mode switches to Selected Folders with Downloads as the only root and a scan starts immediately.
4. When the user clicks "Storage Overview", then the main window is brought to front showing the dashboard storage information (no separate storage screen exists).
5. Given at least one available undo record, when the user clicks "Undo Last Action", then the most recent record is restored directly (no regret dialog) and its row shows restored state.
6. Given no undo records exist, when the user clicks "Undo Last Action", then nothing happens (silent no-op, no error).
7. When the user clicks "Settings…" or presses Cmd+,, then the Settings window opens.
8. When the user clicks "Quit" or presses Cmd+Q, then the app terminates.

**Expected result:** All six menu items work; Cmd+O reopens the closed window; Cmd+, opens Settings; Cmd+Q quits; Quick Scan Downloads starts a Downloads scan; Undo Last Action restores the latest record.

**Evidence to capture:** Snapshot of the menu bar menu items, snapshot of the main window after reopen, status message after quick scan, undo row state after menu-bar undo, app termination.

**Pass criteria:** Every menu item behaves as described; all three keyboard shortcuts work; window reopen works from the closed state.

### Flow 11: Dashboard & Visualizations

**When to run:** Diff changes `DashboardView`, `TreemapView`, `RelationshipGraphView`, `ContentView` (StatusBarView), `SpaceForecaster`, or AppViewModel dashboard computed properties (dashboardSections, spaceForecast).

**Goal:** Verify metric cards, treemap overlays and block selection, the relationship graph (hover, legend, empty state), the storage forecast, and the status bar.

**Preconditions:** A completed scan with findings in multiple categories so dashboard sections and edges exist (a scan with few files may produce no edges, which exercises the empty state instead).

**Steps (Given/When/Then):**
1. Given a completed scan, when the dashboard renders, then five metric cards show Files Seen, Scanned, Reviewable, Projects, and Summaries with non-zero values where applicable.
2. Given dashboard sections exist, when the user switches the treemap overlay picker from None to Risk Level, then block colors change to risk colors (red/orange/green); switching to Category restores the categorical palette (None and Category use the category palette, so they look similar by design).
3. When the user clicks a treemap block, then a selection panel appears below the canvas showing the category label, byte count, and color, with a "Clear Selection" button; clicking the same block again deselects.
4. Given a scan with relationship edges, when the user hovers a node, then the node scales up and incident edges highlight; the legend below lists only the edge types present (Duplicate, Generated From, Same Project, Export Of, Backup Of, Version Of, Manifest Of, Temporary Artifact, Near Duplicate, Cloud Copy).
5. Given a scan with no edges, when the dashboard renders, then the relationship section shows the empty state with "Run default scan", "Re-run with safer mode", and "View last report" (the last only when a report exists).
6. Given storage snapshots exist, when the scan completes, then the Storage Forecast section shows the growth rate per day and the estimated days until the next threshold.
7. When the app renders, then the status bar at the bottom shows free disk space and, when the plan has reclaimable bytes, "N reclaimable".

**Expected result:** Metrics match the scan outcome; overlay modes visibly change colors; block selection works; graph hover and legend behave; empty state appears without edges; forecast appears when snapshots exist; status bar shows free and reclaimable space.

**Evidence to capture:** Snapshot of the metric cards, one snapshot per overlay mode, the treemap selection panel, the graph with legend and a hovered node, the forecast text, the status bar text.

**Pass criteria:** All five metrics render; each overlay mode changes block colors; selection and clear selection work; hover enlarges nodes and highlights edges; the legend shows only present types; the empty state shows all CTAs; status bar shows both free space and reclaimable bytes.

### Flow 12: Keyboard Shortcuts (In-Window)

**When to run:** Diff changes `HeaderBar` (hidden Retry Scan and Focus command field buttons with keyboardShortcut), `NaturalLanguagePlanView` (Cmd+Return on Plan), or focus-state wiring in `ContentView`.

**Goal:** Verify Cmd+R retries the scan, Cmd+F focuses the NL command field, and Cmd+Return applies the NL plan, including their disabled states.

**Preconditions:** A completed scan (for Cmd+R and Cmd+Return) or the onboarding/workspace view (for Cmd+F).

**Steps (Given/When/Then):**
1. Given a completed scan, when the user presses Cmd+R, then a new scan runs with the current mode, folders, and posture, and the header shows "Scan 1/5 steps".
2. Given a scan is running or execution is in progress, when the user presses Cmd+R, then the retry is ignored (no second scan starts).
3. Given the workspace or onboarding view, when the user presses Cmd+F, then the natural language command field becomes focused.
4. Given a non-empty NL command, when the user presses Cmd+Return, then the plan is applied exactly as if the Plan button were clicked.
5. Given an empty or whitespace command, when the user presses Cmd+Return, then nothing happens (the Plan button is disabled).
6. Given the command field is focused, when Cmd+Return applies a command, then focus stays in the field.

**Expected result:** All three shortcuts work in their active states and are safe no-ops in their disabled states.

**Evidence to capture:** Snapshot of the header progress after Cmd+R, focused field state after Cmd+F, action list after Cmd+Return.

**Pass criteria:** Cmd+R retries the scan; Cmd+F focuses the field; Cmd+Return applies the plan; retry is ignored while scanning or executing; an empty command cannot execute; focus is preserved.

### Flow 13: Execute Safe vs Execute All

**When to run:** Diff changes `HeaderBar` execute buttons and confirmation dialogs, `AppViewModel.executeApprovedActions`/`executeSafeActions`, `ActionExecutor`, or `SafetyAuditor`.

**Goal:** Verify both execution variants, their confirmation dialogs, header progress display, and the no-op message when no actions match the selected risk band.

**Preconditions:** A scan with at least one approved low-risk action and at least one approved higher-risk action.

**Steps (Given/When/Then):**
1. Given approved actions exist, when the header renders, then "Execute Safe (N)" appears only when N low-risk approved actions exist, and "Execute All" is disabled when no actions are approved.
2. When the user clicks "Execute Safe (N)", then the "Confirm Safe Execution" dialog appears with the "Execute N Low-Risk Action(s)" button and a message stating the low-risk action and affected-file counts.
3. When the user confirms, then only low-risk approved actions execute, the status shows "Executing low-risk actions...", and the header shows "Execution N/M actions" with a progress bar.
4. When the user clicks "Execute All", then the "Confirm Execution" dialog shows the total approved count including non-low-risk actions; confirming executes all approved actions.
5. Given no approved actions in the selected risk band, when execution is triggered, then no execution starts and the status reads "No approved actions in the selected risk band to execute."
6. Given execution finishes, when the dashboard renders, then the summary shows "N operations, M failures", colored red when failures exist, and failed actions show failed status.

**Expected result:** Safe executes only low-risk actions; All executes every approved action; both dialogs show accurate counts; progress renders in the header; the no-op path does not mutate state; failures are reported in red.

**Evidence to capture:** Snapshots of both confirmation dialogs, the header during execution (progress text and bar), the no-op status message, and the execution summary.

**Pass criteria:** Safe and All execute the correct action sets; dialog counts match; progress text shows during execution; the no-op message appears without state changes; failures render in red.

### Flow 14: Empty-State CTAs

**When to run:** Diff changes `ActionStackView` empty state, `UndoHistoryView` empty state, `RelationshipGraphView` empty state, or empty-plan behavior in AppViewModel.

**Goal:** Verify every empty state exposes actionable CTAs and that "View last report" appears only when a report exists.

**Preconditions:** A scan whose plan has no actions (for the action empty state), no undo records (for undo), and no relationship edges (for the graph).

**Steps (Given/When/Then):**
1. Given a completed scan with no proposed actions, when the Proposed Actions section renders, then it shows "No actions proposed yet." with "Run default scan", "Re-run with safer mode", and "View last report" (the last only when a report URL exists).
2. When the user clicks "Run default scan", then a scan runs with the current settings; "Re-run with safer mode" runs a scan with a more conservative posture.
3. Given no undo records, when the Undo History section renders, then it shows "Executed reversible actions will appear here." with the same three CTAs.
4. Given no relationship edges, when the relationship section renders, then it shows the empty state with the same CTAs; "View last report" is hidden when no report exists.
5. Given an empty state was shown, when a follow-up scan completes, then the sections populate and the zero-state does not linger.

**Expected result:** All three empty states render with working CTAs; the report CTA is conditional; follow-up scans repopulate the sections.

**Evidence to capture:** Snapshot of each empty state with its CTAs, snapshot after a follow-up scan showing populated sections.

**Pass criteria:** Every CTA works; "View last report" appears only with a report; no stale zero-state after a new scan.

### Flow 15: Scan Cancellation

**When to run:** Diff changes `AppViewModel.cancelScan` and the cancellation handling in `runScan`, `ScanOrchestrator` cooperative cancellation, or the HeaderBar Stop button.

**Goal:** Verify the Stop button cancels a mid-scan run, no stale progress repaints, and the status shows "Scan cancelled."

**Preconditions:** A scan target large enough that scanning takes several seconds (for example, a large folder or Home Folder mode).

**Steps (Given/When/Then):**
1. Given a scan is running, when the header renders, then the scan button becomes "Stop" with an xmark icon and the header shows "Scan N/5 steps" with the current phase text.
2. When the user clicks Stop, then the scan cancels and the status message becomes "Scan cancelled."
3. Then the progress text disappears, the Scan button returns, and no further phase updates repaint (stale progress from the cancelled run is not shown).
4. Given a cancelled scan, when the user clicks Scan again, then a fresh scan starts with progress reset to step 1.

**Expected result:** Cancellation is prompt, the status reads "Scan cancelled.", the progress UI clears, and a follow-up scan starts cleanly.

**Evidence to capture:** Snapshot of the Stop button and progress text mid-scan, the status message after cancel, and the header after a follow-up scan.

**Pass criteria:** Stop cancels the run; status reads "Scan cancelled."; no stale progress text; the next scan starts at step 1.

### Flow 16: Risk Filter Chips

**When to run:** Diff changes `ActionStackView` filter chips (counts, disabled states), `FilterChip`, or the filteredActions logic.

**Goal:** Verify live chip counts, per-band filtering, disabled zero-count chips, and the empty-filter recovery path.

**Preconditions:** A plan with a mix of low, medium, and high risk actions (forbidden actions, if present, count toward the High chip).

**Steps (Given/When/Then):**
1. Given a plan with mixed risk levels, when the filter row renders, then the chips show "All (N)", "Low (N)", "Medium (N)", and "High (N)" with live counts, where High includes forbidden actions.
2. When the user clicks "Low (N)", then only low-risk actions are listed; clicking "High (N)" lists high and forbidden actions.
3. Given a chip with zero matching actions (for example, no medium-risk actions), when the chip renders, then it is disabled and cannot open an empty filter.
4. Given a selected filter with no matching visible actions, when the list is empty, then "No actions match the selected filter." appears with a "Show All Actions" button.
5. When the user clicks "Show All Actions", then the full list restores and the All chip becomes selected.

**Expected result:** Counts are live and correct, filtering works per risk band, zero-count chips are disabled, and the empty-filter state offers a working reset.

**Evidence to capture:** Snapshot of the chips with counts, the filtered list per chip, a disabled chip, and the empty-filter recovery state.

**Pass criteria:** Counts match the plan; each chip filters correctly; disabled chips cannot select an empty filter; "Show All Actions" restores the list.

### Flow 17: NL Command Edge Cases

**When to run:** Diff changes `PlannerAgent.planForNaturalLanguageCommand` keyword filters, `NaturalLanguagePlanView`, or `AppViewModel.applyNaturalLanguageCommand`.

**Goal:** Verify the "duplicates", "organize", "logs", and "everything" commands, the empty-command no-op, the no-match hint, and Plan button disabled states.

**Preconditions:** A completed scan with duplicate findings, log findings, and organization-type actions where possible.

**Steps (Given/When/Then):**
1. Given a completed scan, when the user enters "duplicates" and clicks Plan or presses Cmd+Return, then the action list filters to duplicate-related actions and the status shows "Command 'duplicates' converted into N action(s)."
2. When the user enters "organize" (or "sort"), then the list filters to organization actions (tag, archive, alias, symlink, move).
3. When the user enters "logs", then the list filters to log-file actions.
4. When the user enters "everything", then the original unfiltered actions are restored.
5. Given a filtered plan, when the user clears the field and tries to run the command, then nothing changes and the Plan button is disabled for empty or whitespace input.
6. Given a command matching nothing, when the user clicks Plan, then the status reads "No actions match '<command>'. Try a different command or say 'everything' to restore." and the action list may show the empty state with its CTAs.
7. Given the command field is focused, when Cmd+Return applies a command, then focus stays in the field.

**Expected result:** Keyword commands filter and restore correctly; empty commands are no-ops with the Plan button disabled; no-match commands surface the "everything" hint; focus is preserved.

**Evidence to capture:** Action list snapshot per command, the status messages, the disabled Plan button, the no-match hint.

**Pass criteria:** Each keyword produces the described filter; "everything" restores the full list; empty input cannot execute; the no-match hint appears; focus is preserved after execution.

### Flow 18: Settings Data Controls

**When to run:** Diff changes `SettingsView` (launch at login, stepper, slider, privacy picker, AI toggle, calibration, clear data, export), `AppViewModel.saveSettings`/`loadSettings`/`clearAllData`/`exportDatabase`/`applyCalibrationPreset`, or `MemoryEngine.applyCalibrationPreference`.

**Goal:** Verify every Settings control persists, launch-at-login reverts on failure, calibration gives feedback, Clear All Data confirms, and Export Database writes the file.

**Preconditions:** Settings reachable via the macOS Settings menu or Cmd+,. Launch-at-login success requires a bundled app (see Known Failure Modes).

**Steps (Given/When/Then):**
1. When the user toggles "Launch at login" on, then SMAppService.mainApp.register() is attempted; on success the toggle stays on, and on failure the toggle reverts and the header error shows "Failed to update launch at login: ...".
2. When the user adjusts the "Max tokens" stepper (range 200-8000, step 100), then the value label updates and persists after closing and reopening Settings.
3. When the user drags the Temperature slider (0-1), then the numeric readout updates and persists.
4. When the user changes the Privacy mode picker, then all 5 options (Local Only, Metadata Only AI, Snippets AI, Vision AI, Full Document AI) are selectable and the selection persists.
5. When the user toggles "Enable AI during scans", then the value persists across app restarts.
6. When the user taps one of the 5 Confidence Calibration preset rows, then the status message shows "Preference saved." and the rule is stored.
7. When the user clicks "Clear All Data", then the "Are you sure?" confirmation dialog warns that all scan results, undo history, and stored preferences will be permanently deleted; confirming resets the app to onboarding with status "All data cleared."
8. When the user clicks "Export Database", then an NSSavePanel opens; saving copies the SQLite database and the status reads "Database exported successfully."

**Expected result:** Every control persists; failure paths revert cleanly; Clear All Data resets to onboarding; Export Database produces a file.

**Evidence to capture:** Snapshot of the Settings form, the revert error, stepper/slider values after reopen, the calibration status message, the clear-data confirmation, and the exported file on disk.

**Pass criteria:** Values persist across Settings reopen; SMAppService failure reverts the toggle; calibration shows "Preference saved."; Clear All Data returns to onboarding; the exported file exists with non-zero size.

### Flow 19: Sidebar

**When to run:** Diff changes `SidebarView`, `PermissionManager` scan modes, `InboxManager`, or AppViewModel folder management methods.

**Goal:** Verify the 20-mode picker, scan root management, Inbox creation, the privacy and posture pickers, and the report path display.

**Preconditions:** A scan completed once so the workspace renders with the sidebar.

**Steps (Given/When/Then):**
1. When the user opens the Mode picker, then 20 scan modes are listed grouped into Crawl, System, Apps, Developer, and Backups & Large Files sections.
2. When the user selects a non-folder mode (for example, Developer Cleanup), then the mode persists and the next scan uses those roots.
3. Given folder mode, when the user adds folders via "Add Downloads", "Add Home", or the Folders button, then the roots appear in Scan Roots with Open in Finder and Remove buttons; "Clear All" removes them all and is disabled while scanning or executing.
4. When the user clicks "Inbox", then the Cleanroom Inbox directory is created and added to the scan roots with status "Cleanroom Inbox is ready."
5. When the user opens the Privacy picker, then three options show (Local Only, Metadata AI, Snippets), and the BYOK AI toggle is disabled while Local Only is selected; the sidebar selection should match the 5-mode picker in Settings after reopening Settings.
6. Given the posture picker, when space allows it renders the segmented Careful/Balanced/Deep labels, otherwise the menu renders Conservative/Balanced/Aggressive; both map to the same posture values.
7. Given a generated report, when the sidebar renders, then the report file path appears at the bottom above the status bar.

**Expected result:** All 20 modes are selectable and persist; root management works; Inbox creates and adds the folder; privacy and posture pickers persist; the report path is visible.

**Evidence to capture:** Snapshot of the Mode picker with grouped sections, the Scan Roots list with open/remove buttons, the Inbox status message, the privacy and posture pickers, and the report path.

**Pass criteria:** 20 modes present and selectable; roots add, remove, open, and clear; Inbox is created once and added once; privacy selections are consistent between sidebar and Settings; posture variants map to the same values; the report path shows after generation.

### Flow 20: Onboarding Provider Flow

**When to run:** Diff changes `OnboardingView` (provider section, base URL validation), `AppViewModel.saveAPIKey`, or `KeychainStore`.

**Goal:** Verify the API key save flow, base URL validation warning, text model persistence, Start Scan disabled states, and the "Scanning…" state.

**Preconditions:** Fresh launch showing onboarding, or onboarding reached via Clear All Data.

**Steps (Given/When/Then):**
1. Given an empty API key field, when the onboarding renders, then the "Save" button is disabled.
2. When the user types an API key and clicks Save, then the key is stored in Keychain, the field clears, and the status shows "API key saved. AI enabled with metadata-only privacy mode." (or "API key saved in Keychain." when AI was already enabled).
3. When the user types an invalid base URL (for example, "not a url"), then the orange exclamationmark.triangle icon with the "Invalid URL format" tooltip appears and the stored URL is not overwritten.
4. When the user types a valid base URL and a text model name, then both persist across app restarts.
5. Given folder mode with no folders, when the user clicks "Start Scan", then nothing happens because the button is disabled, and the helper text reads "Select at least one folder to enable scanning, or switch scan mode in the sidebar."
6. Given a scan is running from onboarding, when the view updates, then the button title becomes "Scanning…" and stays disabled.

**Expected result:** Save gating works, the key saves with status feedback, invalid URLs warn without overwriting, URL and model persist, and the scan button handles its disabled and scanning states.

**Evidence to capture:** Snapshot of the provider section, the status message after save, the invalid URL warning, and the disabled and Scanning… button states.

**Pass criteria:** Save disabled when empty; key saved and AI mode message shown; invalid URL shows the warning and does not persist; URL and model persist; Start Scan disabled without folders; "Scanning…" shows during a scan.

### Flow 21: Notifications

**When to run:** Diff changes `NotificationScheduler`, the notification permission request in `ContentView.task`, or the post-scan notification calls in AppViewModel.

**Goal:** Verify the permission prompt timing, the scan-completed notification, and weekly digest scheduling.

**Preconditions (important):** Notifications only function when the app runs as a proper .app bundle (`Bundle.main.bundleURL.pathExtension == "app"`). When launched via `swift run` or the bare binary, `NotificationScheduler` disables all notification behavior: no permission prompt, no notifications. Authorization must not already be denied for the bundle.

**Steps (Given/When/Then):**
1. Given a bundled app whose notifications are not yet authorized, when the app first launches, then the system permission prompt appears (requestAuthorization is called from ContentView.task).
2. Given authorization granted, when a scan completes, then a "Scan Complete" notification fires within about a second with the body "Review cleanup suggestions for N."
3. Given a completed scan, when scheduling runs, then a repeating "Weekly Storage Digest" notification is scheduled for Mondays at 9:00, observable only via Notification Center pending notifications (not in the app UI).
4. Given the app runs as a bare binary (not a bundle), when a scan completes, then no permission prompt appears and no notifications are scheduled; this is expected, not a failure.

**Expected result:** Permission prompt on first bundled launch, scan-complete notification delivered, weekly digest scheduled, and graceful no-op for unbundled runs.

**Evidence to capture:** The system permission prompt (if reachable by the driver), Notification Center entries, and the pending notification list; record whether the app ran bundled or unbundled.

**Pass criteria:** Prompt appears once on first bundled launch; the scan-complete notification is delivered; the weekly digest exists in pending notifications; unbundled runs show no notification behavior.

### Flow 22: Cross-Flow Regression

**When to run:** Any diff touching scan, plan, execute, undo, report, or NL paths; always after changes to AppViewModel or PlannerAgent.

**Goal:** Verify the full pipeline scan → approve → execute → undo → report → NL replan with consistent counts and no broken paths.

**Preconditions:** A test folder with known files including at least one cache or duplicate.

**Steps (Given/When/Then):**
1. Given a fresh app state, when the user runs a default scan on the test folder, then the dashboard populates and proposed actions appear.
2. When the user approves a low-risk action and executes it, then the action completes and an undo record appears in Undo History.
3. When the user restores the record, then the file returns and the row shows restored state.
4. When the user generates a report, then the PDF is created and its path shows in the sidebar.
5. When the user runs an NL replan command (for example, "everything"), then the action list stays consistent with the executed and restored state: no phantom actions, no duplicates, counts unchanged.
6. When the user runs a second scan, then prior undo records, the report path, and the dashboard counts remain consistent.

**Expected result:** Every stage of the pipeline completes and subsequent stages do not corrupt prior state.

**Evidence to capture:** Snapshots at each stage: dashboard metrics, action statuses, the undo row, the sidebar report path, and the NL result list.

**Pass criteria:** Scan, approve, execute, undo, report, and NL replan all complete; counts stay consistent; the second scan preserves history.

### Flow 23: Package Manager Cleanup Execution

**When to run:** Diff changes `PackageManagerScanner`, `ActionExecutor` package handling, `ProcessRunner`, or AppViewModel package execution.

**Goal:** Verify package-manager cleanup actions appear only in developer mode for installed tools and that approved actions run the real command.

**Preconditions (conditional):** Developer Cleanup mode selected, and at least one of brew, docker, npm, or pip installed on the machine. If none are installed, report this flow as BLOCKED, not failed. Package cleanup actions never appear outside developer mode.

**Steps (Given/When/Then):**
1. Given Developer Cleanup mode and at least one package manager installed, when a scan runs, then runPackageManagerCleanup actions may appear with dry-run evidence in their reasons (for example, "Homebrew cleanup dry-run has stale downloads or old versions to review.").
2. When the user selects such an action, then the Why Panel shows "Run package manager cleanup command" as the planned operation.
3. When the user approves and executes the action, then the real cleanup command runs via ProcessRunner and the result is recorded in the execution summary.
4. Given a package manager that is not installed, when a scan runs in developer mode, then no candidates for that manager appear (missing executables are skipped).

**Expected result:** Candidates appear only for installed tools, execution runs the real command, and missing tools are skipped silently.

**Evidence to capture:** Snapshot of the package cleanup actions with dry-run text, the Why Panel operation text, the execution summary, and the installed tools (`which brew docker npm pip`).

**Pass criteria:** Actions appear only for installed managers; approved actions execute and are summarized; no candidates for missing managers; BLOCKED when no manager is installed.

### Flow 24: Undo Flow Details

**When to run:** Diff changes `UndoHistoryView` (regret dialog, Show All/Show Less), `AppViewModel.restore`/`restoreWithReason`, `UndoManagerService` expiry, or the menu-bar undo in AppDelegate.

**Goal:** Verify the regret-reason dialog (5 reasons plus Skip), Show All (N)/Show Less, expired and restored row states, and the menu-bar undo path.

**Preconditions:** More than 8 executed actions for the Show All state, and at least one available undo record for restore paths.

**Steps (Given/When/Then):**
1. Given more than 8 undo records, when Undo History renders, then the first 8 show with a "Show All (N)" button; clicking it expands the list and the label becomes "Show Less".
2. Given an available undo record, when the user clicks Restore, then the "Why did you restore this?" dialog appears with 5 reasons (Needed later, Misclassified, Should have archived, not deleted, Wrong project, Too aggressive) and "Skip".
3. When the user selects a reason, then the record restores with the reason recorded for regret learning and the status reads "Undo completed."
4. When the user clicks Restore and then "Skip", then the record restores without recording a reason.
5. Given restored or expired records, when the list renders, then those rows show the checkmark.circle icon, restored/expired status text, and a disabled Restore button.
6. Given the menu bar, when the user clicks "Undo Last Action", then the most recent available record restores directly without the regret dialog and its row updates.

**Expected result:** The dialog offers all 5 reasons plus Skip; restore works with and without a reason; expired/restored rows are disabled; Show All (N)/Show Less toggles; menu-bar undo bypasses the dialog.

**Evidence to capture:** Snapshot of the Show All state, the regret dialog with all options, row states after restore, and the status messages.

**Pass criteria:** All 5 reasons plus Skip present; both restore paths work; expired and restored rows disabled; Show All (N)/Show Less toggles; menu-bar undo restores the latest record.

### Flow 25: Error-Path Flows

**When to run:** Diff changes `AppViewModel.runScan` guards, `AIGateway` failure handling, `ScanOrchestrator` AI catch, `SQLiteStore` fallbacks, or the HeaderBar error and temp-database display.

**Goal:** Verify guarded errors appear without crashing, AI failure degrades to a local-only scan, the temp-database banner renders, and errors are dismissible.

**Preconditions:** Folder mode with no folders selected (step 1), and a way to force the AI failure (step 2, an invalid API key with AI enabled).

**Steps (Given/When/Then):**
1. Given folder mode with no folders selected, when the user clicks Scan, then the header shows the error "Please select folders to scan." with a dismiss button and the app never enters the scanning state.
2. Given AI enabled with an invalid API key, when a scan runs, then AI classification fails gracefully, the scan still completes with local results, and no error blocks the workspace (AI-08 behavior).
3. Given the primary database fails at bootstrap, when the app launches, then the header shows the "Temporary database — data won't persist" label (isUsingTempDatabase).
4. Given an error banner is visible, when the user clicks the dismiss button (xmark.circle.fill), then the error clears.

**Expected result:** All error paths surface specific messages, never crash, and degrade gracefully.

**Evidence to capture:** Snapshot of the header error with the dismiss button, the scan completion status with a bad API key, and the temp-database banner.

**Pass criteria:** The no-folders error shows and dismisses; the scan completes despite AI failure; the temp-database banner renders in degraded mode; no crashes on any error path.

## Flow Selection Guide

Use this map to pick flows from a diff, mirroring the orchestrator's mapping table in `qa/SKILL.md`. When a diff touches several areas, run the listed flows plus the cross-flow regression (Flow 22).

| Code area | Relevant flows |
|---|---|
| `Sources/MacOSCleanerAppKit/App/MacOSCleanerApp.swift` | 10 (menu bar), 21 (notification precondition), 24 (menu-bar undo) |
| `Sources/MacOSCleanerAppKit/App/AppViewModel.swift` | All flows; core of 2, 3, 4, 13, 14, 15, 16, 17, 18, 20, 22, 24, 25 |
| `Sources/MacOSCleanerAppKit/UI/ContentView.swift` | 1 (layout), 3, 11, 14 (workspace shell), 21 (permission prompt) |
| `Sources/MacOSCleanerAppKit/UI/Views/HeaderBar.swift` | 2, 5 (scan progress), 12 (Cmd+R, Cmd+F), 13 (execute buttons and dialogs), 15 (Stop), 25 (error and temp-DB banner) |
| `Sources/MacOSCleanerAppKit/UI/Views/DashboardView.swift` | 9, 11 (metrics, treemap picker, forecast) |
| `Sources/MacOSCleanerAppKit/UI/Views/TreemapView.swift` | 11 (overlay modes, block selection) |
| `Sources/MacOSCleanerAppKit/UI/Views/RelationshipGraphView.swift` | 11, 14 |
| `Sources/MacOSCleanerAppKit/UI/Views/ActionStackView.swift` | 3, 4, 14, 16 |
| `Sources/MacOSCleanerAppKit/UI/Views/NaturalLanguagePlanView.swift` | 7, 12 (Cmd+Return), 17 |
| `Sources/MacOSCleanerAppKit/UI/Views/UndoHistoryView.swift` | 6, 14, 24 |
| `Sources/MacOSCleanerAppKit/UI/Views/WhyPanelView.swift` | 3 |
| `Sources/MacOSCleanerAppKit/UI/Views/SidebarView.swift` | 19 |
| `Sources/MacOSCleanerAppKit/UI/Views/OnboardingView.swift` | 1, 20 |
| `Sources/MacOSCleanerAppKit/UI/SettingsView.swift` | 8, 18 |
| `Sources/MacOSCleanerCore/Services/ScanOrchestrator.swift` | 2, 15, 22, 25 (AI failure) |
| `Sources/MacOSCleanerCore/Services/PlannerAgent.swift` | 7, 17, 22 |
| `Sources/MacOSCleanerCore/Services/ActionExecutor.swift` | 5, 13, 23 |
| `Sources/MacOSCleanerCore/Services/SafetyAuditor.swift` | 5, 13, 25 |
| `Sources/MacOSCleanerCore/Services/UndoManagerService.swift` | 6, 24 |
| `Sources/MacOSCleanerCore/Services/PackageManagerScanner.swift` | 23 |
| `Sources/MacOSCleanerCore/Services/MoCleanScanner.swift` | 19 (system modes), 23 |
| `Sources/MacOSCleanerCore/Services/NotificationScheduler.swift` | 21 |
| `Sources/MacOSCleanerCore/Services/SpaceForecaster.swift` | 11 (forecast) |
| `Sources/MacOSCleanerCore/Services/SQLiteStore.swift` | 18 (clear and export), 25 (temp DB) |
| `Sources/MacOSCleanerCore/Services/AIGateway.swift` | 20, 25 (bad key) |
| `Sources/MacOSCleanerCore/Services/KeychainStore.swift` | 20 |
| `Sources/MacOSCleanerCore/Services/InboxManager.swift` | 19 |
| `Sources/MacOSCleanerCore/Services/MemoryEngine.swift` | 4, 18 (calibration), 24 (regret) |
| `Sources/MacOSCleanerCore/Services/ReportGenerator.swift` | 9 |
| `Sources/MacOSCleanerCore/Models/DomainModels.swift` | All flows (shared model types) |
| `Package.swift` | Build, app launch |
| `Tests/**` | INCONCLUSIVE -- test-only changes don't affect app behavior |

## Per-Persona Variations

This app has no user authentication or role system. All testing is done as a single local user.

## Sidebar Controls

Additional testable sidebar controls that may be relevant depending on the diff (see Flow 19 for the full sidebar flow):

- **Scan mode picker:** Grouped menu picker with 20 modes across Crawl (Selected Folders / Home Folder / Developer Cleanup), System, Apps, Developer, and Backups & Large Files sections
- **Scan roots:** Add Downloads / Add Home shortcuts, per-root Open in Finder and Remove buttons, Clear All
- **Inbox button:** Creates a Cleanroom Inbox folder and adds it to the scan roots
- **Privacy mode picker:** Dropdown menu (Local Only / Metadata AI / Snippets; note Settings shows the full 5-mode picker)
- **BYOK AI toggle:** Enable/disable AI during scans; disabled while privacy mode is Local Only
- **Cleanup posture picker:** Segmented (Careful / Balanced / Deep) or menu (Conservative / Balanced / Aggressive) depending on available width
- **Report path:** Generated report file path shown at the sidebar bottom

## Dashboard Components

- **Metric cards:** Files Seen, Scanned bytes, Reviewable bytes, Projects count, Summaries count
- **Treemap:** Colored blocks proportional to bytes per finding category (170px height), with overlay picker (None / Risk Level / Category) and block selection with Clear Selection
- **Relationship graph:** Node-link visualization with hover highlight, edge-type legend, and empty-state CTAs
- **Storage forecast:** Daily growth rate and estimated days until the next threshold
- **Status bar:** Free disk space plus reclaimable bytes at the window bottom
- **Report button** in dashboard footer
- **Execution summary** text (operations count, failures count)

## Known Failure Modes

1. **macOS privacy permissions not granted.** The app needs Full Disk Access or specific folder permissions to scan. If permissions are missing, the scan may return empty results or show errors. In CI or fresh environments, this is a common blocker.
2. **Build failures from missing dependencies.** The project depends on `sqlite3` system library. If not available on the runner, `swift build` will fail. macOS runners typically have it.
3. **Keychain access in CI.** The KeychainStore requires macOS keychain access. In CI, the keychain may be locked or unavailable. API key tests should handle `KeychainError` gracefully.
4. **App launch timing.** The macOS app may take a few seconds to fully render after launch. Wait for the window to appear before interacting.
5. **Folder picker is a native NSOpenPanel.** Agent-browser may not be able to interact with the native macOS file dialog. If folder selection cannot be automated, report as BLOCKED and suggest using Home Folder mode instead (which doesn't require a file picker).
6. **Menu bar extra lives in the system menu bar, outside the app window.** The sparkle icon and its items are not part of the app window, so agent-browser may not be able to click them. Drive the menu bar via keyboard shortcuts (Cmd+O, Cmd+,, Cmd+Q), AX-level tooling, or manual verification. Closing the main window keeps the app alive (applicationShouldTerminateAfterLastWindowClosed returns false), so the menu bar extra remains available.
7. **Menu bar shortcuts may not reach the app from the driver.** Cmd+O/Cmd+,/Cmd+Q are attached to menu bar buttons; if the driver cannot synthesize global key events, verify via the menu items or a manual run.
8. **Notifications require a bundled .app.** `NotificationScheduler.canUseUserNotifications` returns false unless `Bundle.main.bundleURL.pathExtension == "app"` (or running under XCTest). Launched via `swift run` or the bare binary, no permission prompt and no notifications appear. Build and launch the .app bundle to test Flow 21; the unbundled no-op is expected behavior, not a failure.
9. **Launch-at-login registration requires a bundle.** `SMAppService.mainApp.register()` throws for non-bundled executables; the toggle reverts and an error appears. The revert-on-failure is expected behavior for unbundled builds (still testable, see Flow 18).
10. **NSSavePanel is a native dialog.** Export Database uses NSSavePanel, and the notification permission prompt is a system dialog. Agent-browser may not be able to interact with either; report as BLOCKED if they cannot be automated, and pre-grant notification permission in System Settings when needed.
11. **Package manager cleanup is machine-dependent.** Package cleanup actions only appear in Developer Cleanup mode and only for installed tools (brew, docker, npm, pip). Check `which brew docker npm pip` first; if none are installed, mark Flow 23 as BLOCKED.
12. **Menu bar "Undo Last Action" bypasses the regret dialog.** `AppDelegate.undoLastAction` restores the most recent record directly and silently no-ops when no records exist. This is expected behavior, not a bug.
