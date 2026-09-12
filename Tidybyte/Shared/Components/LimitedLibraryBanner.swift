import SwiftUI

/// Compact, persistent notice shown while the app has *limited* photo access.
///
/// Limited access is the state most likely to make TidyByte look broken: the
/// scans genuinely only see the handful of photos the user picked, so tool
/// results are correct but tiny. Without this banner that reads as "the app
/// can't find anything" rather than "the app can only see 12 photos".
///
/// Self-hiding: renders nothing unless access is limited.
struct LimitedLibraryBanner: View {
    @Environment(PhotoPermissionHandler.self) private var permissionHandler
    @AppStorage(AppPreferences.Key.hasSeenLimitedLibraryNotice) private var hasSeenNotice = false

    var body: some View {
        if permissionHandler.permissionState == .limited {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "photo.badge.plus")
                .font(.headline)
                .foregroundStyle(Color.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Limited Photo Access")
                    .font(.subheadline.bold())

                Text(hasSeenNotice
                     ? "TidyByte can only see the photos you selected."
                     : "You shared some photos with TidyByte. To clean up your whole library, share all of them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Add More Photos") {
                    HapticHelper.impact(.light)
                    PhotoPermissionHandler.presentLimitedLibraryPicker()
                }
                .font(.footnote.bold())
                .padding(.top, Spacing.xs)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .fill(Color.warning.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .strokeBorder(Color.warning.opacity(0.35), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            // The fuller wording explains what limited access means; after the
            // first sighting the compact reminder is enough.
            if !hasSeenNotice { hasSeenNotice = true }
        }
    }
}
