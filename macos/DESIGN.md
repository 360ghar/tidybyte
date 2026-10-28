# Tidybyte for Mac — Design

## Direction

Tidybyte looks and behaves like Apple's own Mac apps: System Settings › Storage for the overview, Photos for media review, Finder for files. Standard SwiftUI navigation, toolbars, sheets, and controls receive macOS 26 Liquid Glass from the system. Custom glass is used only for the floating action bars. macOS 26 is the minimum supported version.

## Layout and navigation

One `NavigationSplitView` with a source-list sidebar, one detail column, and a native inspector.

| Sidebar | Rows |
| --- | --- |
| (top) | Overview |
| Clean | System Junk, Developer, Large & Old Files, Duplicates, Photos & Media |
| Apps | Applications, Leftovers, Login Items |
| Insights | Space Explorer, Changes, History |

- Each review row shows only its own plan actions (`AppDestination.forCategory`). Bulk Approve and Reject act on the current row only.
- Sidebar badges show bytes still waiting for a decision.
- Photos & Media is a `NavigationStack`: a grouped list of tools that pushes each tool. Swipe Review is one of its rows.
- Changes and History switch views with a segmented control in the toolbar.
- The App Store build shows Overview, Photos & Media, and History only.

Default window 1200 × 800 points; detail column minimum 420 points, so macOS collapses the sidebar before content clips. Sidebar 200–280 points. Inspector 280–400 points; it never turns into a sheet.

## Toolbar

Contextual items first (View menu in Space Explorer; Risk filter and Ask Tidybyte on review rows), then a fixed `ToolbarSpacer`, then **Scan** as the one `.glassProminent` action (Stop while busy), then the inspector toggle. Progress is the window subtitle. Errors and permission notices appear in a strip under the toolbar only while they need attention.

## Visual system

- System text styles and SF Symbols through `Label`. Monospaced text only for paths and commands; sizes use monospaced digits.
- Semantic system colors; the user's accent color; categorical color only for data. Risk shows a colored symbol plus text, never color alone.
- Rounded rectangles with `Radius.card` / `Radius.cardCompact`; no square strokes. Selection is an accent border plus a check badge (Photos style).
- Glass only on navigation-layer controls: the approved-changes bar on review rows, the tool action bar, and the Swipe buttons, each in one `GlassEffectContainer`. No glass on rows, cards, forms, grid cells, sheets, or charts.
- No in-app appearance switch: the app follows System Settings.

## Keyboard and menus

| Shortcut | Command |
| --- | --- |
| ⌘R | Scan |
| ⌘N | Scan Options… |
| ⌘1 – ⌘9 | Go to Overview, System Junk, Developer, Large & Old Files, Duplicates, Photos & Media, Applications, Space Explorer, History |
| ⌘F | Find in the current row |
| ⌘K | Ask Tidybyte |
| ⇧⌘A / ⇧⌘R | Approve / Reject selected action |
| View menu | Show or hide the sidebar and the inspector (system commands) |
| ⌘A, Delete, double-click | Select all, Move to Trash…, Quick Look in media grids |
| ⌘Z | Edit ▸ Undo reverts the last Swipe decision |

## Behavior and safety

Selection, approval, and execution are separate steps. Every cleanup runs through one immutable confirmation sheet that lists counts per sidebar area, revalidates the plan, and says "Move to Trash" when every action is a Trash move. Recovery copy states the limits, including package-manager cleanup. Service safety policy is unchanged by the UI.

Accessibility: VoiceOver labels and selected state on grid cells, keyboard paths for every pointer action, Reduce Motion, Reduce Transparency (system glass falls back), Increase Contrast.
