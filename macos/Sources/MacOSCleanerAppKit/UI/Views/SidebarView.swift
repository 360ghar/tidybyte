import MacOSCleanerCore
import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        let pending = model.pendingBytesByDestination
        List(
            selection: Binding<AppDestination?>(
                get: { model.destination },
                set: { if let destination = $0 { model.destination = destination } }
            )
        ) {
            ForEach(Array(AppDestination.sections.enumerated()), id: \.offset) { _, section in
                if let title = section.title {
                    Section(title) { rows(section.rows, pending: pending) }
                } else {
                    rows(section.rows, pending: pending)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func rows(_ rows: [AppDestination], pending: [AppDestination: Int64]) -> some View {
        ForEach(rows) { row in
            Label(row.title, systemImage: row.icon)
                .badge(badge(for: row, pending: pending))
                .tag(row)
        }
    }

    /// Reclaimable bytes still waiting for a decision. Empty rows show no badge.
    private func badge(for row: AppDestination, pending: [AppDestination: Int64]) -> Text? {
        guard let bytes = pending[row], bytes > 0 else { return nil }
        return Text(bytes.formattedByteCount)
    }
}
