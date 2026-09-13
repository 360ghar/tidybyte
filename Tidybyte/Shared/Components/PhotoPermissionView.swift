import SwiftUI

/// Full-screen permission gate shown in place of a tab's content when the app
/// has no library access.
///
/// Every string and the offered action come from
/// `PhotoPermissionState.presentation`, so this screen, the Settings row, and
/// the unit tests agree on what each state means. Three shapes reach here:
///
/// - `.notDetermined` — nothing has been asked yet. Explain first (the primer),
///   then let iOS ask.
/// - `.denied` — the prompt is spent and iOS will not show it again, so
///   Settings is the only route back.
/// - `.restricted` — Screen Time or device management blocks the library and
///   the Photos switch in Settings is disabled, so there is no button to offer
///   and the copy says why.
struct PhotoPermissionView: View {
    let permissionHandler: PhotoPermissionHandler

    /// Drives the pre-prompt explainer. Tapping the ask affordance opens it;
    /// only its "Continue" reaches `PHPhotoLibrary.requestAuthorization`.
    @State private var showPrimer = false

    private var presentation: PermissionPresentation {
        permissionHandler.permissionState.presentation
    }

    /// `.limited` never reaches this view — `RootView` renders tab content for
    /// it — but it is not a denial, so it is excluded here too.
    private var isWarning: Bool {
        switch permissionHandler.permissionState {
        case .denied, .restricted: true
        default: false
        }
    }

    private var accent: Color {
        isWarning ? .warning : .blue
    }

    private var glyph: String {
        switch permissionHandler.permissionState {
        case .denied, .restricted: "lock.shield"
        default: "photo.on.rectangle.angled"
        }
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

                        Image(systemName: glyph)
                            .scaledGlyph(ScaledSize.stateGlyph, weight: .light)
                            .foregroundStyle(accent.opacity(0.85))
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: Spacing.md) {
                        Text(presentation.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(presentation.message)
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
        .photoPermissionPrimer(isPresented: $showPrimer, permissionHandler: permissionHandler)
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

    /// Driven by the presentation model, so a state that has no useful button
    /// (`.restricted`) simply renders none instead of pointing at a switch the
    /// OS keeps disabled.
    @ViewBuilder
    private var actionButton: some View {
        switch presentation.action {
        case .requestPermission:
            Button {
                HapticHelper.impact(.light)
                showPrimer = true
            } label: {
                primaryLabel("Allow Access", icon: "checkmark")
            }
            .scaleOnPress()
            .accessibilityHint("Explains what TidyByte needs, then opens the iOS permission prompt")
        case .openSettings:
            Button {
                HapticHelper.impact(.light)
                permissionHandler.openSettings()
            } label: {
                primaryLabel("Open Settings", icon: "arrow.up.right.square")
            }
            .scaleOnPress()
            .accessibilityHint("Opens iOS Settings, where you can turn photo access back on")
        case .none:
            EmptyView()
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

// MARK: - Pre-prompt explainer

/// Shown before the one-shot system prompt so the ask is never cold — and so a
/// tap that can no longer produce a dialog is explained rather than silently
/// forwarding the user to the Settings app.
struct PhotoPermissionPrimer: ViewModifier {
    @Binding var isPresented: Bool
    let permissionHandler: PhotoPermissionHandler
    /// Runs after the user answers, so a screen that mirrors the raw
    /// `PHAuthorizationStatus` (Settings) can re-read it.
    var onResolved: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(PermissionPresentation.primerTitle, isPresented: $isPresented) {
            Button(PermissionPresentation.primerButtonTitle) {
                // Explicit main actor: `onResolved` reaches back into SwiftUI
                // state (Settings re-reads its raw status), and this closure is
                // not guaranteed to inherit the actor from the modifier's body.
                Task { @MainActor in
                    await permissionHandler.requestPermission()
                    onResolved?()
                }
            }
            Button(PermissionPresentation.declineButtonTitle, role: .cancel) {
                // Deliberate no-op: declining the primer leaves the permission
                // untouched, so the ask is still available on a later tap.
            }
        } message: {
            Text(PermissionPresentation.primerMessage)
        }
    }
}

extension View {
    /// Attaches the shared pre-prompt explainer. `onResolved` is called after
    /// the system prompt closes.
    func photoPermissionPrimer(
        isPresented: Binding<Bool>,
        permissionHandler: PhotoPermissionHandler,
        onResolved: (() -> Void)? = nil
    ) -> some View {
        modifier(
            PhotoPermissionPrimer(
                isPresented: isPresented,
                permissionHandler: permissionHandler,
                onResolved: onResolved
            )
        )
    }
}
