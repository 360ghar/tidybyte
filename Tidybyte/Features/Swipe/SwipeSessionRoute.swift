import Foundation
import SwiftData
import SwiftUI

struct SwipeSessionRoute: Identifiable, Hashable, Sendable {
    let id: UUID
    let filter: SwipeFilter

    init(id: UUID = UUID(), filter: SwipeFilter) {
        self.id = id
        self.filter = filter
    }
}

struct SwipeSessionHostView: View {
    @State private var viewModel: SwipeSessionViewModel

    init(route: SwipeSessionRoute, photoService: PhotoLibraryService, modelContext: ModelContext) {
        _viewModel = State(
            initialValue: SwipeSessionViewModel(
                filter: route.filter,
                photoService: photoService,
                modelContext: modelContext
            )
        )
    }

    var body: some View {
        SwipeSessionView(viewModel: viewModel)
    }
}
