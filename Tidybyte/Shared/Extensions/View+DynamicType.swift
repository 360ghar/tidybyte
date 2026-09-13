import SwiftUI

// MARK: - Dynamic Type Control Geometry

/// Base (Large content size) dimensions for the app's fixed-size controls, plus
/// the growth ceiling applied to all of them.
///
/// Text should use semantic fonts (`.headline`, `.body`, …) and scales for
/// free. These values exist for *control geometry* — the circular swipe action
/// buttons, tool icon tiles, and empty-state glyphs — which are drawn at a
/// fixed size and would otherwise stay tiny at accessibility text sizes.
enum ScaledSize {
    /// Swipe session primary actions (delete / keep).
    static let actionButton: CGFloat = 60

    /// Swipe session secondary actions (skip / add to album).
    static let secondaryActionButton: CGFloat = 48

    /// Tool icon tile on the swipe home and cleanup home cards.
    static let toolIconTile: CGFloat = 48

    /// Icon inside a tool card's 44pt badge.
    static let toolCardIcon: CGFloat = 44

    /// Empty-state and idle-state glyph.
    static let stateGlyph: CGFloat = 72

    /// Glow circle drawn behind a state glyph.
    static let stateHalo: CGFloat = 160

    /// Session-complete celebration glyph. Larger than the state glyph because
    /// it is the screen's single focal point rather than one row among many.
    static let celebrationGlyph: CGFloat = 80

    /// Glow circle drawn behind the celebration glyph.
    static let celebrationHalo: CGFloat = 140

    /// Video play affordance centered on the top swipe card. Smaller than the
    /// state glyph because it floats over the photo itself and must not cover it.
    static let videoPlayGlyph: CGFloat = 56

    /// Ceiling on Dynamic Type growth for control geometry.
    ///
    /// Unclamped, Accessibility XXXL (roughly a 2.1x body ratio) turns the 60pt
    /// action button into ~127pt — four of them plus spacing no longer fit the
    /// width of an iPhone SE, and the row clips. 1.5x keeps controls
    /// comfortably larger without breaking the layout that contains them.
    static let maxScale: CGFloat = 1.5
}

private struct ScaledSquareModifier: ViewModifier {
    // The `= 1` default is never used — `init` always assigns the wrapper. It is
    // required because the `@ScaledMetric(relativeTo:)` attribute form needs a
    // wrappedValue to resolve at the declaration site.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 1
    private let cap: CGFloat

    init(base: CGFloat, cap: CGFloat) {
        _side = ScaledMetric(wrappedValue: base, relativeTo: .body)
        self.cap = cap
    }

    func body(content: Content) -> some View {
        let clamped = min(side, cap)
        content.frame(width: clamped, height: clamped)
    }
}

private struct ScaledGlyphModifier: ViewModifier {
    // See `ScaledSquareModifier`: the default is unused, the attribute form just
    // needs a wrappedValue to resolve.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 1
    private let cap: CGFloat
    private let weight: Font.Weight

    init(base: CGFloat, cap: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: base, relativeTo: .largeTitle)
        self.cap = cap
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(size, cap), weight: weight))
    }
}

extension View {
    /// Sizes a control to a Dynamic-Type-scaled square, clamped at
    /// `ScaledSize.maxScale` so accessibility text sizes enlarge the control
    /// without breaking the layout around it.
    ///
    /// Use for controls whose hit target and shape are fixed (circular action
    /// buttons, icon tiles), not for text.
    func scaledSquare(_ base: CGFloat) -> some View {
        modifier(ScaledSquareModifier(base: base, cap: base * ScaledSize.maxScale))
    }

    /// Applies a Dynamic-Type-scaled size to an SF Symbol, clamped with the same
    /// ceiling as `scaledSquare`.
    ///
    /// Decorative glyphs scale less aggressively than `scaledSquare` because the
    /// container they sit in is usually a fixed frame; the cap keeps the glyph
    /// from outgrowing it.
    func scaledGlyph(_ base: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledGlyphModifier(base: base, cap: base * ScaledSize.maxScale, weight: weight))
    }
}
