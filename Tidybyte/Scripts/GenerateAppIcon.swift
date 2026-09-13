#!/usr/bin/env swift

// Generates the TidyByte app icon.
//
// This script is the single source of truth for the app mark. It writes:
//   * Tidybyte/Resources/Assets.xcassets/AppIcon.appiconset/  (light, dark, tinted)
//   * (with --sync-site) the site copies under public/assets/img/
//
// Usage, from the repository root:
//   swift Tidybyte/Scripts/GenerateAppIcon.swift              # regenerate everything
//   swift Tidybyte/Scripts/GenerateAppIcon.swift --check      # verify what is on disk
//   swift Tidybyte/Scripts/GenerateAppIcon.swift --sync-site  # also refresh the site
//
// The mark is a tidy stack of three photo cards (violet, periwinkle, brand blue)
// on a light field, with a white shine sparkle above: cleaning reads as sparkle,
// not as a checkmark.
//
// The website copies under public/assets/img/ are written only by --sync-site, and
// currently lag the app icon on purpose: the app mark leads, so the site keeps the
// art it already has until someone runs that mode.
//
// The asset catalog uses Xcode's single-size format: one 1024x1024 image per
// appearance, and Xcode generates every smaller size from it. Two facts forced
// that choice, both verified by compiling the catalog with actool:
//
//   1. The dark and tinted appearances are only honored in the single-size
//      format. In the older per-size format actool accepts the `appearances`
//      keys and then silently drops them, producing light-only renditions.
//   2. Per-size hand-tuned art is therefore not an option alongside dark and
//      tinted. It is also not needed: with the card offset below, downsampling
//      the 1024 keeps 100% of the back card's pixel footprint at 20pt (see the
//      offset note on `Art.offset`).
//
// Every PNG is written opaque. App Store validation rejects the marketing icon
// if it carries an alpha channel (ITMS-90717).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - The mark

/// The mark's geometry, in a 0...1 space on both axes, with y pointing up.
///
/// One art serves every size, because Xcode downsamples the 1024. The values here
/// are the ones that survive that downsampling, so they are not free parameters:
/// changing `offset` or `checkStrokeFraction` degrades the small sizes.
///
/// The app icon stacks three cards (`depth` 3) after the shine redesign: violet
/// behind up-right, periwinkle in the middle, brand blue in front down-left, with
/// a white sparkle on top. The table below measured the old two-card art and now
/// documents `siteArt`'s offset, which keeps the two-card mark on the website:
///
///   offset   20px   29px   40px   58px   60px   76px   80px   120px
///   0.065   -50%   -44%   -53%   -57%   -57%   -60%   -48%   -51%
///   0.105    +4%    -9%    -1%    -5%   -11%    -9%    -3%    -6%
///   0.115    +4%    +1%     0%     0%     0%     0%     0%    +3%
struct Art {
    /// Nothing is drawn outside this inset, so the iOS superellipse mask can never
    /// clip the mark. The app icon runs a comfortable inset (~15%), Apple-icon
    /// style: the stack floats on its field with air around it, room for the shine
    /// up top. The website mark runs tighter, because there the mark is the entire
    /// icon.
    let inset: CGFloat

    /// Front and back cards share one aspect ratio at every size, so the mark
    /// never reads as a different shape. 0.862 is the frame in favicon.svg; the app
    /// icon squares the cards off, which is the cheapest way to fill a square canvas
    /// and is worth 16% of the mark's height at 20pt.
    let cardAspect: CGFloat

    /// Card width, filled out to whatever the inset allows once the offset is
    /// accounted for. A larger card also means a larger checkmark, which is the
    /// other thing that has to survive downsampling.
    let cardWidthRequested: CGFloat

    /// Step offset between stacked cards, toward the top-right. This is the single
    /// most important value in the file: it sets how much of each card stays
    /// visible, and therefore whether the icon reads as a stack once iOS has scaled
    /// it down to 20pt. See the table above.
    let offset: CGFloat

    /// Checkmark stroke as a fraction of the front card's width.
    let checkStrokeFraction: CGFloat

    /// The dark stroke under the check, as a multiple of its width. Only the
    /// appearances whose check sits close in luminance to its card use one.
    let checkHaloMultiplier: CGFloat

    /// Dark stroke inside the front card's edge. Only the site's two-card mark uses
    /// one: it is the seam that separates its two cards. Unused by the app icon.
    let seamFraction: CGFloat

    /// How many cards the stack holds: 3 for the app icon, 2 for the site mark.
    let depth: Int

    /// Shine sparkle center in mark space (y-up), sitting on the front card's
    /// top-right corner, plus its outer radius. Radius 0 draws no shine, which is
    /// how the site mark (with its check instead) opts out.
    let sparkleCenter: CGPoint
    let sparkleRadius: CGFloat

    /// Smaller satellite sparkle on the back card. Same opt-out by zero radius.
    let satelliteCenter: CGPoint
    let satelliteRadius: CGFloat

    /// Checkmark path in front-card-local coordinates (origin bottom-left, 0...1).
    /// Derived from the path in public/assets/img/favicon.svg.
    let checkPathLocal: [CGPoint]

    init(
        inset: CGFloat,
        cardAspect: CGFloat,
        cardWidthRequested: CGFloat = 0.80,
        offset: CGFloat = 0.115,
        checkStrokeFraction: CGFloat = 0.13,
        checkHaloMultiplier: CGFloat = 1.6,
        seamFraction: CGFloat = 0.035,
        depth: Int = 2,
        sparkleCenter: CGPoint = CGPoint(x: 0.5, y: 0.5),
        sparkleRadius: CGFloat = 0,
        satelliteCenter: CGPoint = CGPoint(x: 0.5, y: 0.5),
        satelliteRadius: CGFloat = 0
    ) {
        self.inset = inset
        self.cardAspect = cardAspect
        self.cardWidthRequested = cardWidthRequested
        self.offset = offset
        self.checkStrokeFraction = checkStrokeFraction
        self.checkHaloMultiplier = checkHaloMultiplier
        self.seamFraction = seamFraction
        self.depth = depth
        self.sparkleCenter = sparkleCenter
        self.sparkleRadius = sparkleRadius
        self.satelliteCenter = satelliteCenter
        self.satelliteRadius = satelliteRadius
        self.checkPathLocal = [
            CGPoint(x: 0.33, y: 0.48),
            CGPoint(x: 0.44, y: 0.38),
            CGPoint(x: 0.67, y: 0.66),
        ]
    }

    /// Card width after the inset and the stack's total spread have taken their
    /// share, so every card still fits the safe area.
    var cardWidth: CGFloat {
        min(cardWidthRequested, 1 - 2 * inset - offset * CGFloat(depth - 1))
    }

    var cardHeight: CGFloat { cardWidth * cardAspect }

    /// Half the stack's spread. Cards sit symmetric about the center: front
    /// down-left, back up-right, middle dead center when there are three.
    var shift: CGFloat { offset * CGFloat(depth - 1) / 2 }

    var frontRect: CGRect {
        let cx = 0.5 - shift
        let cy = 0.5 - shift
        return CGRect(x: cx - cardWidth / 2, y: cy - cardHeight / 2, width: cardWidth, height: cardHeight)
    }

    var midRect: CGRect {
        CGRect(x: 0.5 - cardWidth / 2, y: 0.5 - cardHeight / 2, width: cardWidth, height: cardHeight)
    }

    var backRect: CGRect {
        let cx = 0.5 + shift
        let cy = 0.5 + shift
        return CGRect(x: cx - cardWidth / 2, y: cy - cardHeight / 2, width: cardWidth, height: cardHeight)
    }

    /// Bounding square of a sparkle, for the inset check.
    func sparkleBounds(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    var corner: CGFloat { 0.20 * min(cardWidth, cardHeight) }

    var checkStroke: CGFloat { checkStrokeFraction * cardWidth }

    var seam: CGFloat { seamFraction * cardWidth }

    /// Maps a front-card-local point into the mark's 0...1 space.
    func checkPoint(_ local: CGPoint) -> CGPoint {
        CGPoint(
            x: frontRect.origin.x + local.x * frontRect.width,
            y: frontRect.origin.y + local.y * frontRect.height
        )
    }

    /// Bounding box of the drawn checkmark, including stroke bleed.
    var checkBounds: CGRect {
        let points = checkPathLocal.map(checkPoint)
        var bounds = CGRect(x: points[0].x, y: points[0].y, width: 0, height: 0)
        for point in points.dropFirst() {
            bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return bounds.insetBy(dx: -checkStroke * checkHaloMultiplier / 2, dy: -checkStroke * checkHaloMultiplier / 2)
    }

    /// Everything the renderer can put ink on: all cards, the shine, and the
    /// site mark's check (drawn from the front card, so inside the union anyway).
    var contentBounds: CGRect {
        var bounds = frontRect.union(backRect).union(checkBounds)
        if depth >= 3 { bounds = bounds.union(midRect) }
        if sparkleRadius > 0 { bounds = bounds.union(sparkleBounds(center: sparkleCenter, radius: sparkleRadius)) }
        if satelliteRadius > 0 { bounds = bounds.union(sparkleBounds(center: satelliteCenter, radius: satelliteRadius)) }
        return bounds
    }
}

/// The app icon's mark: three cards fanned up-right (violet, periwinkle, brand
/// blue), each step 0.075, with a white shine sparkle riding the front card's
/// top-right corner and a satellite on the back card. The stack spans 0.15 to 0.85
/// of the canvas: presence at 20pt without touching the mask.
let art = Art(
    inset: 0.15,
    cardAspect: 1.0,
    cardWidthRequested: 0.55,
    offset: 0.075,
    checkStrokeFraction: 0.14,
    depth: 3,
    sparkleCenter: CGPoint(x: 0.70, y: 0.70),
    sparkleRadius: 0.055,
    satelliteCenter: CGPoint(x: 0.79, y: 0.55),
    satelliteRadius: 0.022
)

/// The website mark, still on the original geometry so that the app icon leading
/// does not silently restyle the site the moment anyone regenerates it.
let siteArt = Art(inset: 0.12, cardAspect: 0.862)


// MARK: - Colors

struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    init(_ hex: UInt32) {
        self.r = CGFloat((hex >> 16) & 0xFF) / 255
        self.g = CGFloat((hex >> 8) & 0xFF) / 255
        self.b = CGFloat(hex & 0xFF) / 255
    }

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }

    var luminance: CGFloat { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// Blends `t` of the way toward this color's own gray. Keeps the dark
    /// appearance from glaring against a black home screen.
    func desaturated(_ t: CGFloat) -> RGB {
        let gray = luminance
        return RGB(r: r + (gray - r) * t, g: g + (gray - g) * t, b: b + (gray - b) * t)
    }

    /// Composites self over `background` at `alpha`, returning an opaque color.
    /// Keeping the result opaque means the renderer never has to rely on alpha
    /// blending, which is what lets the PNGs ship with no alpha channel.
    func over(_ background: RGB, alpha: CGFloat) -> RGB {
        RGB(
            r: self.r * alpha + background.r * (1 - alpha),
            g: self.g * alpha + background.g * (1 - alpha),
            b: self.b * alpha + background.b * (1 - alpha)
        )
    }

    /// The color as a CGColor in the sRGB space.
    ///
    /// The color space matters: `CGColor(red:green:blue:alpha:)` builds its color in
    /// Core Graphics' Generic RGB space, and the context then converts it to its own
    /// space on draw. That conversion shifts the channel values — brand blue
    /// #0A84FF came out as #009AFF — leaving the PNG a different blue from the hex
    /// in the SVGs and tailwind.config.js. Constructing in sRGB keeps the stored
    /// bytes equal to the hex.
    func cg(_ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: sRGBSpace, components: [r, g, b, alpha])
            ?? CGColor(red: r, green: g, blue: b, alpha: alpha)
    }

    var hex: String {
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(r), channel(g), channel(b))
    }

    /// Toward white by `t`.
    func lighten(_ t: CGFloat) -> RGB { mix(RGB(0xFFFFFF), t) }

    /// Toward black by `t`.
    func darken(_ t: CGFloat) -> RGB { mix(RGB(0x000000), t) }

    /// Linear blend toward `other` by `t`.
    func mix(_ other: RGB, _ t: CGFloat) -> RGB {
        RGB(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t
        )
    }

    func alpha(_ value: CGFloat) -> CGColor { cg(value) }
}

// Brand colors, matching public/assets/img/favicon.svg and tailwind.config.js.
let brandBlue = RGB(0x0A84FF)
let brandPurple = RGB(0xAF52DE)
let brandTeal = RGB(0x30B0C7)
let brandBlack = RGB(0x09090B)
let brandNearBlack = RGB(0x16181D)

enum Appearance: String, CaseIterable {
    case light
    case dark
    case tinted

    /// Filename suffix. The default appearance keeps the shortest name.
    var suffix: String { self == .light ? "" : "_\(rawValue)" }

    /// The `appearances` entry for Contents.json, empty for the default appearance.
    var appearanceKey: (String, String)? {
        switch self {
        case .light: return nil
        case .dark: return ("luminosity", "dark")
        case .tinted: return ("luminosity", "tinted")
        }
    }
}

/// The material recipe for one appearance.
///
/// Depth comes from one soft shadow and a faint top light, not from extra shapes
/// or detail, which is why the mark survives being scaled down to 20pt. These are
/// the approved shine settings: light field, three-card stack, white sparkle, no
/// glow, no rim.
struct Glass {
    let backgroundBottom: RGB
    let backgroundTop: RGB
    /// Radial glow behind the mark, and its alpha.
    let glow: RGB
    let glowAlpha: CGFloat
    let vignetteAlpha: CGFloat

    /// Card fills. The front card's three stops are bottom, middle, top, so the
    /// card's midpoint is exactly the brand color and the depth is symmetric.
    /// The middle card gets two stops; the back card's violet is sampled from the
    /// approved concept art, like the middle card's periwinkle.
    let backTop: RGB
    let backBottom: RGB
    let midTop: RGB
    let midBottom: RGB
    let frontTop: RGB
    let frontMid: RGB
    let frontBottom: RGB

    /// The site mark's check. The app icon draws a shine sparkle instead; see
    /// `sparkle`. Both stay on the struct because one script renders both marks.
    let check: RGB
    /// Dark stroke under the check, or nil when the check reads on its own.
    let checkHalo: RGB?
    let checkGlow: RGB
    let checkGlowAlpha: CGFloat

    /// Shine sparkle fill. White on the vivid stack; a dark knockout in tinted,
    /// where a white sparkle on a white card would be invisible.
    let sparkle: RGB

    let seam: RGB
    /// Color pooled under the cards, and its alpha.
    let ambient: RGB
    let ambientAlpha: CGFloat

    /// White for the light and dark appearances; the tinted appearance keeps light
    /// grays so its grayscale gradient still reads as a lit surface.
    let highlight: RGB
    /// The card's own inner top highlight.
    let topHighlight: CGFloat
    let leftHighlight: CGFloat
    let innerShadow: CGFloat

    /// Specular rim alphas: the outline runs the whole way round the card, and the
    /// top band is the brighter pass where light from overhead would catch. These are
    /// separate from `topHighlight` because the card's inner light and the rim read
    /// as two different materials, and driving both from one number forces one of
    /// them to be wrong.
    let rimAlpha: CGFloat
    let rimTopAlpha: CGFloat

    /// Specular rim width as a fraction of the canvas.
    let rimFraction: CGFloat
}

func glass(_ appearance: Appearance) -> Glass {
    switch appearance {
    case .light:
        return Glass(
            backgroundBottom: RGB(0xDCE2E9),
            backgroundTop: RGB(0xECEFF3),
            // No radial glow and no vignette. A clean field is the whole point of
            // the look: the stack separates from it by color alone.
            glow: brandBlue,
            glowAlpha: 0,
            vignetteAlpha: 0,
            // Concept-sampled violet: left/center/right thirds of the generated
            // art read blue, periwinkle, violet, and the stack keeps that order.
            backTop: RGB(0x9881FF),
            backBottom: RGB(0x6E54DE),
            midTop: RGB(0x7B93FF),
            midBottom: RGB(0x4E6BF0),
            // Flatter than the old glass look: a narrow spread symmetric around
            // brand blue, so the card reads as one lit surface.
            frontTop: RGB(0x2F9BFF),
            frontMid: RGB(0x0A84FF),
            frontBottom: RGB(0x0B6FD8),
            // The site mark's check. The app icon draws `sparkle` instead.
            check: RGB(0xFFFFFF),
            checkHalo: nil,
            checkGlow: RGB(0xFFFFFF),
            checkGlowAlpha: 0,
            sparkle: RGB(0xFFFFFF),
            // Unused by the app icon now (no seam is drawn); kept for the site mark.
            seam: RGB(0x0F1014),
            // One soft neutral shadow under the stack. This and the top light are
            // the only depth left.
            ambient: RGB(0x000000),
            ambientAlpha: 0.22,
            highlight: RGB(0xFFFFFF),
            topHighlight: 0.14,
            leftHighlight: 0,
            innerShadow: 0.08,
            // No specular rim. A rimmed card on a white field reads as a button, not
            // as an Apple icon.
            rimAlpha: 0,
            rimTopAlpha: 0,
            rimFraction: 0.0045
        )
    case .dark:
        // Near-black graphite so the icon sits flush on a dark home screen without
        // going full black, with the hues pulled 10% toward gray so they do not
        // bloom. Same three-card stack, same flat gradients as light.
        let blue = brandBlue.desaturated(0.10)
        let violet = RGB(0x9176FF).desaturated(0.10)
        let peri = RGB(0x6880FF).desaturated(0.10)
        return Glass(
            backgroundBottom: RGB(0x000000),
            backgroundTop: RGB(0x1D2026),
            glow: blue,
            glowAlpha: 0,
            vignetteAlpha: 0,
            backTop: violet.lighten(0.14),
            backBottom: violet.darken(0.20),
            midTop: peri.lighten(0.12),
            midBottom: peri.darken(0.18),
            frontTop: blue.lighten(0.18),
            frontMid: blue,
            frontBottom: blue.darken(0.20),
            check: RGB(0xFFFFFF),
            checkHalo: nil,
            checkGlow: RGB(0xFFFFFF),
            checkGlowAlpha: 0,
            sparkle: RGB(0xFFFFFF),
            seam: RGB(0x000000),
            ambient: RGB(0x000000),
            ambientAlpha: 0.5,
            highlight: RGB(0xFFFFFF),
            topHighlight: 0.14,
            leftHighlight: 0,
            innerShadow: 0.12,
            rimAlpha: 0,
            rimTopAlpha: 0,
            rimFraction: 0.0045
        )
    case .tinted:
        // iOS maps luminance to the user's tint color, so this appearance is built
        // from luminance alone. The gradients are pure grays: the tint mapping
        // preserves relative luminance, so the card still reads as a lit surface
        // rather than a white blob. The check is a dark knockout here, because a white
        // check on a white card would be invisible.
        return Glass(
            backgroundBottom: RGB(0x000000),
            backgroundTop: RGB(0x000000),
            glow: RGB(0xFFFFFF),
            glowAlpha: 0,
            vignetteAlpha: 0,
            backTop: RGB(0x6A6A6A),
            backBottom: RGB(0x3A3A3A),
            midTop: RGB(0x9A9A9A),
            midBottom: RGB(0x666666),
            frontTop: RGB(0xFFFFFF),
            frontMid: RGB(0xF2F2F2),
            frontBottom: RGB(0xD0D0D0),
            check: RGB(0x6E6E6E),
            checkHalo: nil,
            checkGlow: RGB(0x000000),
            checkGlowAlpha: 0,
            sparkle: RGB(0x6E6E6E),
            seam: RGB(0x000000),
            ambient: RGB(0x000000),
            ambientAlpha: 0.45,
            highlight: RGB(0xFFFFFF),
            topHighlight: 0.30,
            leftHighlight: 0,
            innerShadow: 0.10,
            rimAlpha: 0,
            rimTopAlpha: 0,
            rimFraction: 0.0045
        )
    }
}

/// Per-size damping of the glass layers.
///
/// This only affects sizes rendered directly, which in practice means the site's
/// 32px favicon. The shipped app icon is a single 1024, and iOS derives its small
/// sizes by downsampling that, so iOS never calls this. The check's outer glow is
/// the one layer worth dropping outright when rendering small: at 32px a 2.5x-wide
/// soft stroke stops reading as a glow and starts reading as haze around the check.
struct Detail {
    let topHighlight: CGFloat
    let leftHighlight: CGFloat
    let innerShadow: CGFloat
    let rim: CGFloat
    let checkGlow: CGFloat
    let background: CGFloat
}

func detail(for size: Int) -> Detail {
    if size >= 256 {
        return Detail(topHighlight: 1, leftHighlight: 1, innerShadow: 1, rim: 1, checkGlow: 1, background: 1)
    }
    if size >= 80 {
        return Detail(topHighlight: 0.85, leftHighlight: 0.8, innerShadow: 0.85, rim: 0.9, checkGlow: 0.7, background: 0.8)
    }
    return Detail(topHighlight: 0.6, leftHighlight: 0.5, innerShadow: 0.6, rim: 0.7, checkGlow: 0, background: 0.5)
}

// MARK: - Rendering

/// Every color in this file is sRGB, matching the hex values in favicon.svg and
/// tailwind.config.js. Rendering in this space (not DeviceRGB) is what keeps the
/// stored pixels equal to the brand hex.
let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
let colorSpace = sRGBSpace

func roundedPath(_ rect: CGRect, corner: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
}

/// Scales a rect in the mark's 0...1 space to `canvas` pixels. Keeping every rect
/// in unit space until this point is what stops a card being drawn at 0.6 pixels.
func pixels(_ rect: CGRect, canvas: CGFloat) -> CGRect {
    CGRect(
        x: rect.origin.x * canvas,
        y: rect.origin.y * canvas,
        width: rect.width * canvas,
        height: rect.height * canvas
    )
}

/// Clips to `path` and fills it with a vertical gradient from bottom to top.
func fillVerticalGradient(
    _ context: CGContext,
    path: CGPath,
    colors: [CGColor],
    locations: [CGFloat],
    rect: CGRect
) {
    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: colors as CFArray,
        locations: locations
    ) else { return }
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.minY),
        end: CGPoint(x: rect.midX, y: rect.maxY),
        options: []
    )
    context.restoreGState()
}

/// Clips to `path` and fills it with a vertical gradient over one band of the rect.
///
/// `alphaAt` and `fadeTo` are fractions of the rect's height measured from the
/// bottom. The color is at its given alpha at `alphaAt` and fully transparent at
/// `fadeTo`, so the order of the two arguments sets the direction: pass the higher
/// fraction first for a highlight that falls from the top edge, the lower first for
/// shading that rises from the bottom edge.
func fillBand(
    _ context: CGContext,
    path: CGPath,
    rect: CGRect,
    alphaAt: CGFloat,
    fadeTo: CGFloat,
    color: RGB,
    alpha: CGFloat
) {
    guard alpha > 0, let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color.cg(alpha), color.cg(0)] as CFArray,
        locations: [0, 1]
    ) else { return }
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.minY + rect.height * alphaAt),
        end: CGPoint(x: rect.midX, y: rect.minY + rect.height * fadeTo),
        options: []
    )
    context.restoreGState()
}

/// Lays a drop shadow under the next filled path.
func withShadow(
    _ context: CGContext,
    color: RGB,
    alpha: CGFloat,
    offsetY: CGFloat,
    blur: CGFloat,
    _ body: () -> Void
) {
    context.saveGState()
    if alpha > 0 {
        context.setShadow(
            offset: CGSize(width: 0, height: offsetY),
            blur: blur,
            color: color.cg(alpha)
        )
    }
    body()
    context.restoreGState()
}

func drawIcon(size: Int, appearance: Appearance) -> CGImage? {
    let material = glass(appearance)
    let level = detail(for: size)
    let canvas = CGFloat(size)

    // `noneSkipLast` yields a 3-channel RGB PNG with no alpha channel. The
    // marketing icon must be opaque or App Store validation rejects it.
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else { return nil }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Background. CGContext is y-up, so y = 0 (the bottom of the PNG) takes the
    // darker stop, matching logo.svg.
    let full = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    fillVerticalGradient(
        context,
        path: CGPath(rect: full, transform: nil),
        colors: [material.backgroundBottom.cg(), material.backgroundTop.cg()],
        locations: [0, 1],
        rect: full
    )

    // Glow pooled behind the mark from the lower left, then a vignette to keep the
    // corners from competing with the cards.
    if material.glowAlpha * level.background > 0,
       let glow = CGGradient(
           colorsSpace: colorSpace,
           colors: [material.glow.cg(material.glowAlpha * level.background), material.glow.cg(0)] as CFArray,
           locations: [0, 1]
       ) {
        let center = CGPoint(x: canvas * 0.46, y: canvas * 0.58)
        context.drawRadialGradient(
            glow,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: canvas * 0.62,
            options: []
        )
    }
    if material.vignetteAlpha * level.background > 0,
       let vignette = CGGradient(
           colorsSpace: colorSpace,
           colors: [RGB(0x000000).cg(0), RGB(0x000000).cg(material.vignetteAlpha * level.background)] as CFArray,
           locations: [0.55, 1]
       ) {
        let center = CGPoint(x: canvas / 2, y: canvas / 2)
        context.drawRadialGradient(
            vignette,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: canvas * 0.72,
            options: []
        )
    }

    let backRect = pixels(art.backRect, canvas: canvas)
    let midRect = pixels(art.midRect, canvas: canvas)
    let frontRect = pixels(art.frontRect, canvas: canvas)
    let corner = art.corner * canvas
    let rim = max(1.0, material.rimFraction * canvas)

    // One card fill: soft shadow, vertical gradient, inner bottom shade, inner top
    // light. The caller paints back to front so each card overlaps the last.
    func drawCard(_ rect: CGRect, colors: [CGColor], locations: [CGFloat]) {
        withShadow(
            context,
            color: material.ambient,
            alpha: material.ambientAlpha * level.background,
            offsetY: -0.018 * canvas,
            blur: 0.040 * canvas
        ) {
            context.addPath(roundedPath(rect, corner: corner))
            context.setFillColor(colors[colors.count / 2])
            context.fillPath()
        }
        fillVerticalGradient(
            context,
            path: roundedPath(rect, corner: corner),
            colors: colors,
            locations: locations,
            rect: rect
        )
        fillBand(
            context,
            path: roundedPath(rect, corner: corner),
            rect: rect,
            alphaAt: 0,
            fadeTo: 0.22,
            color: RGB(0x000000),
            alpha: material.innerShadow * level.innerShadow
        )
        fillBand(
            context,
            path: roundedPath(rect, corner: corner),
            rect: rect,
            alphaAt: 1.0,
            fadeTo: 0.66,
            color: material.highlight,
            alpha: material.topHighlight * level.topHighlight
        )
    }

    // MARK: back card
    drawCard(
        backRect,
        colors: [material.backBottom.cg(), material.backTop.cg()],
        locations: [0, 1]
    )

    // MARK: middle card
    if art.depth >= 3 {
        drawCard(
            midRect,
            colors: [material.midBottom.cg(), material.midTop.cg()],
            locations: [0, 1]
        )
    }

    // MARK: front card
    drawCard(
        frontRect,
        colors: [material.frontBottom.cg(), material.frontMid.cg(), material.frontTop.cg()],
        locations: [0, 0.5, 1]
    )

    // MARK: specular rim
    // Drawn clipped to the card interior so it sits inside the edge and cannot
    // bleed past the safe inset: a full outline first, then a brighter pass along
    // the top band and down the left side, where a real light source would catch.
    // No rim in the Apple-clean recipes (both alphas are 0): the extra condition
    // keeps the renderer from stroking an invisible path over the card edge.
    if level.rim > 0, material.rimAlpha + material.rimTopAlpha > 0 {
        let rimRect = frontRect.insetBy(dx: rim / 2, dy: rim / 2)
        let rimPath = roundedPath(rimRect, corner: max(0, corner - rim / 2))
        context.saveGState()
        context.addPath(roundedPath(frontRect, corner: corner))
        context.clip()
        context.addPath(rimPath)
        context.setStrokeColor(material.highlight.cg(material.rimAlpha * level.rim))
        context.setLineWidth(rim * 2)
        context.strokePath()
        context.saveGState()
        context.clip(to: CGRect(
            x: frontRect.minX,
            y: frontRect.maxY - frontRect.height * 0.16,
            width: frontRect.width,
            height: frontRect.height * 0.16
        ))
        context.addPath(rimPath)
        context.setStrokeColor(material.highlight.cg(material.rimTopAlpha * level.topHighlight))
        context.setLineWidth(rim * 2)
        context.strokePath()
        context.restoreGState()
        if material.leftHighlight * level.leftHighlight > 0 {
            context.saveGState()
            context.clip(to: CGRect(
                x: frontRect.minX,
                y: frontRect.minY,
                width: frontRect.width * 0.10,
                height: frontRect.height
            ))
            context.addPath(rimPath)
            context.setStrokeColor(material.highlight.cg(material.leftHighlight * level.leftHighlight))
            context.setLineWidth(rim * 2)
            context.strokePath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    // MARK: shine sparkle
    // A four-point star polygon: outer points at 0/90/180/270, waist pinched to
    // 0.20 of the radius at the diagonals. A polygon, not curves, so the points
    // stay sharp at 20pt instead of melting into a blob.
    func starPath(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<8 {
            let angle = CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 4
            let r = i % 2 == 0 ? radius : radius * 0.20
            let point = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
    if art.sparkleRadius > 0 {
        let c = CGPoint(x: art.sparkleCenter.x * canvas, y: art.sparkleCenter.y * canvas)
        context.addPath(starPath(center: c, radius: art.sparkleRadius * canvas))
        context.setFillColor(material.sparkle.cg())
        context.fillPath()
    }
    if art.satelliteRadius > 0 {
        let c = CGPoint(x: art.satelliteCenter.x * canvas, y: art.satelliteCenter.y * canvas)
        context.addPath(starPath(center: c, radius: art.satelliteRadius * canvas))
        context.setFillColor(material.sparkle.cg())
        context.fillPath()
    }

    // MARK: checkmark
    // The site mark's check. Check and sparkle are alternatives: art with a shine
    // radius draws the shine above instead of this.
    if art.sparkleRadius == 0 {
        let check = CGMutablePath()
    for (index, local) in art.checkPathLocal.enumerated() {
        let point = art.checkPoint(local)
        let scaled = CGPoint(x: point.x * canvas, y: point.y * canvas)
        if index == 0 {
            check.move(to: scaled)
        } else {
            check.addLine(to: scaled)
        }
    }
    let stroke = art.checkStroke * canvas
    let glowAlpha = material.checkGlowAlpha * level.checkGlow
    if glowAlpha > 0 {
        context.addPath(check)
        context.setStrokeColor(material.checkGlow.cg(glowAlpha))
        context.setLineWidth(stroke * 2.5)
        context.strokePath()
    }
    if let halo = material.checkHalo {
        context.addPath(check)
        context.setStrokeColor(halo.cg())
        context.setLineWidth(stroke * art.checkHaloMultiplier)
        context.strokePath()
    }
    context.addPath(check)
    context.setStrokeColor(material.check.cg())
    context.setLineWidth(stroke)
    context.strokePath()
    }

    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw ScriptError("cannot create image destination at \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScriptError("cannot write \(url.path)")
    }
}

// MARK: - Asset catalog

let appIconDir = "Tidybyte/Resources/Assets.xcassets/AppIcon.appiconset"
let siteImageDir = "public/assets/img"

/// The single size the catalog ships. Xcode derives 20pt through 83.5pt from it,
/// for iPhone and iPad both.
let iconFilename = "icon_1024"
let iconPixels = 1024

/// Xcode's single-size format. `platform: ios` with `idiom: universal` is what
/// makes the `appearances` keys take effect.
func contentsJSON() -> String {
    var entries: [String] = []
    for appearance in Appearance.allCases {
        var fields: [String] = []
        if let key = appearance.appearanceKey {
            fields.append("""
                  "appearances" : [
                    {
                      "appearance" : "\(key.0)",
                      "value" : "\(key.1)"
                    }
                  ]
            """)
        }
        fields.append("      \"filename\" : \"\(iconFilename)\(appearance.suffix).png\"")
        fields.append("      \"idiom\" : \"universal\"")
        fields.append("      \"platform\" : \"ios\"")
        fields.append("      \"size\" : \"1024x1024\"")
        entries.append("    {\n" + fields.joined(separator: ",\n") + "\n    }")
    }
    return """
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
}

// MARK: - SVG output

/// Trims a CGFloat to at most 5 decimals with no trailing zeros.
func fmt(_ value: CGFloat) -> String {
    var text = String(format: "%.5f", Double(value))
    while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
        text.removeLast()
    }
    return text
}

/// Emits the mark as an SVG group, flipped so unit-space y-up matches SVG's
/// y-down. This reads `siteArt`, not `art`: the site keeps the geometry it was drawn
/// with, so regenerating it does not restyle the page behind everyone's back.
///
/// The gradient directions read inverted on purpose. The group carries a y-flip, so
/// a gradient running from local y=0 to y=1 renders bottom-to-top on screen, which
/// is why offset 0% is the darker stop in every fill here.
///
/// The specular rim and the ambient shadow are deliberately not emitted: at favicon
/// size a 1px highlight is invisible, and a blurred shadow would need an SVG filter
/// that costs more bytes than it returns. The card gradients, background glow and
/// check glow carry the depth at these sizes.
func svgGlyphMarkup(centerX: CGFloat, centerY: CGFloat, scale: CGFloat, idPrefix: String, background: (id: String, top: String, bottom: String)) -> String {
    let material = glass(.light)
    let front = siteArt.frontRect
    let back = siteArt.backRect
    let seamRect = front.insetBy(dx: siteArt.seam / 2, dy: siteArt.seam / 2)
    let checkPath = "M" + siteArt.checkPathLocal
        .map(siteArt.checkPoint)
        .map { "\(fmt($0.x)) \(fmt($0.y))" }
        .joined(separator: " L")

    // The inner top highlight is a band across the top third of the front card.
    let highlightRect = CGRect(
        x: front.minX,
        y: front.maxY - front.height * 0.34,
        width: front.width,
        height: front.height * 0.34
    )
    let glowCenter = CGPoint(x: 0.46, y: 0.58)

    // Only the layers the current material actually draws are emitted, so a
    // zero-alpha glow does not ship as dead markup.
    var defs: [String] = []
    defs.append("    <linearGradient id=\"\(background.id)\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">")
    defs.append("      <stop offset=\"0%\" stop-color=\"\(background.top)\"/>")
    defs.append("      <stop offset=\"100%\" stop-color=\"\(background.bottom)\"/>")
    defs.append("    </linearGradient>")
    defs.append("    <linearGradient id=\"\(idPrefix)-back\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">")
    defs.append("      <stop offset=\"0%\" stop-color=\"\(material.backBottom.hex)\"/>")
    defs.append("      <stop offset=\"100%\" stop-color=\"\(material.backTop.hex)\"/>")
    defs.append("    </linearGradient>")
    defs.append("    <linearGradient id=\"\(idPrefix)-front\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">")
    defs.append("      <stop offset=\"0%\" stop-color=\"\(material.frontBottom.hex)\"/>")
    defs.append("      <stop offset=\"50%\" stop-color=\"\(material.frontMid.hex)\"/>")
    defs.append("      <stop offset=\"100%\" stop-color=\"\(material.frontTop.hex)\"/>")
    defs.append("    </linearGradient>")
    defs.append("    <linearGradient id=\"\(idPrefix)-highlight\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">")
    defs.append("      <stop offset=\"0%\" stop-color=\"#FFFFFF\" stop-opacity=\"0\"/>")
    defs.append("      <stop offset=\"100%\" stop-color=\"#FFFFFF\" stop-opacity=\"\(fmt(material.topHighlight))\"/>")
    defs.append("    </linearGradient>")
    if material.glowAlpha > 0 {
        defs.append("    <radialGradient id=\"\(idPrefix)-glow\">")
        defs.append("      <stop offset=\"0%\" stop-color=\"\(material.glow.hex)\" stop-opacity=\"\(fmt(material.glowAlpha))\"/>")
        defs.append("      <stop offset=\"100%\" stop-color=\"\(material.glow.hex)\" stop-opacity=\"0\"/>")
        defs.append("    </radialGradient>")
    }
    defs.append("    <clipPath id=\"\(idPrefix)-front-clip\">")
    defs.append("      <rect x=\"\(fmt(front.minX))\" y=\"\(fmt(front.minY))\" width=\"\(fmt(front.width))\" height=\"\(fmt(front.height))\" rx=\"\(fmt(siteArt.corner))\"/>")
    defs.append("    </clipPath>")

    var lines: [String] = []
    lines.append("  <defs>")
    lines.append(contentsOf: defs)
    lines.append("  </defs>")

    let transform = "translate(\(fmt(centerX)),\(fmt(centerY))) scale(\(fmt(scale)),-\(fmt(scale))) translate(-0.5,-0.5)"
    lines.append("  <g transform=\"\(transform)\">")
    if material.glowAlpha > 0 {
        lines.append("    <circle cx=\"\(fmt(glowCenter.x))\" cy=\"\(fmt(glowCenter.y))\" r=\"0.62\" fill=\"url(#\(idPrefix)-glow)\"/>")
    }
    lines.append("    <rect x=\"\(fmt(back.minX))\" y=\"\(fmt(back.minY))\" width=\"\(fmt(back.width))\" height=\"\(fmt(back.height))\" rx=\"\(fmt(siteArt.corner))\" fill=\"url(#\(idPrefix)-back)\"/>")
    lines.append("    <rect x=\"\(fmt(front.minX))\" y=\"\(fmt(front.minY))\" width=\"\(fmt(front.width))\" height=\"\(fmt(front.height))\" rx=\"\(fmt(siteArt.corner))\" fill=\"url(#\(idPrefix)-front)\"/>")
    lines.append("    <g clip-path=\"url(#\(idPrefix)-front-clip)\">")
    lines.append("      <rect x=\"\(fmt(highlightRect.minX))\" y=\"\(fmt(highlightRect.minY))\" width=\"\(fmt(highlightRect.width))\" height=\"\(fmt(highlightRect.height))\" fill=\"url(#\(idPrefix)-highlight)\"/>")
    lines.append("    </g>")
    lines.append("    <rect x=\"\(fmt(seamRect.origin.x))\" y=\"\(fmt(seamRect.origin.y))\" width=\"\(fmt(seamRect.width))\" height=\"\(fmt(seamRect.height))\" rx=\"\(fmt(max(0, siteArt.corner - siteArt.seam / 2)))\" fill=\"none\" stroke=\"\(material.seam.hex)\" stroke-width=\"\(fmt(siteArt.seam))\"/>")
    if material.checkGlowAlpha > 0 {
        lines.append("    <path d=\"\(checkPath)\" fill=\"none\" stroke=\"\(material.checkGlow.hex)\" stroke-opacity=\"\(fmt(material.checkGlowAlpha))\" stroke-width=\"\(fmt(siteArt.checkStroke * 2.5))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
    }
    if let halo = material.checkHalo {
        lines.append("    <path d=\"\(checkPath)\" fill=\"none\" stroke=\"\(halo.hex)\" stroke-width=\"\(fmt(siteArt.checkStroke * siteArt.checkHaloMultiplier))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
    }
    lines.append("    <path d=\"\(checkPath)\" fill=\"none\" stroke=\"\(material.check.hex)\" stroke-width=\"\(fmt(siteArt.checkStroke))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
    lines.append("  </g>")
    return lines.joined(separator: "\n")
}

func logoSVG() -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="TidyByte">
      <rect width="512" height="512" fill="url(#tb-logo-bg)"/>
    \(svgGlyphMarkup(centerX: 256, centerY: 190, scale: 200, idPrefix: "tb-logo-mark",
                     background: (id: "tb-logo-bg", top: "#16181D", bottom: "#09090B")))
      <text x="256" y="382" text-anchor="middle" font-family="-apple-system, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif" font-size="52" font-weight="600" fill="#F4F4F5">TidyByte</text>
    </svg>

    """
}

func faviconSVG() -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64" role="img" aria-label="TidyByte">
      <rect width="64" height="64" rx="14" fill="url(#tb-favicon-bg)"/>
    \(svgGlyphMarkup(centerX: 32, centerY: 32, scale: 44, idPrefix: "tb-fav-mark",
                     background: (id: "tb-favicon-bg", top: "#16181D", bottom: "#09090B")))
    </svg>

    """
}

// MARK: - Icon Composer layers

/// Emits the mark as the layered, fully opaque SVG files Icon Composer imports.
///
/// `AppIcon.icon` cannot be authored here: the format is undocumented, Xcode 26
/// ships no template for it, the Icon Composer framework will not load outside the
/// app (it traps), and actool answers an incomplete document with an internal
/// exception rather than naming the missing keys, so there is no diagnostic loop to
/// converge against. Icon Composer is the only tool that writes the format, so this
/// is the furthest the pipeline can go: the layers it wants you to import.
///
/// Three layers, bottom to top. Each is a full-canvas SVG at the same viewBox, so
/// they stack without any offset bookkeeping in Icon Composer.
func iconComposerLayers() -> [(name: String, svg: String)] {
    let material = glass(.light)
    let front = art.frontRect
    let mid = art.midRect
    let back = art.backRect
    let highlightRect = CGRect(
        x: front.minX,
        y: front.maxY - front.height * 0.34,
        width: front.width,
        height: front.height * 0.34
    )
    // Four-point star polygon in unit space, mirroring the renderer's starPath.
    func starPoints(center: CGPoint, radius: CGFloat) -> String {
        (0..<8).map { i in
            let angle = CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 4
            let r = i % 2 == 0 ? radius : radius * 0.20
            return "\(fmt(center.x + r * cos(angle))) \(fmt(center.y + r * sin(angle)))"
        }.joined(separator: " ")
    }

    // The same mapping the site mark uses: unit space (y-up, centred on 0.5) onto
    // the canvas, with the negative Y scale supplying SVG's top-left origin. Stops
    // inside that space therefore run bottom (0%) to top (100%). Emitting unit
    // coordinates straight into a 1024 viewBox draws the whole mark as one
    // sub-pixel dot in the corner.
    let transform = "translate(512,512) scale(1024,-1024) translate(-0.5,-0.5)"

    func document(defs: [String], body: [String]) -> String {
        var lines = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">",
            "  <defs>",
        ]
        lines += defs.map { "    " + $0 }
        lines.append("  </defs>")
        lines.append("  <g transform=\"\(transform)\">")
        lines += body.map { "    " + $0 }
        lines.append("  </g>")
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    // Layer 1: background gradient and its glow. Opacity-free, so Icon Composer
    // treats it as the back plane.
    let background = document(
        defs: [
            "<linearGradient id=\"tb-bg\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">",
            "  <stop offset=\"0%\" stop-color=\"\(material.backgroundBottom.hex)\"/>",
            "  <stop offset=\"100%\" stop-color=\"\(material.backgroundTop.hex)\"/>",
            "</linearGradient>",
            "<radialGradient id=\"tb-glow\" cx=\"0.46\" cy=\"0.58\" r=\"0.62\">",
            "  <stop offset=\"0%\" stop-color=\"\(material.glow.hex)\" stop-opacity=\"\(fmt(material.glowAlpha))\"/>",
            "  <stop offset=\"100%\" stop-color=\"\(material.glow.hex)\" stop-opacity=\"0\"/>",
            "</radialGradient>",
        ],
        body: [
            "<rect x=\"0\" y=\"0\" width=\"1\" height=\"1\" fill=\"url(#tb-bg)\"/>",
            "<rect x=\"0\" y=\"0\" width=\"1\" height=\"1\" fill=\"url(#tb-glow)\"/>",
        ]
    )

    // Layer 2: the stack — back, middle, and front cards, their gradients, and
    // the front card's inner light.
    let cards = document(
        defs: [
            "<linearGradient id=\"tb-back\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">",
            "  <stop offset=\"0%\" stop-color=\"\(material.backBottom.hex)\"/>",
            "  <stop offset=\"100%\" stop-color=\"\(material.backTop.hex)\"/>",
            "</linearGradient>",
            "<linearGradient id=\"tb-mid\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">",
            "  <stop offset=\"0%\" stop-color=\"\(material.midBottom.hex)\"/>",
            "  <stop offset=\"100%\" stop-color=\"\(material.midTop.hex)\"/>",
            "</linearGradient>",
            "<linearGradient id=\"tb-front\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">",
            "  <stop offset=\"0%\" stop-color=\"\(material.frontBottom.hex)\"/>",
            "  <stop offset=\"50%\" stop-color=\"\(material.frontMid.hex)\"/>",
            "  <stop offset=\"100%\" stop-color=\"\(material.frontTop.hex)\"/>",
            "</linearGradient>",
            "<linearGradient id=\"tb-highlight\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">",
            "  <stop offset=\"0%\" stop-color=\"#FFFFFF\" stop-opacity=\"0\"/>",
            "  <stop offset=\"100%\" stop-color=\"#FFFFFF\" stop-opacity=\"\(fmt(material.topHighlight))\"/>",
            "</linearGradient>",
            "<clipPath id=\"tb-front-clip\">",
            "  <rect x=\"\(fmt(front.minX))\" y=\"\(fmt(front.minY))\" width=\"\(fmt(front.width))\" height=\"\(fmt(front.height))\" rx=\"\(fmt(art.corner))\"/>",
            "</clipPath>",
        ],
        body: [
            "<rect x=\"\(fmt(back.minX))\" y=\"\(fmt(back.minY))\" width=\"\(fmt(back.width))\" height=\"\(fmt(back.height))\" rx=\"\(fmt(art.corner))\" fill=\"url(#tb-back)\"/>",
            "<rect x=\"\(fmt(mid.minX))\" y=\"\(fmt(mid.minY))\" width=\"\(fmt(mid.width))\" height=\"\(fmt(mid.height))\" rx=\"\(fmt(art.corner))\" fill=\"url(#tb-mid)\"/>",
            "<rect x=\"\(fmt(front.minX))\" y=\"\(fmt(front.minY))\" width=\"\(fmt(front.width))\" height=\"\(fmt(front.height))\" rx=\"\(fmt(art.corner))\" fill=\"url(#tb-front)\"/>",
            "<g clip-path=\"url(#tb-front-clip)\">",
            "  <rect x=\"\(fmt(highlightRect.minX))\" y=\"\(fmt(highlightRect.minY))\" width=\"\(fmt(highlightRect.width))\" height=\"\(fmt(highlightRect.height))\" fill=\"url(#tb-highlight)\"/>",
            "</g>",
        ]
    )

    // Layer 3: the shine alone, as opaque polygons.
    let shine = document(
        defs: [],
        body: [
            "<polygon points=\"\(starPoints(center: art.sparkleCenter, radius: art.sparkleRadius))\" fill=\"\(material.sparkle.hex)\"/>",
            "<polygon points=\"\(starPoints(center: art.satelliteCenter, radius: art.satelliteRadius))\" fill=\"\(material.sparkle.hex)\"/>",
        ]
    )

    return [("01-background", background), ("02-cards", cards), ("03-shine", shine)]
}

// MARK: - Modes

struct ScriptError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Fails if the art would bleed outside the safe inset.
func verifyInsets() throws {
    let bounds = art.contentBounds
    guard bounds.minX >= art.inset - 1e-6,
          bounds.minY >= art.inset - 1e-6,
          bounds.maxX <= 1 - art.inset + 1e-6,
          bounds.maxY <= 1 - art.inset + 1e-6 else {
        throw ScriptError(String(
            format: "inset violation: content bounds %@ escape the %.0f%% inset",
            NSStringFromRect(bounds),
            art.inset * 100
        ))
    }
    print("inset check: content stays inside the \(Int(art.inset * 100))% safe inset")
}

func iconURL(_ appearance: Appearance) -> URL {
    URL(fileURLWithPath: appIconDir)
        .appendingPathComponent("\(iconFilename)\(appearance.suffix).png")
}

func runGenerate(syncSite: Bool) throws {
    let directory = URL(fileURLWithPath: appIconDir)
    guard FileManager.default.fileExists(atPath: directory.path) else {
        throw ScriptError("run this from the repository root: \(appIconDir) not found")
    }

    try verifyInsets()

    for appearance in Appearance.allCases {
        guard let image = drawIcon(size: iconPixels, appearance: appearance) else {
            throw ScriptError("render failed for the \(appearance.rawValue) icon")
        }
        try writePNG(image, to: iconURL(appearance))
        print("wrote \(iconFilename)\(appearance.suffix).png (\(iconPixels)px, \(appearance.rawValue))")
    }

    try contentsJSON().write(
        to: directory.appendingPathComponent("Contents.json"),
        atomically: true,
        encoding: .utf8
    )
    print("wrote Contents.json (\(Appearance.allCases.count) entries)")

    if syncSite { try syncSiteAssets() }
}

/// Refreshes the site copies so the app and website cannot drift apart.
func syncSiteAssets() throws {
    let directory = URL(fileURLWithPath: siteImageDir)
    guard FileManager.default.fileExists(atPath: directory.path) else {
        throw ScriptError("\(siteImageDir) not found")
    }

    // 1024 for the OG image and JSON-LD logo, 180 for the touch icon, 32 for the tab.
    for (name, pixels) in [("icon-1024.png", 1024), ("apple-touch-icon.png", 180), ("favicon-32.png", 32)] {
        guard let image = drawIcon(size: pixels, appearance: .light) else {
            throw ScriptError("render failed for site asset \(name)")
        }
        try writePNG(image, to: directory.appendingPathComponent(name))
        print("synced \(siteImageDir)/\(name) (\(pixels)px)")
    }

    for (name, markup) in [("logo.svg", logoSVG()), ("favicon.svg", faviconSVG())] {
        try markup.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        print("synced \(siteImageDir)/\(name)")
    }
}

// MARK: - Small-size legibility

/// What a downsampled icon has to keep, measured on the shipped 1024.
///
/// The app ships one 1024 and iOS derives every smaller size from it, so "does this
/// hold up at 20pt" is a question about the downsample, not about art drawn small.
/// Each number guards a different failure:
///
///   * `cardPixels40` — the blue-to-violet stack must survive at 40px as a vivid
///     footprint, or the stack has lost its color (recolored, flattened into the
///     field, or gone).
///   * `shinePixels40` — the white shine must stay visible at 40px. The failure
///     here is the sparkle shrinking into the cards or vanishing; a ceiling
///     catches the opposite mistake, a shine grown so large it floods the stack.
///     Measured at 40px, not 20px: the sparkle is a single pixel at 20px, and
///     downsample bleed swallows a 2x shrink or growth there.
///   * `frontContrast120` — mean brightness near the front card's top edge minus
///     near its bottom edge, at 120px. This is the depth signal: if the card ever
///     flattens back to a single fill, this collapses toward zero.
///
/// The contrast metric samples near the card's edges rather than averaging the whole
/// card, because averaging mixes in the shine and the card edges. It samples at
/// 120px rather than 20px because a card gradient is a large-scale feature that
/// survives downsampling, while the shine is what needs the small size.
struct Legibility {
    let cardPixels40: Int
    let shinePixels40: Int
    let frontContrast120: Double
}

/// Recorded from the approved shine render. See `--measure-legibility`.
/// Re-baselined after the redesign: three-card stack on a light field, shine
/// metric in place of the old check metric.
let baselineLegibility = Legibility(
    cardPixels40: 686,
    shinePixels40: 5,
    frontContrast120: 10.9
)

/// Tolerances, each one-sided for the failure it guards.
///
/// Calibrated by deliberately breaking the art and running --check on the result:
///
///   * stack recolored light gray: 686 -> 0.   Floor at 0.90 of baseline.
///   * sparkle halved or removed: 5 -> 2.      Floor at 0.70 of baseline. The
///     residual 2 is highlight-softened card pixels, not shine; the bar sits
///     between 2 and 5.
///   * sparkle grown 1.8x: 5 -> 27.            Ceiling at 1.50 of baseline.
///   * front gradient flattened: 10.9 -> 0.0.  Floor at 0.75 of baseline.
///
/// What it does not catch: dropping a card's inner highlight and inner shadow
/// while keeping its gradient still measures near baseline, because the sampled
/// strip of the card only ever shows the gradient. That is a milder regression
/// than a flat card, and catching it would need a second metric aimed at the
/// highlight band.
struct LegibilityTolerances {
    let cardFloor: Double = 0.90
    let shineFloor: Double = 0.70
    let shineCeiling: Double = 1.50
    let contrastFloor: Double = 0.75
}

/// Rasterizes `image` at `size` and returns its RGBA bytes, so the analysis below
/// reads a buffer whose layout this code owns rather than a CGImage's.
func pixelBuffer(_ image: CGImage, size: Int) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let context = CGContext(
            data: raw.baseAddress,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return false }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return true
    }
    return ok ? bytes : nil
}

/// Hue in degrees plus saturation and value, both 0...1.
func hsv(_ r: Double, _ g: Double, _ b: Double) -> (hue: Double, sat: Double, val: Double) {
    let maxC = max(r, g, b), minC = min(r, g, b)
    let delta = maxC - minC
    var hue = 0.0
    if delta > 0 {
        if maxC == r { hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
        else if maxC == g { hue = 60 * (((b - r) / delta) + 2) }
        else { hue = 60 * (((r - g) / delta) + 4) }
    }
    if hue < 0 { hue += 360 }
    return (hue, maxC == 0 ? 0 : delta / maxC, maxC)
}

/// Mean brightness of a band of the buffer, in 0...255 per channel.
///
/// Coordinates are fractions of the canvas measured from the top, matching how the
/// PNG rows are laid out, and x is kept left of 0.34 to stay clear of the check.
func meanBrightness(_ buffer: [UInt8], size: Int, xRange: ClosedRange<Double>, yRange: ClosedRange<Double>) -> Double {
    var total = 0.0
    var count = 0
    let y0 = Int(yRange.lowerBound * Double(size)), y1 = Int(yRange.upperBound * Double(size))
    let x0 = Int(xRange.lowerBound * Double(size)), x1 = Int(xRange.upperBound * Double(size))
    for y in max(0, y0)..<min(size, y1) {
        for x in max(0, x0)..<min(size, x1) {
            let index = (y * size + x) * 4
            total += (Double(buffer[index]) + Double(buffer[index + 1]) + Double(buffer[index + 2])) / 3
            count += 1
        }
    }
    return count > 0 ? total / Double(count) : 0
}

/// Classifies the icon's signature colors by hue, which stays stable as the card
/// gradients brighten or darken. Fixed RGB ranges do not: an earlier version of this
/// check used them and reported a false regression the moment the back card's
/// gradient got lighter.
func legibility(of image: CGImage) -> Legibility? {
    guard let big = pixelBuffer(image, size: 40),
          let shineBuf = pixelBuffer(image, size: 40),
          let contrast = pixelBuffer(image, size: 120) else { return nil }

    // The stack runs brand blue (~211°) through periwinkle (~230°) to violet
    // (~252°). The light field is near-white, so it falls out on saturation alone;
    // nothing else vivid shares the canvas.
    var card = 0
    for index in stride(from: 0, to: big.count, by: 4) {
        let r = Double(big[index]) / 255, g = Double(big[index + 1]) / 255, b = Double(big[index + 2]) / 255
        let (hue, sat, val) = hsv(r, g, b)
        if hue >= 195, hue <= 275, sat > 0.25, val > 0.30 { card += 1 }
    }

    // The shine is white on vivid cards, found as bright near-neutral pixels
    // scanned only inside the box it can occupy. The box sits on the back card on
    // every side: the field is near-white too, so it would count as shine if the
    // box ever touched it. The value bar is deliberately core-white (0.90) and the
    // saturation bar tight (0.30): the anti-aliased skirt would otherwise count,
    // and the middle card's top highlight softens its periwinkle to sat ~0.4
    // inside this box, which would read as shine that is not there.
    var shine = 0
    let shineSide = 40
    for y in Int(0.20 * Double(shineSide))...Int(0.42 * Double(shineSide)) {
        for x in Int(0.60 * Double(shineSide))...Int(0.84 * Double(shineSide)) {
            let index = (y * shineSide + x) * 4
            let r = Double(shineBuf[index]) / 255, g = Double(shineBuf[index + 1]) / 255, b = Double(shineBuf[index + 2]) / 255
            let (_, sat, val) = hsv(r, g, b)
            if sat < 0.30, val > 0.90 { shine += 1 }
        }
    }

    // Both bands sit in the strip of the front card that only the gradient paints.
    // The front card spans 0.30 to 0.85 from the top, but its top 34% carries the
    // inner highlight and its bottom 22% carries the inner shadow, and those two
    // hold the reading up even when the gradient is gone. Between 0.52 and 0.70
    // only the gradient varies.
    //
    // The x band is narrow and just inside the front card's left edge: the shine
    // starts at about x 0.64, so sampling further right would fold the sparkle into
    // the card's brightness reading and report a contrast change when only the
    // shine had moved.
    let xBand: ClosedRange<Double> = 0.20...0.26
    let top = meanBrightness(contrast, size: 120, xRange: xBand, yRange: 0.52...0.55)
    let bottom = meanBrightness(contrast, size: 120, xRange: xBand, yRange: 0.67...0.70)

    return Legibility(cardPixels40: card, shinePixels40: shine, frontContrast120: top - bottom)
}

func runCheck() throws {
    var failures: [String] = []

    try verifyInsets()

    // Every filename Contents.json references must exist, at the right size.
    for appearance in Appearance.allCases {
        let url = iconURL(appearance)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            failures.append("missing or unreadable \(iconFilename)\(appearance.suffix).png")
            continue
        }
        if image.width != iconPixels || image.height != iconPixels {
            failures.append("\(iconFilename)\(appearance.suffix).png is \(image.width)x\(image.height), expected \(iconPixels)")
        }
        // Light and dark must be opaque. Tinted is included anyway, since nothing
        // in this art needs transparency.
        if image.alphaInfo != .none && image.alphaInfo != .noneSkipLast {
            failures.append("\(iconFilename)\(appearance.suffix).png carries an alpha channel (alphaInfo \(image.alphaInfo.rawValue))")
        }
    }
    if failures.isEmpty {
        print("files: all \(Appearance.allCases.count) icons present, \(iconPixels)px, opaque")
    }

    // The catalog must keep the dark and tinted entries, or iOS silently falls
    // back to the light icon and the appearance variants stop working.
    let contents = (try? String(contentsOf: URL(fileURLWithPath: appIconDir).appendingPathComponent("Contents.json"), encoding: .utf8)) ?? ""
    for appearance in Appearance.allCases {
        guard let key = appearance.appearanceKey else { continue }
        if !contents.contains("\"value\" : \"\(key.1)\"") {
            failures.append("Contents.json is missing the \(key.1) appearance entry")
        }
    }
    if failures.isEmpty { print("catalog: light, dark, and tinted entries present") }

    // Small-size legibility, measured on the downsampled 1024 because that is what
    // iOS actually renders on the home screen at 20pt through 120pt.
    if let light = CGImageSourceCreateWithURL(iconURL(.light) as CFURL, nil),
       let image = CGImageSourceCreateImageAtIndex(light, 0, nil),
       let measured = legibility(of: image) {
        let base = baselineLegibility
        let tol = LegibilityTolerances()
        let cardFloor = Double(base.cardPixels40) * tol.cardFloor
        let shineFloor = Double(base.shinePixels40) * tol.shineFloor
        let shineCeiling = Double(base.shinePixels40) * tol.shineCeiling
        let contrastFloor = base.frontContrast120 * tol.contrastFloor

        if Double(measured.cardPixels40) < cardFloor {
            failures.append(String(
                format: "stack is down to %d px at 40px (floor %.0f): the cards are being lost",
                measured.cardPixels40, cardFloor
            ))
        }
        if Double(measured.shinePixels40) < shineFloor {
            failures.append(String(
                format: "shine is down to %d px at 40px (floor %.0f): the sparkle is disappearing at small sizes",
                measured.shinePixels40, shineFloor
            ))
        }
        if Double(measured.shinePixels40) > shineCeiling {
            failures.append(String(
                format: "shine covers %d px at 40px (ceiling %.0f): the sparkle is flooding the stack",
                measured.shinePixels40, shineCeiling
            ))
        }
        if measured.frontContrast120 < contrastFloor {
            failures.append(String(
                format: "card contrast is %.1f at 120px (floor %.1f): the card has flattened and lost its depth",
                measured.frontContrast120, contrastFloor
            ))
        }
        if failures.isEmpty {
            print(String(
                format: "legibility: 40px stack %d px, 40px shine %d px, 120px card contrast %.1f",
                measured.cardPixels40, measured.shinePixels40, measured.frontContrast120
            ))
        }
    } else {
        failures.append("could not measure small-size legibility")
    }

    if !failures.isEmpty {
        for failure in failures { print("FAIL \(failure)") }
        throw ScriptError("\(failures.count) check failure(s)")
    }
    print("check passed")
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    if arguments.contains("--icon-composer-layers") {
        let index = arguments.firstIndex(of: "--icon-composer-layers")
        let directory = index.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? "build/icon-composer"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for layer in iconComposerLayers() {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(layer.name).svg")
            try layer.svg.write(to: url, atomically: true, encoding: .utf8)
            print("wrote \(directory)/\(layer.name).svg")
        }
    } else if arguments.contains("--measure-legibility") {
        for appearance in Appearance.allCases {
            guard let source = CGImageSourceCreateWithURL(iconURL(appearance) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let measured = legibility(of: image) else {
                throw ScriptError("cannot measure the \(appearance.rawValue) icon")
            }
            print("\(appearance.rawValue): stack40=\(measured.cardPixels40) shine40=\(measured.shinePixels40) contrast120=\(String(format: "%.1f", measured.frontContrast120))")
        }
    } else if arguments.contains("--check") {
        try runCheck()
    } else {
        try runGenerate(syncSite: arguments.contains("--sync-site"))
        print("done")
    }
} catch let error as ScriptError {
    FileHandle.standardError.write("error: \(error.description)\n".data(using: .utf8)!)
    exit(1)
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
