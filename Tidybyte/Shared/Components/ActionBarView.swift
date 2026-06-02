import SwiftUI

struct ActionBarView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
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
