import SwiftUI

/// Shared "Select All" / "Deselect All" toggle used in the toolbars of every
/// screen with multi-select media. Callers own the ToolbarItem placement and
/// any visibility/enabled conditions.
struct SelectAllToolbarButton: View {
    let allSelected: Bool
    let selectAll: () -> Void
    let deselectAll: () -> Void

    var body: some View {
        Button(allSelected ? "Deselect All" : "Select All") {
            HapticHelper.impact(.light)
            if allSelected {
                deselectAll()
            } else {
                selectAll()
            }
        }
    }
}
