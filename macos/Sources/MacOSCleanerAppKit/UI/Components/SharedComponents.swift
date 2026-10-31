import MacOSCleanerCore
import SwiftUI

public struct RiskBadge: View {
    let risk: RiskLevel
    public init(risk: RiskLevel) { self.risk = risk }

    public var body: some View {
        Label {
            Text(risk.displayName)
        } icon: {
            Image(systemName: RiskScale.symbol(for: risk)).foregroundStyle(RiskScale.color(for: risk))
        }
        .font(.caption)
        .accessibleRiskLabel(risk)
    }
}

public struct SecondaryButton: View {
    let title: String
    let icon: String?
    let isDisabled: Bool
    let action: () -> Void

    public init(title: String, icon: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if let icon { Label(title, systemImage: icon) } else { Text(title) }
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }
}
