import SwiftUI
import UIKit

// MARK: - Spacing System

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

// MARK: - Corner Radius System

enum CornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let full: CGFloat = 100
}

// MARK: - Colors

extension Color {
    static let appBackground = Color(.systemBackground)
    static let destructive = Color.red
    static let success = Color.green
    static let warning = Color.orange
    static let otherCategory = Color.gray

    // Glass card surface colors — adaptive so the glass look works in both light
    // and dark mode (a translucent light fill on dark, a translucent dark fill on light).
    static let cardSurface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.035)
    })
    static let cardBorder = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.10)
    })
}

// MARK: - Gradients

extension LinearGradient {
    static let storageBarGradient = LinearGradient(
        colors: [.green, .yellow, .orange, .red],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Shadows

extension View {
    func cardShadow() -> some View {
        self.shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    func subtleShadow() -> some View {
        self.shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}
