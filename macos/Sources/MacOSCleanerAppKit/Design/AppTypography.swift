import SwiftUI

/// Native text styles; monospaced text is reserved for paths and commands.
public enum AppFont: Sendable {
    case display, h3, h4, bodyMedium, labelMedium, caption, filePath

    public func font() -> Font {
        switch self {
        case .display: return .largeTitle.weight(.semibold)
        case .h3: return .headline
        case .h4: return .subheadline.weight(.semibold)
        case .bodyMedium: return .body
        case .labelMedium: return .callout
        case .caption: return .caption
        case .filePath: return .system(.caption, design: .monospaced)
        }
    }
}

extension Font {
    public static func app(_ style: AppFont) -> Font { style.font() }
}

extension View {
    public func appFont(_ style: AppFont) -> some View { font(style.font()) }
    public func appFont(_ style: AppFont, color: Color) -> some View { font(style.font()).foregroundStyle(color) }
}
