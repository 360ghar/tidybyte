import SwiftUI

/// Full-screen permission gate shown in place of a tab's content when the app
/// has no library access.
///
/// Two states, and they need different things from the user:
///
/// - `.notDetermined` — nothing has been asked yet. Lead with what the app does
///   and offer the prompt.
/// - `.denied` / `.restricted` — the prompt is spent and iOS will not show it
///   again, so the only way forward is Settings. Lead with that.
struct PhotoPermissionView: View {
    let permissionHandler: PhotoPermissionHandler

    /// True when the system prompt is spent and Settings is the only route back.
    /// `.limited` never reaches this view — `RootView` renders tab content for
    /// it — but it is not a denial, so it is excluded here too.
    private var isDenied: Bool {
        switch permissionHandler.permissionState {
        case .denied, .restricted: true
        default: false
        }
    }

    private var accent: Color {
        isDenied ? .warning : .blue
    }

    var body: some View {
        // Wrapped in a scroll view so the copy and capability list stay
        // reachable at accessibility text sizes, where they exceed the screen.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    Spacer(minLength: Spacing.lg)

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [accent.opacity(0.15), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 90
                                )
                            )
                            .scaledSquare(ScaledSize.stateHalo)

                        Image(systemName: isDenied ? "lock.shield" : "photo.on.rectangle.angled")
                            .scaledGlyph(ScaledSize.stateGlyph, weight: .light)
                            .foregroundStyle(accent.opacity(0.85))
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: Spacing.md) {
                        Text(isDenied ? "Photo Access Is Off" : "TidyByte Needs Your Photos")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(isDenied
                             ? "iOS is blocking TidyByte from your library. Turn access back on in Settings and everything here starts working again."
                             : "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    capabilitiesCard

                    actionButton

                    Spacer(minLength: Spacing.lg)
                }
                .padding(.horizontal, Spacing.lg)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .readableWidth()
            }
        }
    }

    // MARK: - What the access is for

    private var capabilitiesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            capability(icon: "doc.on.doc", text: "Find exact and near-duplicate photos")
            capability(icon: "camera.metering.unknown", text: "Spot blurry, dark, and overexposed shots")
            capability(icon: "externaldrive", text: "Surface the biggest files taking up space")
            capability(icon: "trash.slash", text: "Delete only what you review and approve")
        }
        .glassCard()
    }

    private func capability(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionButton: some View {
        if isDenied {
            Button {
                HapticHelper.impact(.light)
                permissionHandler.openSettings()
            } label: {
                primaryLabel("Open Settings", icon: "arrow.up.right.square")
            }
            .scaleOnPress()
            .accessibilityHint("Opens iOS Settings, where you can turn photo access back on")
        } else {
            Button {
                HapticHelper.impact(.light)
                Task { await permissionHandler.requestPermission() }
            } label: {
                primaryLabel("Allow Access", icon: "checkmark")
            }
            .scaleOnPress()
            .accessibilityHint("Opens the iOS permission prompt for your photo library")
        }
    }

    private func primaryLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
            .background(.tint)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}
