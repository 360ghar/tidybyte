import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = Spacing.lg

    init(padding: CGFloat = Spacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .fill(Color.cardSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.large)
                            .strokeBorder(Color.cardBorder, lineWidth: 1)
                    }
            }
            .subtleShadow()
    }
}

// View modifier version for easier application
struct GlassCardModifier: ViewModifier {
    var padding: CGFloat = Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .fill(Color.cardSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.large)
                            .strokeBorder(Color.cardBorder, lineWidth: 1)
                    }
            }
            .subtleShadow()
    }
}

extension View {
    func glassCard(padding: CGFloat = Spacing.lg) -> some View {
        modifier(GlassCardModifier(padding: padding))
    }
}
