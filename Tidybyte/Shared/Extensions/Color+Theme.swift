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
    static let extraLarge: CGFloat = 20
    static let full: CGFloat = 100
}

// MARK: - Colors

extension Color {
    static let appBackground = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let tertiaryBackground = Color(.tertiarySystemBackground)

    static let appAccent = Color.blue
    static let destructive = Color.red
    static let success = Color.green
    static let warning = Color.orange

    static let photoCategory = Color.blue
    static let videoCategory = Color.purple
    static let screenshotCategory = Color.yellow
    static let livePhotoCategory = Color.teal
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
    static let elevatedSurface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.06)
    })
}

// MARK: - Gradients

extension LinearGradient {
    static let accentGradient = LinearGradient(
        colors: [.blue, .blue.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let headerGradient = LinearGradient(
        colors: [.blue.opacity(0.15), .clear],
        startPoint: .top,
        endPoint: .bottom
    )

    static let destructiveGradient = LinearGradient(
        colors: [.red, .red.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let successGradient = LinearGradient(
        colors: [.green, .green.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

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

    func glowShadow(color: Color = .blue, radius: CGFloat = 12) -> some View {
        self.shadow(color: color.opacity(0.3), radius: radius)
    }
}
