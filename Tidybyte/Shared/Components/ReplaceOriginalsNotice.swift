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
    ///   - copies: what step 1 makes, e.g. "a new, smaller copy of each video".
    ///   - originals: what step 2 deletes, e.g. "the original videos".
    static func explainer(copies: String, originals: String) -> String {
        """
        1. TidyByte saves \(copies).
        2. When all copies are saved, iOS asks you to delete \(originals).

        If you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.
        """
    }

    /// Bottom-bar status for the running step. `nil` when idle.
    static func phaseText(_ phase: ReplacePhase) -> String? {
        switch phase {
        case .idle:
            nil
        case .savingCopies(let done, let total):
            "Step 1 of 2 · Saving copy \(min(done + 1, total)) of \(total)"
        case .removingOriginals:
            "Step 2 of 2 · Confirm in the iOS alert to delete the originals"
        }
    }
}

extension View {
    /// Shown when saved copies exist but their originals are still in the
    /// library (the user tapped "Don't Allow", or the delete failed).
    func originalsKeptAlert(
        isPresented: Bool,
        onTryAgain: @escaping () -> Void,
        onRemoveCopies: @escaping () -> Void
    ) -> some View {
        alert("Originals Kept", isPresented: .constant(isPresented)) {
            Button("Try Again", action: onTryAgain)
            Button("Remove Copies", action: onRemoveCopies)
        } message: {
            Text("Your new copies are saved. Nothing was lost. Try again to delete the originals and free space, or remove the new copies.")
        }
    }
}
