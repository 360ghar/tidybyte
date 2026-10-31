---
name: qa
description: >
  Run QA tests for macOS Cleaner. Analyzes git diff to determine affected areas,
  runs configured test flows for the desktop app, and generates diff-targeted tests.
  Uses agent-browser for desktop GUI testing.
  Use when testing PRs, releases, or smoke testing the application.
---

# QA Orchestrator

**SCOPE: This skill performs manual/functional QA only -- verifying that the application actually works by interacting with it as a real user would (browser, TUI, API calls). Do NOT run or report on CI checks, linting, typecheck, unit tests, or any static analysis. Those are handled by separate workflows.**

## Step 1: Load Configuration

Read `macos/.agents/skills/qa/config.yaml` for environment URLs, credentials, personas, and app definitions. All commands and paths below are relative to `macos/` (the Swift package root in this monorepo) unless noted.

## Step 2: Determine Target Environment

This is a local-first macOS desktop app with no remote environments. The QA target is always the local build.

- Build the app: `swift build` (from `macos/`)
- The built binary is `macos/.build/debug/Tidybyte`
- Build the launchable bundle with `Scripts/build-app.sh direct` (from `macos/`), then launch `macos/.build/Tidybyte.app` for GUI testing via agent-browser

**CRITICAL: This app has no web deployment.** All testing happens against the locally built binary from the current branch code. Never test against a different version.

## Step 3: Analyze Git Diff

Run `git diff` to determine what changed. Map changed files to apps using the path_patterns in config.yaml.

| Path pattern | App |
|---|---|
| `Sources/MacOSCleanerAppKit/**` | desktop |
| `Sources/MacOSCleanerAppKit/**` | desktop |
| `Sources/MacOSCleanerCore/**` | desktop |
| `Package.swift` | desktop |
| `Tests/**` | desktop |

Files that don't match ANY app's path_patterns (e.g., `.agents/skills/**`, `docs/**`, `.github/**`, `AGENTS.md`, `DESIGN.md`, `README.md`) are NOT associated with any app. Do NOT run app test flows for them.

For the desktop app:

- Run ONLY flows relevant to the changed code areas
- Generate ADDITIONAL targeted tests based on the specific changes in the diff

If NO app is affected by the diff (e.g., docs-only, CI-only, or config-only changes), report as INCONCLUSIVE: "No app code changed -- QA not applicable for this diff." Do NOT run any app flows.

## Step 4: Pre-flight Checks

Run pre-flight checks for the desktop app:

1. **Build the app:** `swift build` from `macos/`
2. **Verify the binary exists:** `macos/.build/debug/Tidybyte`
3. **Build the bundle:** `Scripts/build-app.sh direct` from `macos/` (GUI flows need the `.app` bundle)
4. **Launch the app** via agent-browser or `open .build/Tidybyte.app`
5. **Wait for the app window** to appear (check for the "Tidybyte" title)

If a pre-flight check fails, report it as BLOCKED with the specific error and remediation steps.

## Step 5: Execute Diff-Relevant Flows Only

Read the sub-skill from `macos/.agents/skills/qa-desktop/SKILL.md`.

The sub-skill contains a MENU of available test flows. You must:

1. Read the diff carefully and identify which flows are relevant to the change
2. Run those flows PLUS any adjacent flows that verify the change integrates correctly
3. Do NOT run completely unrelated flows (e.g., if the diff only changes SafetyAuditor, do NOT test Settings UI)
4. If no existing flow covers the change, write a NEW ad-hoc test that directly verifies the changed behavior
5. Do NOT run unit tests, lint, typecheck, or any automated test suite. This is manual/functional QA -- interact with the app as a real user would.

### Mapping Code Areas to Flows

| Code area | Relevant flows |
|---|---|
| `Sources/MacOSCleanerAppKit/UI/**` | GUI flows: onboarding, dashboard, action rows, why panel, sidebar, settings |
| `Sources/MacOSCleanerAppKit/App/AppViewModel.swift` | All ViewModel-driven flows: scan, approve/reject, execute, undo, NL command |
| `Sources/MacOSCleanerCore/Services/ScanOrchestrator.swift` | Scan flow, dashboard display |
| `Sources/MacOSCleanerCore/Services/ActionExecutor.swift` | Execute actions, undo flow |
| `Sources/MacOSCleanerCore/Services/SafetyAuditor.swift` | Safety checks, high-risk rejections, approve/reject behavior |
| `Sources/MacOSCleanerCore/Services/DuplicateDetector.swift` | Scan flow, duplicate findings |
| `Sources/MacOSCleanerCore/Services/CleanerRuleEngine.swift` | Scan findings, action proposals |
| `Sources/MacOSCleanerCore/Services/AIGateway.swift` | AI classification, settings |
| `Sources/MacOSCleanerCore/Services/PlannerAgent.swift` | Natural language command, plan generation |
| `Sources/MacOSCleanerCore/Services/MemoryEngine.swift` | Always/Never memory rules |
| `Sources/MacOSCleanerCore/Services/UndoManagerService.swift` | Undo flow |
| `Sources/MacOSCleanerCore/Services/ReportGenerator.swift` | Report generation |
| `Sources/MacOSCleanerCore/Services/ContentExtractor.swift` | Content summaries display |
| `Sources/MacOSCleanerCore/Services/PackageManagerScanner.swift` | Package cleanup findings |
| `Sources/MacOSCleanerCore/Models/DomainModels.swift` | All flows (shared model types) |
| `Package.swift` | Build, app launch |
| `Tests/**` | INCONCLUSIVE -- test-only changes don't affect app behavior |

## Step 6: Evidence Capture

After each significant test step, capture evidence. Use **text snapshots as primary evidence** -- they render inline in the PR comment with no image hosting issues.

For the macOS desktop app (agent-browser):

- Use `agent-browser snapshot` to capture the app's accessibility tree as text evidence
- Save screenshot files to `./qa-results/$RUN_ID/` for the artifact upload
- Do NOT embed `![image](url)` markdown in the report -- screenshot images cannot be displayed inline in GitHub PR comments. Instead, mention the filename and note that it's available in the downloadable artifacts.

Evidence quality rules:

- Focus on the RELEVANT content. Trim snapshots to the meaningful part.
- Label each snapshot clearly: what it shows and why it matters for the test.
- NEVER embed broken image links. If you can't verify an image URL will resolve, use text evidence instead.
- The workflow uploads all files in `./qa-results/` as a downloadable artifact -- reference that for visual evidence.

## Step 7: Test Quality Gate

TEST QUALITY REQUIREMENTS:

1. CHANGE-SPECIFIC FIRST. Prioritize tests that directly verify the behavioral change in the diff. At least half your tests should be testing the new/changed feature itself.
2. INTEGRATION TESTS ARE VALID. Tests that verify the change integrates correctly with existing features are good. These are NOT smoke tests -- they verify the change didn't break integration points.
3. NO UNRELATED FLOWS. Do NOT test features completely unrelated to the diff.
4. NO AUTOMATED TEST SUITES. Do NOT run swift test, xcodebuild test, or any CI-style checks. This is manual/functional QA only.
5. NEGATIVE TESTS. Include at least 1 test verifying error handling or boundary conditions related to the change.
6. INTERACTIVE TESTING. Test by actually interacting with the app as a real user would.
7. INCONCLUSIVE IF UNSURE. If you cannot articulate what the PR changes, mark as INCONCLUSIVE rather than PASS.

## Step 8: Handle Failures

**Never silently skip a flow.** If a flow cannot complete, report it as BLOCKED with what was tried and how the user can fix it. Then continue to the next flow -- never abort the entire run for a single failure.

## Step 9: Generate Report

Generate the report at `./qa-results/report.md` using `macos/.agents/skills/qa/REPORT-TEMPLATE.md`.

The report MUST follow the template. Key rules:

- Start with `## QA Report` heading followed by the test results table
- Result column MUST use emojis: :white_check_mark: PASS, :x: FAIL, :no_entry: BLOCKED, :warning: FLAKY, :grey_question: INCONCLUSIVE
- Keep it CONCISE. The table + a short "Action Required" section (if any) + collapsed screenshots = the entire report.
- Do NOT include: "Behavioral Change Summary", "Blocked Flows" prose, "Info" metadata table, or verbose explanations of what the diff does.
- Do NOT report setup/prerequisite steps (building, startup, launching) as test rows. Those are means to an end, not test cases. Only report rows that verify actual user-facing behavior or the specific behavioral change from the diff.
- Put ALL evidence in a single collapsed `<details>` block
- For web/evidence: embed accessibility tree snapshots as text. Reference screenshot filenames for visual proof (available in downloadable artifacts). Do NOT use `![image](url)` markdown.

## Step 10: Suggest Skill Updates (Failure Learning)

After generating the report, check if any BLOCKED or FAIL results revealed a **testing environment insight** that would help future QA runs succeed.

Read the `failure_learning` field from config.yaml (`suggest_in_report`): include the suggestion table in the PR comment report only. Do NOT write `skill-updates.json`.

Format as a table with severity, collapsible fix prompts, and a count in the heading:

## Suggested Skill Updates (N issues found)

| # | Severity | File | Issue | Fix Prompt |
| --- | --- | --- | --- | --- |
| 1 | <emoji> <level> | `<file>` | <short description> | <details><summary>Copy</summary><br>`<full droid prompt to fix the issue>`</details> |

**Severity levels:**

- `🔴 Breaking` -- Causes test failures every run
- `🟡 Degraded` -- Causes intermittent failures or suboptimal behavior
- `🔵 Info` -- New knowledge that improves future runs but doesn't cause failures

Do NOT suggest updates for failures already covered in Known Failure Modes, bad selectors, or expected behavior changes from the PR. If no genuinely new environment insights were discovered, omit this section entirely.
