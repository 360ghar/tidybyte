import MacOSCleanerCore
import SwiftUI

/// Insights › History: every change Tidybyte made, with restore where the
/// operation supports it. System cleanup and Photos & Media keep separate
/// records, so a segmented control switches between them.
struct HistoryView: View {
    @Bindable var model: AppViewModel
    @SceneStorage("historyMode") private var showsMedia = false

    var body: some View {
        Group {
            if showsMedia || !DistributionChannel.supportsAdvanced {
                CleanupActivityView(model: model.cleanup)
            } else {
                UndoHistoryView(model: model)
            }
        }
        .toolbar {
            if DistributionChannel.supportsAdvanced {
                ToolbarItem(placement: .principal) {
                    Picker(String(localized: "History"), selection: $showsMedia) {
                        Text(String(localized: "Cleanup")).tag(false)
                        Text(String(localized: "Photos & Media")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }
}
