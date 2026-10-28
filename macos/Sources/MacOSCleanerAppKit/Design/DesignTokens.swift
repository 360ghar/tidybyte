import SwiftUI
import MacOSCleanerCore

// Colors are semantic system colors; they adapt to appearance and Increase Contrast.

public enum Primary {
    public static let primary = Color.accentColor
    public static let selection = Color.accentColor.opacity(0.12)
    public static let label = Color.primary
}

public enum SemanticScale {
    public static let success = Color(nsColor: .systemGreen)
    public static let error = Color(nsColor: .systemRed)
    public static let warning = Color(nsColor: .systemOrange)
    public static let successSoft = success.opacity(0.12)
    public static let errorSoft = error.opacity(0.12)
    public static let warningSoft = warning.opacity(0.12)
}

public enum RiskScale {
    public static let low = SemanticScale.success
    public static let medium = SemanticScale.warning
    public static let high = SemanticScale.error
    public static let forbidden = Color(nsColor: .systemPurple)
    public static func color(for risk: RiskLevel) -> Color {
        switch risk {
        case .low: low
        case .medium: medium
        case .high: high
        case .forbidden: forbidden
        }
    }
    public static func symbol(for risk: RiskLevel) -> String {
        switch risk {
        case .low: "checkmark.shield"
        case .medium: "exclamationmark.triangle"
        case .high: "exclamationmark.shield"
        case .forbidden: "lock.shield"
        }
    }
}

public enum Radius {
    public static let card: CGFloat = 12
    public static let cardCompact: CGFloat = 8
}

public enum Spacing {
    public static let windowMinWidth: CGFloat = 900
    public static let windowMinHeight: CGFloat = 640
    public static let sidebarWidth: CGFloat = 220
    public static let detailPanelWidth: CGFloat = 320
    public static let screenEdge: CGFloat = 24
    public static let sectionGap: CGFloat = 24
    public static let cardPadding: CGFloat = 16
    public static let cardInternal: CGFloat = 12
    public static let elementTight: CGFloat = 8
    public static let elementNormal: CGFloat = 12
    public static let elementSection: CGFloat = 24
    public static let sidebarInternal: CGFloat = 12
}
