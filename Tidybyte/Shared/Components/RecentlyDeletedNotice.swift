import SwiftUI

struct RecentlyDeletedNotice: View {
    @Environment(\.openURL) private var openURL
    @State private var showInstructions = false

    var body: some View {
        if let notice = CleanupLedger.shared.deletionNotice {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(notice.message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if showInstructions {
                    Text("Open Photos, find Recently Deleted under Utilities, then unlock it and delete the items you no longer need.")
                        .font(.caption)
                }
                HStack {
                    Button("Open Photos") {
                        guard let url = URL(string: "photos-redirect://") else { return }
                        openURL(url) { accepted in
                            if accepted { CleanupLedger.shared.dismissDeletionNotice(id: notice.id) }
                            else { showInstructions = true }
                        }
                    }
                    Spacer()
                    Button("Dismiss") { CleanupLedger.shared.dismissDeletionNotice(id: notice.id) }
                }
                .frame(minHeight: 44)
            }
            .padding(Spacing.md)
            .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: CornerRadius.large))
            .padding(.horizontal, Spacing.lg)
            .onChange(of: notice.id) { showInstructions = false }
        }
    }
}
