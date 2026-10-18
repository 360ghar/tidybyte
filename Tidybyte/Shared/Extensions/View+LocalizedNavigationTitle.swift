import SwiftUI

/// A navigation title that follows a live language change.
///
/// `.navigationTitle("key")` is not enough, for two separate reasons that both
/// show up as the same stale title:
///
/// 1. The literal is the *same* `LocalizedStringKey` in every language, and the
///    bar is UIKit-backed, so it only re-applies a title whose **value** changed.
/// 2. A title is a value computed when the view's body runs, and a screen that
///    was hidden while the language changed does not run its body again. Its leaf
///    `Text` views re-resolve against `\.locale` and read correctly, which is why
///    the staleness is easy to miss: the body is in the new language while the
///    bar above it is still in the old one.
///
/// This modifier fixes both. It resolves the key through `L10n`, so the value
/// differs per language, and it reads the live language, so the modifier itself
/// re-runs on a change and pushes the new title.
extension View {
    /// A `.navigationTitle` that re-resolves when the language changes.
    ///
    /// - Parameter key: the String Catalog key, which is the English text.
    func localizedNavigationTitle(_ key: String) -> some View {
        modifier(LocalizedNavigationTitle(key: key))
    }
}

private struct LocalizedNavigationTitle: ViewModifier {
    let key: String

    /// Optional so a presentation that does not inherit the environment — some
    /// sheet and cover presentations — degrades to a plain lookup rather than
    /// trapping on a dependency that is not there.
    @Environment(LanguageStore.self) private var languageStore: LanguageStore?

    func body(content: Content) -> some View {
        // Reading the store is the point of this modifier: it is the dependency
        // that makes the title recompute. `nil` falls back to `L10n`'s own
        // lookup of the stored override.
        content.navigationTitle(L10n.string(key, language: languageStore?.effectiveLanguage))
    }
}
