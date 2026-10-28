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
            // A material, not `cardSurface`: the notice floats over the tabs'
            // content, and a 6% wash left that content showing through the text.
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.large))
            .padding(.horizontal, Spacing.lg)
            .onChange(of: notice.id) { showInstructions = false }
        }
    }
}

extension View {
    /// Shows the Recently Deleted notice as a bottom inset on this screen.
    ///
    /// Applied per screen rather than on the `TabView`: since iOS 26 the tab
    /// bar floats over the tabs' content, so an inset on the `TabView` sat
    /// underneath the tab bar and took its taps. Not on a `NavigationStack`
    /// either: pushed screens don't get its inset, and a tool's bottom action
    /// bar ended up behind the notice.
    func recentlyDeletedNoticeInset() -> some View {
        modifier(RecentlyDeletedNoticeInset())
    }
}

private struct RecentlyDeletedNoticeInset: ViewModifier {
    @Environment(AppNavigation.self) private var appNavigation

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            // The completion screen shows the notice inline instead.
            if !appNavigation.isShowingSwipeCompletion {
                RecentlyDeletedNotice()
            }
        }
    }
}
