import MacOSCleanerCore
import SwiftUI

extension View {
    public func accessibleRiskLabel(_ risk: RiskLevel) -> some View {
        accessibilityLabel(String(localized: "Risk: \(risk.displayName)"))
    }
}
