import MacOSCleanerCore
import SwiftUI

/// Errors and permission notices. Shown only while one needs attention;
/// progress lives in the window subtitle and the toolbar Stop button.
struct StatusNotices: View {
    @Bindable var model: AppViewModel

    private var hasNotice: Bool {
        model.errorMessage != nil || model.fullDiskAccessHint != nil || model.isUsingTempDatabase
            || model.cleanup.error != nil || model.cleanup.notice != nil
    }

    var body: some View {
        if hasNotice {
            VStack(alignment: .leading, spacing: Spacing.elementTight) {
                if let error = model.errorMessage {
                    notice(error, symbol: "exclamationmark.triangle.fill", tint: SemanticScale.error) {
                        Button(String(localized: "Dismiss")) { model.dismissError() }
                    }
                }
                if let error = model.cleanup.error {
                    notice(error, symbol: "exclamationmark.triangle.fill", tint: SemanticScale.error) {
                        Button(String(localized: "Dismiss")) { model.cleanup.error = nil }
                    }
                }
                if let hint = model.fullDiskAccessHint {
                    notice(hint, symbol: "lock.shield", tint: SemanticScale.warning) {
                        Button(String(localized: "Open Privacy Settings")) { PermissionLinks.openFullDiskAccess() }
                        Button(String(localized: "Dismiss")) { model.dismissFullDiskAccessHint() }
                    }
                }
                if let notice = model.cleanup.notice {
                    self.notice(notice, symbol: "info.circle", tint: .secondary) {
                        Button(String(localized: "Dismiss")) { model.cleanup.notice = nil }
                    }
                }
                if model.isUsingTempDatabase {
                    Label(
                        String(localized: "Temporary storage is in use. History will not persist after this session."),
                        systemImage: "externaldrive.badge.exclamationmark"
                    )
                    .foregroundStyle(SemanticScale.warning)
                }
            }
            .font(.callout)
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.vertical, Spacing.elementNormal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary)
            .accessibilityElement(children: .contain)
        }
    }

    private func notice<Actions: View>(
        _ text: String, symbol: String, tint: Color, @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.elementNormal) {
            Label {
                Text(text).textSelection(.enabled)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Spacer(minLength: Spacing.elementNormal)
            actions().controlSize(.small)
        }
    }
}

/// System Settings deep links used by notices and onboarding.
enum PermissionLinks {
    static func openFullDiskAccess() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openPhotos() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
