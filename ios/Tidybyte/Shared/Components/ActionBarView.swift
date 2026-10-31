import SwiftUI

struct ActionBarView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // E7: the adaptive border token, not a hardcoded near-invisible
            // white that disappears in light mode.
            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: 0.5)

            HStack {
                content
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            // Keep the bar's controls at a readable measure and centered on iPad,
            // while the material background below still spans the full width.
            .readableWidth()
        }
        .background(.regularMaterial)
    }
}
