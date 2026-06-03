import SwiftUI
import SwiftData
import UIKit

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
    @State private var isRequestingNotificationPermission = false
    @State private var showNotificationDeniedAlert = false
    @State private var showMailUnavailableAlert = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    private let feedbackEmail = "contact@sakshammittal.com"

    private let weekdays = [
        (1, "Sunday"), (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"),
        (5, "Thursday"), (6, "Friday"), (7, "Saturday")
    ]

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
                        Task {
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
            Section {
                Label("All processing happens on your device.", systemImage: "lock.shield")
                    .font(.subheadline)
            } footer: {
                Text("TidyByte has no account and no servers. Your photos and activity never leave your device.")
            }
        }
        .navigationTitle("Settings")
        // Settings shows only `@AppStorage`-backed controls and inline `Bundle.main`
        // version/build reads — all synchronous and always current — so there's no
        // async/derived state to re-fetch. The gesture is wired purely for app-wide
        // consistency (every screen pulls-to-refresh); the helper still fires its
        // completion haptic to acknowledge the gesture.
        .pullToRefresh { }
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

    private func resetSwipeHistory() {
        do {
            try modelContext.delete(model: SwipeRecord.self)
            try modelContext.save()
        } catch {
            // Non-critical
        }
    }
}
