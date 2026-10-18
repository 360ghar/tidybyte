import SwiftUI
import SwiftData
import UIKit
import Photos

struct SettingsView: View {
    @Environment(WidgetSnapshotCoordinator.self) private var widgetCoordinator
    /// The live language/appearance state. Changing the language here
    /// re-renders the whole app: `RootView` injects `\.locale` and keys the tree
    /// on the language, so every screen follows without a relaunch.
    @Environment(LanguageStore.self) private var languageStore
    // Swipe
    @AppStorage(AppPreferences.Key.defaultSwipeFilter) private var defaultSwipeFilter: String = DefaultSwipeFilterPreference.notSwipedYet.rawValue

    // Haptics
    @AppStorage(AppPreferences.Key.hapticsEnabled) private var hapticsEnabled: Bool = true

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
    @State private var toast: ToastMessage?
    @State private var showResetErrorAlert = false
    @State private var photoPermissionStatus: PHAuthorizationStatus = .notDetermined
    /// Drives the shared pre-prompt explainer for the "Allow Access to Photos"
    /// row, so Settings asks the same way every other surface does.
    @State private var showPhotoPermissionPrimer = false
    @State private var isRequestingNotificationPermission = false
    @State private var showNotificationDeniedAlert = false
    @State private var showMailUnavailableAlert = false
    /// The last composer attempt failed to hand the message to Mail, so
    /// Settings says so instead of closing as if the feedback went out.
    @State private var showMailSendFailedAlert = false
    /// The in-app composer's payload, or nil when it is not presented.
    @State private var mailDraft: MailDraft?
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

    /// The reminder picker's rows, ordered from the device's first day of the
    /// week. Built from the device calendar rather than a hardcoded
    /// Sunday-first list, so the picker opens on the day the user's own
    /// calendar starts with (Monday in India, Germany and Brazil; Saturday in
    /// much of the Middle East) and every name is localized.
    private var weekdays: [(weekday: Int, name: String)] {
        Formatters.orderedWeekdays()
    }

    /// The reminder time, formatted in the device's convention. Replaces a
    /// hardcoded "10 AM", which was wrong everywhere that reads a 24-hour
    /// clock — most of the world.
    private var reminderTimeLabel: String {
        var components = DateComponents()
        components.hour = NotificationService.reminderHour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? .now
        return Formatters.shortTime(date)
    }

    private var photoPermissionLabel: String {
        switch photoPermissionStatus {
        case .notDetermined: return L10n.string("Not Asked Yet")
        case .restricted: return L10n.string("Restricted")
        case .denied: return L10n.string("Denied")
        case .authorized: return L10n.string("Full Access")
        case .limited: return L10n.string("Limited Access")
        @unknown default: return L10n.string("Unknown")
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
        case .authorized: return .green
        // Limited works, but TidyByte sees only some photos: not a full green.
        case .limited: return .orange
        case .denied, .restricted: return .red
        default: return .orange
        }
    }

    var body: some View {
        Form {
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

            // MARK: - Language & Appearance
            //
            // Placed directly under Permissions: these are the two settings a
            // user looks for first when the app is not speaking their language
            // or hurts their eyes, and burying them under tool settings would
            // make them hard to find in exactly the situation where the rest of
            // the screen is unreadable.
            Section {
                Picker("Language", selection: languageBinding) {
                    Text("Automatic").tag(AppLanguage.system.rawValue)
                    Divider()
                    // Endonyms: every row is written in its own language and
                    // script, so someone who cannot read the current UI language
                    // can still find theirs.
                    ForEach(AppLanguage.concreteLanguages) { language in
                        Text(language.endonym).tag(language.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.language")

                if languageStore.deviceLanguageIsUnsupported {
                    // The device is set to a language with no translations. Say
                    // so plainly instead of leaving the user wondering why the
                    // app is in English.
                    Text("Your device language is not translated yet, so TidyByte is using English. Pick a language above to override.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // The photo-permission alert, the Photos picker, and the share
                // sheet are drawn by iOS, which reads the app's language at
                // launch. This is the escape hatch for anyone who wants the
                // whole app — including those dialogs — in one language.
                Button {
                    openSystemSettings()
                } label: {
                    Label("Open iOS Settings", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Automatic follows your device. TidyByte changes immediately; some iOS dialogs follow on the next launch.")
            }

            Section("Appearance") {
                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("settings.appearance")
            }

            Section {
                Toggle("Haptics", isOn: $hapticsEnabled)
                    .onChange(of: hapticsEnabled) { _, enabled in
                        // Push the change into the cache the swipe deck reads,
                        // so the toggle takes effect on the next gesture rather
                        // than on the next launch.
                        AppPreferences.saveHapticsEnabled(enabled)
                        HapticHelper.refreshEnabledState()
                    }
            } footer: {
                Text("Vibration feedback when you swipe, tap, and finish a cleanup.")
            }

            // MARK: - Swipe Settings
            Section("Swipe") {
                Picker("Default Filter", selection: $defaultSwipeFilter) {
                    ForEach(DefaultSwipeFilterPreference.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter.rawValue)
                    }
                }
            }

            // MARK: - Cleanup Settings
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Similar Photo Time Window")
                    HStack {
                        Slider(value: $timeWindow, in: 1...60, step: 1)
                            .accessibilityLabel("Similar Photo Time Window")
                            .accessibilityValue("\(Int(timeWindow)) seconds")
                        Text("\(Int(timeWindow))s")
                            .monospacedDigit()
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Blur Detection Sensitivity")
                    Picker("Blur Detection Sensitivity", selection: $blurSensitivity) {
                        ForEach(BlurSensitivity.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Smart Category Sensitivity")
                    Picker("Smart Category Sensitivity", selection: $smartCategorySensitivity) {
                        ForEach(CategorySensitivity.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Large File Threshold")
                    HStack {
                        Slider(value: $largeFileThreshold, in: 5...500, step: 5)
                            .accessibilityLabel("Large File Threshold")
                            .accessibilityValue("\(Int(largeFileThreshold)) megabytes")
                        Text("\(Int(largeFileThreshold)) MB")
                            .monospacedDigit()
                            .fixedSize()
                            .accessibilityHidden(true)
                    }
                }
            } header: {
                Text("Cleanup")
            } footer: {
                Text("Time window: photos taken this close together count as similar. Higher blur sensitivity flags more photos. Broad sorting puts more photos in categories, with more mistakes.")
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
            Section {
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
                                    await widgetCoordinator.refreshReminder()
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
                        ForEach(weekdays, id: \.weekday) { day in
                            Text(day.name).tag(day.weekday)
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
                            await widgetCoordinator.refreshReminder()
                        }
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                if remindersEnabled {
                    Text("Sent every week at \(reminderTimeLabel) on the day you pick. Tapping it opens Cleanup.")
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

                // Same guarantee as the happy-path prompt's fallback link: the
                // write-review deep link can't be silently swallowed by the
                // OS prompt quota the way `requestReview` can. A tap also
                // marks the user as rated, so the prompt stops asking.
                Button {
                    HapticHelper.impact(.light)
                    AppPreferences.saveHasRatedApp()
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

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Acknowledgements")
                    Text("TidyByte is built only with Apple frameworks. It includes no third-party code.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .navigationTitle("Settings")
        .toast($toast)
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
            Text("No email account is set up on this device. Please email us at \(FeedbackMail.address).")
        }
        .alert("Reset Failed", isPresented: $showResetErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not clear swipe history. Please try again.")
        }
        .alert("Couldn't Send Feedback", isPresented: $showMailSendFailedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The message couldn't be sent. Please try again or email us at \(FeedbackMail.address).")
        }
        .sheet(item: $mailDraft) { draft in
            MailComposeView(subject: draft.subject, body: draft.body) { result in
                mailDraft = nil
                // MessageUI's `.failed` means the message was neither saved
                // nor queued — surface it instead of dismissing silently.
                showMailSendFailedAlert = (result == .failed)
            }
        }
    }

    private func sendFeedback(subject: String, isBug: Bool) {
        let prompt = isBug
            ? "Describe the bug:\n\nSteps to reproduce:\n\nWhat you expected:\n\nWhat happened instead:\n"
            : "Describe the feature you'd like:\n\nWhy it would help:\n"
        // Same gate as the prompt card: `openURL(mailto:)` reports success
        // whenever Mail is installed, so ask MessageUI instead and show the
        // plain-text address when it genuinely cannot send.
        guard FeedbackMail.canSend else {
            showMailUnavailableAlert = true
            return
        }
        showMailSendFailedAlert = false
        mailDraft = MailDraft(subject: subject, body: FeedbackMail.body(prompt: prompt))
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// The language picker writes through `LanguageStore`, not `@AppStorage`:
    /// the store also mirrors the choice into the App Group (for the widget),
    /// writes `AppleLanguages` (for iOS-drawn dialogs), and reloads widget
    /// timelines. A bare `@AppStorage` write would skip all three.
    private var languageBinding: Binding<String> {
        Binding(
            get: { languageStore.language.rawValue },
            set: { raw in
                guard let language = AppLanguage(rawValue: raw) else { return }
                languageStore.setLanguage(language)
            }
        )
    }

    /// Same reasoning as `languageBinding`: the store owns the write so the
    /// value and the persisted key cannot drift.
    private var appearanceBinding: Binding<String> {
        Binding(
            get: { languageStore.appearance.rawValue },
            set: { raw in
                guard let appearance = AppAppearance(rawValue: raw) else { return }
                languageStore.appearance = appearance
            }
        )
    }

    private func refreshPhotoPermissionStatus() {
        photoPermissionStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func resetSwipeHistory() {
        do {
            try modelContext.delete(model: SwipeRecord.self)
            try modelContext.save()
            toast = ToastMessage(text: L10n.string("Swipe history cleared"), systemImage: "checkmark.circle")
        } catch {
            AppLog.data.error("Failed to reset swipe history: \(error.localizedDescription, privacy: .public)")
            showResetErrorAlert = true
        }
    }
}
