import SwiftUI

// MARK: - Adaptive Grids

/// Width-driven grid column definitions, shared so every grid reflows the same way.
///
/// We use `GridItem(.adaptive(...))` rather than computing a column count from
/// `horizontalSizeClass` because the column count then follows the *available width* —
/// which is what actually changes across iPhone, iPad full-screen, landscape, Split View,
/// Slide Over, and Stage Manager. A size-class approach would still render a few huge
/// columns in a wide iPad pane that reports `.regular`.
///
/// An `.adaptive` `LazyVGrid` takes a *single* `GridItem` (it expands it internally),
/// so each call site passes one of these arrays in place of the old explicit 2/3-item arrays.
enum ResponsiveGrid {
    /// Dense, square photo thumbnails. ~110pt min keeps 3 columns on a ~390pt iPhone and
    /// grows to ~6 on an 11" iPad and ~7 in landscape / 13". `maximum` caps cell growth so
    /// thumbnails never balloon on the widest screens.
    static func photo(spacing: CGFloat = Spacing.xs) -> [GridItem] {
        [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: spacing)]
    }

    /// Text-bearing tool cards, which need more room. ~165pt min keeps 2 columns on iPhone
    /// and grows to 3–4 on iPad; `maximum` stops cards from stretching absurdly wide.
    static func card(spacing: CGFloat = Spacing.md) -> [GridItem] {
        [GridItem(.adaptive(minimum: 165, maximum: 260), spacing: spacing)]
    }
}

// MARK: - Readable Width

/// Caps content at a comfortable measure and centers it, so scrollable / form content
/// doesn't stretch edge-to-edge on iPad. The inner frame caps the width; the outer frame
/// centers that capped content in whatever space is available. A no-op on iPhone, where
/// the screen is narrower than `maxWidth`.
struct ReadableWidthModifier: ViewModifier {
    var maxWidth: CGFloat = 700

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Centers content at a readable max width (default 700pt). Apply to the inner
    /// `VStack`/content of a `ScrollView`, not to a `List` (a fixed-width `List` clips its
    /// separators and swipe actions).
    func readableWidth(_ maxWidth: CGFloat = 700) -> some View {
        modifier(ReadableWidthModifier(maxWidth: maxWidth))
    }
}
