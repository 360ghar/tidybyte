import Darwin
import MacOSCleanerAppKit
import MacOSCleanerCore

// Entry point. The full SwiftUI app shell (AppViewModel, views, design system)
// lives in the MacOSCleanerAppKit library so it can be unit-tested.
//
// `--autoscan` (invoked by the com.sakshammittal.tidybyte.autoscan LaunchAgent)
// runs one unattended maintenance pass — scan, then fold exact duplicates
// only, never delete — and exits without showing a window.

if CommandLine.arguments.contains("--autoscan") {
    await AutoScanRunner.run()
    exit(0)
}

#if canImport(Sparkle) && !APP_STORE
import Sparkle

// Updates are signed with the key in SUPublicEDKey. Builds without a key
// (development) never start the updater and show no update command.
let canUpdate = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
let updater = SPUStandardUpdaterController(startingUpdater: canUpdate, updaterDelegate: nil, userDriverDelegate: nil)
if canUpdate {
    MacOSCleanerApp.checkForUpdates = { updater.checkForUpdates(nil) }
}
#endif

MacOSCleanerApp.main()
