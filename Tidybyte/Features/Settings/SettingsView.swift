import SwiftUI
import SwiftData
import UIKit
import Photos

struct SettingsView: View {
    // Swipe
    @AppStorage(AppPreferences.Key.defaultSwipeFilter) private var defaultSwipeFilter: String = DefaultSwipeFilterPreference.notSwipedYet.rawValue

    // Similar Photos
    @AppStorage(AppPreferences.Key.similarPhotoTimeWindow) private var timeWindow: Double = 5.0

    // Blur Detection
    @AppStorage(AppPreferences.Key.blurSensitivity) private var blurSensitivity: String = BlurSensitivity.medium.rawValue

    // Smart Categories
    @AppStorage(AppPreferences.Key.smartCategorySensitivity) private var smartCategorySensitivity: String = CategorySensitivity.balanced.rawValue

    // Large Files
    @AppStorage(AppPreferences.Key.largeFileThresholdMB) private var largeFileThreshold: Double = 10.0

    // Video Compression
    @AppStorage(AppPreferences.Key.defaultCompressionPreset) private var compressionPreset: String = "1080p"

    // Photo Compression
    @AppStorage(AppPreferences.Key.defaultPhotoCompressionPreset) private var photoCompressionPreset: String = "high"

    // Notifications
    @AppStorage(AppPreferences.Key.cleanupRemindersEnabled) private var remindersEnabled: Bool = false
    @AppStorage(AppPreferences.Key.reminderWeekday) private var reminderWeekday: Int = 1 // Sunday

    @State private var showResetConfirm = false
    @State private var showResetErrorAlert = false
    @State private var photoPermissionStatus: PHAuthorizationStatus = .notDetermined
    /// Drives the shared pre-prompt explainer for the "Allow Access to Photos"
    /// row, so Settings asks the same way every other surface does.
    @State private var showPhotoPermissionPrimer = false
    @State private var isRequestingNotificationPermission = false
    @State private var showNotificationDeniedAlert = false
    @State private var showMailUnavailableAlert = false
    /// The last weekday we actually committed to the scheduler. The Reminder Day
    /// picker reverts to this when permission was revoked, and the revert must
    /// not be mistaken for a fresh user pick (that would loop forever: each
    /// revert re-triggers `onChange`, whose revert re-triggers `onChange`…).
    @State private var committedReminderWeekday = AppPreferences.reminderWeekday()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// The same handler `RootView` injects, so granting from Settings updates
    /// the tab gate in the same pass instead of on the next activation.
    @Environment(PhotoPermissionHandler.self) private var permissionHandler

    private let feedbackEmail = "contact@sakshammittal.com"

    private let weekdays = [
        (1, "Sunday"), (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"),
        (5, "Thursday"), (6, "Friday"), (7, "Saturday")
    ]

    private var photoPermissionLabel: String {
        switch photoPermissionStatus {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Full Access"
        case .limited: return "Limited Access"
        @unknown default: return "Unknown"
        }
    }

    private var photoPermissionIcon: String {
        switch photoPermissionStatus {
        case .authorized, .limited: return "checkmark.shield"
        case .denied, .restricted: return "exclamationmark.shield"
        default: return "questionmark.shield"
        }
    }

    private var photoPermissionColor: Color {
        switch photoPermissionStatus {
        case .authorized, .limited: return .green
        case .denied, .restricted: return .red
        default: return .orange
        }
    }

    var body: some View {
        Form {
            // MARK: - Swipe Settings
            Section("Swipe") {
                Picker("Default Filter", selection: $defaultSwipeFilter) {
                    ForEach(DefaultSwipeFilterPreference.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter.rawValue)
                    }
                }
            }

            // MARK: - Cleanup Settings
            Section("Cleanup") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Similar Photo Time Window")
                    HStack {
                        Slider(value: $timeWindow, in: 1...60, step: 1)
                        Text("\(Int(timeWindow))s")
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Blur Detection Sensitivity")
                    Picker("Blur Detection Sensitivity", selection: $blurSensitivity) {
                        ForEach(BlurSensitivity.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Smart Category Sensitivity")
                    Picker("Smart Category Sensitivity", selection: $smartCategorySensitivity) {
                        ForEach(CategorySensitivity.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Large File Threshold")
                    HStack {
                        Slider(value: $largeFileThreshold, in: 5...500, step: 5)
                        Text("\(Int(largeFileThreshold)) MB")
                            .monospacedDigit()
                            .frame(width: 60)
                    }
                }
            }

            // MARK: - Video Compression
            Section("Video Compression") {
                Picker("Default Preset", selection: $compressionPreset) {
                    ForEach(CompressionPreset.presets) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
            }

            // MARK: - Photo Compression
            Section("Photo Compression") {
                Picker("Default Preset", selection: $photoCompressionPreset) {
                    ForEach(PhotoCompressionPreset.presets) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
            }

            // MARK: - Notifications
            Section("Reminders") {
                Toggle("Cleanup Reminders", isOn: $remindersEnabled)
                    .disabled(isRequestingNotificationPermission)
                    .onChange(of: remindersEnabled) { _, enabled in
                        if enabled {
                            isRequestingNotificationPermission = true
                            Task {
                                let granted = await NotificationService.requestPermission()
                                isRequestingNotificationPermission = false
                                if granted {
                                    // Keep the committed mirror in sync so a later
                                    // revert lands on the day the user actually has.
                                    committedReminderWeekday = reminderWeekday
                                    await NotificationService.scheduleWeeklyReminder(weekday: reminderWeekday)
                                } else {
                                    remindersEnabled = false
                                    showNotificationDeniedAlert = true
                                }
                            }
                        } else {
                            NotificationService.cancelAllReminders()
                        }
                    }

                if remindersEnabled {
                    Picker("Reminder Day", selection: $reminderWeekday) {
                        ForEach(weekdays, id: \.0) { day in
                            Text(day.1).tag(day.0)
                        }
                    }
                    .onChange(of: reminderWeekday) { _, newDay in
                        // Ignore our own revert below — treating it as a user
                        // pick would flip the value back and forth forever.
                        guard newDay != committedReminderWeekday else { return }
                        Task {
                            // APP-14: if notification permission was revoked, the
                            // reschedule would silently no-op — revert the picker
                            // and surface the same alert as the toggle's deny path.
                            guard await NotificationService.isPermissionGranted() else {
                                reminderWeekday = committedReminderWeekday
                                showNotificationDeniedAlert = true
                                return
                            }
                            committedReminderWeekday = newDay
                            await NotificationService.scheduleWeeklyReminder(weekday: newDay)
                        }
                    }
                }
            }

            // MARK: - Data
            Section("Data") {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text("Reset Swipe History")
                }
            }

            // MARK: - Feedback
            Section("Feedback") {
                Button {
                    sendFeedback(subject: "TidyByte Bug Report", isBug: true)
                } label: {
                    Label("Report a Bug", systemImage: "ladybug")
                }

                Button {
                    sendFeedback(subject: "TidyByte Feature Request", isBug: false)
                } label: {
                    Label("Request a Feature", systemImage: "lightbulb")
                }

                // Same guarantee as the happy-path card's Rate button: the
                // write-review deep link can't be silently swallowed by the
                // OS prompt quota the way `requestReview` can.
                Button {
                    HapticHelper.impact(.light)
                    openURL(AppStoreLinks.writeReviewURL)
                } label: {
                    Label("Rate TidyByte on the App Store", systemImage: "star.fill")
                }

                ShareLink(item: AppStoreLinks.shareMessage(statLine: nil)) {
                    Label("Share with Friends", systemImage: "square.and.arrow.up")
                }
            }

            // MARK: - About
            Section("About") {
                HStack {
                    Text("App")
                    Spacer()
                    Text("TidyByte")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Privacy
            Section("Permissions") {
                HStack {
                    Image(systemName: photoPermissionIcon)
                        .foregroundStyle(photoPermissionColor)
                    Text("Photo Library")
                    Spacer()
                    Text(photoPermissionLabel)
                        .foregroundStyle(.secondary)
                }

                // The offered action comes from the state itself. A fresh
                // install asks for access here — through the same pre-prompt
                // explainer every other surface uses — instead of opening the
                // Settings app, where there is nothing to turn on yet.
                switch permissionHandler.permissionState.presentation.action {
                case .requestPermission:
                    Button {
                        showPhotoPermissionPrimer = true
                    } label: {
                        Label("Allow Access to Photos", systemImage: "checkmark")
                    }
                case .openSettings:
                    Button {
                        openSystemSettings()
                    } label: {
                        Label("Open Settings", systemImage: "arrow.up.right.square")
                    }
                case .none:
                    EmptyView()
                }

                if photoPermissionStatus == .limited {
                    Button {
                        PhotoPermissionHandler.presentLimitedLibraryPicker()
                    } label: {
                        Label("Add More Photos", systemImage: "photo.badge.plus")
                    }
                }

                // `.restricted` deliberately has no button: Screen Time or
                // device management keeps the Photos switch disabled, so the
                // only useful thing to show is where the block comes from.
                if permissionHandler.permissionState == .restricted {
                    Text(permissionHandler.permissionState.presentation.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label("All processing happens on your device.", systemImage: "lock.shield")
                    .font(.subheadline)
            } footer: {
                Text("TidyByte has no account and no servers. Your photos and activity never leave your device.")
            }
        }
        .navigationTitle("Settings")
        .photoPermissionPrimer(
            isPresented: $showPhotoPermissionPrimer,
            permissionHandler: permissionHandler,
            onResolved: { refreshPhotoPermissionStatus() }
        )
        .task {
            refreshPhotoPermissionStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshPhotoPermissionStatus()
            }
        }
        // No pull-to-refresh (E8): Settings shows only `@AppStorage`-backed
        // controls and inline `Bundle.main` reads — synchronous and always
        // current — so the gesture could only fake work.
        .alert("Reset Swipe History", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetSwipeHistory()
            }
        } message: {
            Text("This will clear all swipe records. All photos will appear as \"Not Swiped Yet\" again. This cannot be undone.")
        }
        .alert("Notifications Disabled", isPresented: $showNotificationDeniedAlert) {
            Button("Open Settings") { openSystemSettings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enable notifications for TidyByte in Settings to receive cleanup reminders.")
        }
        .alert("No Mail Account", isPresented: $showMailUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("No email account is set up on this device. Please email us at \(feedbackEmail).")
        }
        .alert("Reset Failed", isPresented: $showResetErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not clear swipe history. Please try again.")
        }
    }

    private func sendFeedback(subject: String, isBug: Bool) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: feedbackBody(isBug: isBug))
        ]
        guard let url = components.url else { return }
        openURL(url) { accepted in
            if !accepted { showMailUnavailableAlert = true }
        }
    }

    private func feedbackBody(isBug: Bool) -> String {
        let prompt = isBug
            ? "Describe the bug:\n\nSteps to reproduce:\n\nWhat you expected:\n\nWhat happened instead:\n"
            : "Describe the feature you'd like:\n\nWhy it would help:\n"
        return "\(prompt)\n\n---\nThe info below helps us debug — please keep it.\n\(diagnostics)"
    }

    private var diagnostics: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let device = UIDevice.current
        return """
        App: TidyByte \(version) (\(build))
        iOS: \(device.systemVersion)
        Device: \(deviceModelIdentifier)
        """
    }

    private var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let id = mirror.children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 {
                result.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        return id.isEmpty ? UIDevice.current.model : id
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshPhotoPermissionStatus() {
        photoPermissionStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func resetSwipeHistory() {
        do {
            try modelContext.delete(model: SwipeRecord.self)
            try modelContext.save()
        } catch {
            AppLog.data.error("Failed to reset swipe history: \(error.localizedDescription, privacy: .public)")
            showResetErrorAlert = true
        }
    }
}
