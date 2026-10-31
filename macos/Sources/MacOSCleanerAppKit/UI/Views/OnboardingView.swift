import MacOSCleanerCore
import SwiftUI

/// First-run sheet: welcome, Full Disk Access, Photos, then the first scan.
/// The step is saved, so onboarding resumes after System Settings asks to
/// quit and reopen Tidybyte.
struct OnboardingView: View {
    static let stepKey = "onboardingStep"
    static let doneStep = 4

    @Bindable var model: AppViewModel
    @AppStorage(OnboardingView.stepKey) private var step = 0
    @AppStorage(AppDelegate.menuBarExtraKey) private var showsMenuBarExtra = false
    @State private var hasFullDiskAccess = FullDiskAccess.isGranted()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.elementSection) {
            switch step {
            case 0: welcome
            case 1: fullDiskAccess
            case 2: photos
            default: ready
            }
        }
        .padding(Spacing.sectionGap + 8)
        .frame(width: 520)
        .animation(reduceMotion ? nil : .appSelection, value: step)
        .task(id: step) { await waitForFullDiskAccess() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: Spacing.elementNormal) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(String(localized: "Welcome to Tidybyte")).font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: Spacing.elementNormal) {
                point("magnifyingglass", String(localized: "Finds caches, leftovers, duplicates, and large files."))
                point("hand.raised", String(localized: "Nothing changes until you approve it."))
                point("arrow.uturn.backward", String(localized: "Files go to the Trash, and History can restore them."))
            }
            .padding(.vertical, Spacing.elementTight)
            // The App Store build is sandboxed; Full Disk Access does not apply.
            Button(String(localized: "Continue")) { step = DistributionChannel.supportsAdvanced ? 1 : 2 }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var fullDiskAccess: some View {
        VStack(spacing: Spacing.elementNormal) {
            Image(systemName: hasFullDiskAccess ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(.largeTitle))
                .foregroundStyle(hasFullDiskAccess ? AnyShapeStyle(SemanticScale.success) : AnyShapeStyle(.tint))
                .accessibilityHidden(true)
            Text(String(localized: "Allow Full Disk Access")).font(.title.bold())
            Text(
                String(
                    localized: """
                        macOS hides Mail, Safari, and other apps' data until you allow it. \
                        Turn on Tidybyte in Privacy & Security › Full Disk Access. You can also \
                        drag the icon below into that list.
                        """)
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
                .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                .help(String(localized: "Drag into the Full Disk Access list"))
                .accessibilityLabel(String(localized: "Tidybyte app icon"))
            HStack {
                Button(String(localized: "Skip for Now")) { step = 2 }
                Button(String(localized: "Open Privacy & Security")) { PermissionLinks.openFullDiskAccess() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            Text(String(localized: "Tidybyte continues on its own once access is on."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var photos: some View {
        VStack(spacing: Spacing.elementNormal) {
            Image(systemName: "photo.on.rectangle").font(.system(.largeTitle)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(String(localized: "Include your Photos library?")).font(.title.bold())
            Text(
                String(
                    localized: """
                        Tidybyte can find similar shots, blurry photos, and large videos in Photos. \
                        Anything you remove goes to Recently Deleted in Photos.
                        """)
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "Not Now")) {
                    model.cleanup.scope.includesPhotos = false
                    step = 3
                }
                Button(String(localized: "Allow Photos Access")) {
                    Task {
                        // Include Photos only when access was granted; a denial must not block the folder scan.
                        let granted = (try? await PhotoLibraryService().authorize()) != nil
                        model.cleanup.scope.includesPhotos = granted
                        step = 3
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }

    private var ready: some View {
        VStack(spacing: Spacing.elementNormal) {
            Image(systemName: "checkmark.circle.fill").font(.system(.largeTitle)).foregroundStyle(SemanticScale.success)
                .accessibilityHidden(true)
            Text(String(localized: "You're all set")).font(.title.bold())
            Toggle(String(localized: "Show free space in the menu bar"), isOn: $showsMenuBarExtra)
                .toggleStyle(.switch)
            Button(String(localized: "Scan My Mac")) {
                step = Self.doneStep
                model.scanAll()
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }

    /// Checks every second while the Full Disk Access step shows.
    private func waitForFullDiskAccess() async {
        guard step == 1 else { return }
        while !Task.isCancelled {
            hasFullDiskAccess = FullDiskAccess.isGranted()
            if hasFullDiskAccess {
                try? await Task.sleep(for: .seconds(1))
                step = 2
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
