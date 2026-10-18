import SwiftUI

/// Copy and alerts shared by the three replace flows (video compression, photo
/// compression, Live Photo conversion). Each flow saves the new copies first,
/// then deletes all originals in one call, so iOS shows one delete prompt.
/// Users who see that prompt without context think their media is being lost,
/// so the order is stated before the start, during the work, and after a
/// "Don't Allow".
enum ReplaceOriginalsNotice {
    /// The confirm-alert message shown before the work starts.
    /// - Parameters:
    ///   - copies: what step 1 makes, e.g. `L10n.string("a new, smaller copy of each video")`.
    ///   - originals: what step 2 deletes, e.g. `L10n.string("the original videos")`.
    ///
    /// Both arguments and the template are resolved through `L10n`, not
    /// interpolated. The assembled sentence is handed to `Text` as a plain
    /// `String`, which is the non-localizing overload, so everything in it has
    /// to arrive already translated.
    static func explainer(copies: String, originals: String) -> String {
        L10n.format(
            "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.",
            copies,
            originals
        )
    }

    /// Bottom-bar status for the running step.
    ///
    /// Resolved through `L10n` because the caller renders the returned `String`
    /// with `Text`, which does not localize a `String`.
    static func phaseText(_ phase: ReplacePhase) -> String {
        switch phase {
        case .idle:
            L10n.string("Working…")
        case .savingCopies(let done, let total):
            L10n.format("Step 1 of 2 · Saving copy %lld of %lld", min(done + 1, total), total)
        case .removingOriginals:
            L10n.string("Step 2 of 2 · Confirm in the iOS alert to delete the originals")
        }
    }
}

extension View {
    /// Shown when saved copies exist but their originals are still in the
    /// library (the user tapped "Don't Allow", or the delete failed).
    func originalsKeptAlert(
        isPresented: Binding<Bool>,
        onTryAgain: @escaping () -> Void,
        onRemoveCopies: @escaping () -> Void
    ) -> some View {
        alert("Originals Kept", isPresented: isPresented) {
            Button("Try Again", action: onTryAgain)
            Button("Remove Copies", action: onRemoveCopies)
        } message: {
            Text("Your new copies are saved. Nothing was lost. Try again to delete the originals and free space, or remove the new copies.")
        }
    }
}
