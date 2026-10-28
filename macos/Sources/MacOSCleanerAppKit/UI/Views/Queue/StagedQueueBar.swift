import MacOSCleanerCore
import SwiftUI

/// Floating glass bar with the approved-change count and the one action that
/// leads to the confirmation sheet. Selection and approval stay in the list.
struct StagedQueueBar: View {
    @Bindable var model: AppViewModel
    var onConfirm: (RiskLevel) -> Void

    var body: some View {
        let actions = model.pendingExecutableActions()
        if !actions.isEmpty {
            GlassEffectContainer {
                HStack(spacing: Spacing.elementNormal) {
                    Label(
                        String(localized: "\(actions.count) approved", comment: "Count of approved actions"),
                        systemImage: "checkmark.circle"
                    )
                    .padding(.leading, Spacing.elementTight)
                    if !model.pendingExecutableActions(upTo: .low).isEmpty {
                        Button(String(localized: "Clean Low Risk Only…")) { onConfirm(.low) }
                            .buttonStyle(.glass)
                    }
                    Button(String(localized: "Review & Clean…")) { onConfirm(.high) }
                        .buttonStyle(.glassProminent)
                }
                .padding(Spacing.elementTight)
                .glassEffect(in: .capsule)
            }
            .disabled(model.isScanning || model.isExecuting || model.isPlanning)
            .padding(.bottom, Spacing.elementNormal)
        }
    }
}
