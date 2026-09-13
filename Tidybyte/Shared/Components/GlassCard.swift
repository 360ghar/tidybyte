import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = Spacing.lg

    init(padding: CGFloat = Spacing.lg, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        // Single rendering path: the struct delegates to the `glassCard`
        // modifier so the card look can never drift between the two entry
        // points (de-slop: this used to duplicate the styling inline).
        content.glassCard(padding: padding)
    }
}

// View modifier version for easier application
struct GlassCardModifier: ViewModifier {
    var padding: CGFloat = Spacing.lg

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// Reduce Transparency is a legibility request, so the translucent surface
    /// yields to a real one. Increased Contrast thickens and darkens the border
    /// rather than changing the fill, so the card still reads as a card.
    private var fill: Color {
        reduceTransparency ? .opaqueCardSurface : .cardSurface
    }

    private var border: Color {
        reduceTransparency || contrast == .increased ? .opaqueCardBorder : .cardBorder
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 1.5 : 1
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.large)
                            .strokeBorder(border, lineWidth: borderWidth)
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
