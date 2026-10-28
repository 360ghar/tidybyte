import MacOSCleanerCore
import SwiftUI

struct CleanupSettingsView: View {
    @Bindable var model: CleanupModel
    @State private var confirmsReset = false
    var body: some View {
        Form {
                Section(String(localized: "Analysis")) {
                    Slider(value: $model.settings.similarSeconds, in: 1...60, step: 1) {
                        Text(String(localized: "Similar files: \(Int(model.settings.similarSeconds)) seconds"))
                    }
                    Picker(String(localized: "Blur sensitivity"), selection: $model.settings.blurSensitivity) {
                        Text(String(localized: "Low")).tag(0)
                        Text(String(localized: "Medium")).tag(1)
                        Text(String(localized: "High")).tag(2)
                    }
                    Picker(String(localized: "Category sensitivity"), selection: $model.settings.categorySensitivity) {
                        Text(String(localized: "Strict")).tag(0)
                        Text(String(localized: "Balanced")).tag(1)
                        Text(String(localized: "Broad")).tag(2)
                    }
                    Slider(value: $model.settings.largeMegabytes, in: 5...500, step: 5) {
                        Text(String(localized: "Large files: \(Int(model.settings.largeMegabytes)) MB"))
                    }
                    Picker(String(localized: "Default swipe filter"), selection: $model.settings.defaultFilter) {
                        ForEach(ReviewFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section(String(localized: "Compression")) {
                    Picker(String(localized: "Video resolution"), selection: $model.settings.videoHeight) {
                        Text("1080p").tag(1080)
                        Text("720p").tag(720)
                        Text("480p").tag(480)
                    }
                    Picker(String(localized: "Image quality"), selection: $model.settings.imageQuality) {
                        Text(String(localized: "High")).tag(ImageQuality.high)
                        Text(String(localized: "Balanced")).tag(ImageQuality.balanced)
                        Text(String(localized: "Small")).tag(ImageQuality.small)
                    }
                }
                Section(String(localized: "Reminder")) {
                    Toggle(String(localized: "Weekly cleanup reminder"), isOn: $model.settings.reminderEnabled)
                    Picker(String(localized: "Day at 09:00"), selection: $model.settings.reminderWeekday) {
                        ForEach(1...7, id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
                    }.disabled(!model.settings.reminderEnabled)
                    Text(String(localized: "Reminders quote the date and real counts from the last completed scan."))
                        .font(.caption)
                }
                Section(String(localized: "History")) {
                    Button(String(localized: "Reset Review History…"), role: .destructive) { confirmsReset = true }
                        .disabled(model.isBusy)
                }
        }
            .formStyle(.grouped)
            .onChange(of: model.settings.defaultFilter) { model.filter = model.settings.defaultFilter }
            // Reminder changes must schedule/cancel the notification
            // immediately; saveSettings() is what (re)registers it, and the
            // window can stay open indefinitely.
            .onChange(of: model.settings.reminderEnabled) { _, _ in
                Task { await model.saveSettings() }
            }
            .onChange(of: model.settings.reminderWeekday) { _, _ in
                Task { await model.saveSettings() }
            }
            .onDisappear { Task { await model.saveSettings() } }
            .confirmationDialog(
                String(
                    localized: """
                        Reset review history and discard saved review drafts? Activity and \
                        recovery records will remain.
                        """
                ), isPresented: $confirmsReset
            ) {
                Button(String(localized: "Reset Review History"), role: .destructive) {
                    Task { await model.resetHistory() }
                }
            }
    }
}
