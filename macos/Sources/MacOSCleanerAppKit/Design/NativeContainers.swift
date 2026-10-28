import SwiftUI

/// A quiet content group. Navigation and window chrome are supplied by macOS.
struct ContentSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            content.frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.elementTight)
        } label: {
            Text(title).font(.headline)
        }
    }
}
