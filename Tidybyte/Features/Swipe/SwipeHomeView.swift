import SwiftUI
import SwiftData

struct SwipeHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var appNavigation
    @State private var selectedRoute: SwipeSessionRoute?
    @State private var showAlbumSelection = false
    @State private var pendingAlbumFilter: SwipeFilter?

    @AppStorage(AppPreferences.Key.defaultSwipeFilter) private var defaultFilterRaw: String = DefaultSwipeFilterPreference.notSwipedYet.rawValue

    // @State (not a plain let) so the actor instance survives body re-evals —
    // a View struct is recreated on every render and a stored `let` would
    // construct a fresh PhotoLibraryService (and change observer) each time
    // (APP-10). A reference type in @State is just a holder.
    @State private var photoService = PhotoLibraryService()

    private var defaultFilterPreference: DefaultSwipeFilterPreference {
        DefaultSwipeFilterPreference(rawValue: defaultFilterRaw) ?? .notSwipedYet
    }

    var body: some View {
        mainContent
        .navigationTitle("Swipe")
        .navigationDestination(item: $selectedRoute) { route in
            SwipeSessionHostView(
                route: route,
                photoService: photoService,
                modelContext: modelContext
            )
        }
        .onChange(of: appNavigation.swipeDismissRequestID) { _, _ in
            selectedRoute = nil
        }
        .onChange(of: appNavigation.pendingSwipeFilter) { _, _ in
            consumePendingFilter()
        }
        .onAppear {
            consumePendingFilter()
        }
        .sheet(isPresented: $showAlbumSelection, onDismiss: {
            // Start the session only after the sheet has fully dismissed —
            // pushing a navigationDestination while a sheet is dismissing in the
            // same update drops the push.
            if let filter = pendingAlbumFilter {
                pendingAlbumFilter = nil
                startSwipeSession(with: filter)
            }
        }) {
            SwipeAlbumPickerSheet(photoService: photoService) { albumId in
                pendingAlbumFilter = .specificAlbum(id: albumId)
            }
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                // Hero header
                heroHeader
                    .fadeSlideIn()

                // Filter cards
                VStack(spacing: Spacing.md) {
                    filterCard(
                        title: "Not Swiped Yet",
                        description: "Photos you haven't reviewed yet",
                        icon: "sparkles",
                        color: .blue,
                        filter: .notSwipedYet,
                        isDefault: defaultFilterPreference == .notSwipedYet
                    )
                    .fadeSlideIn(delay: 0.05)

                    filterCard(
                        title: "All Media",
                        description: "Every photo and video in your library",
                        icon: "photo.on.rectangle.angled",
                        color: .purple,
                        filter: .allMedia,
                        isDefault: defaultFilterPreference == .allMedia
                    )
                    .fadeSlideIn(delay: 0.1)

                    filterCard(
                        title: "Not in Any User Album",
                        description: "Photos not organized into your albums",
                        icon: "folder.badge.questionmark",
                        color: .orange,
                        filter: .notInAnyAlbum,
                        isDefault: defaultFilterPreference == .notInAnyAlbum
                    )
                    .fadeSlideIn(delay: 0.15)

                    filterCard(
                        title: "Specific Album",
                        description: "Review photos from a specific album",
                        icon: "rectangle.stack",
                        color: .teal,
                        filter: nil
                    )
                    .fadeSlideIn(delay: 0.2)
                }
                .padding(.horizontal, Spacing.lg)
            }
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                // Glow behind icon
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue.opacity(0.2), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                // Stacked card icons
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.3))
                        .frame(width: 40, height: 52)
                        .rotationEffect(.degrees(-12))
                        .offset(x: -8)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.5))
                        .frame(width: 40, height: 52)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.8))
                        .frame(width: 40, height: 52)
                        .rotationEffect(.degrees(12))
                        .offset(x: 8)
                }
            }

            VStack(spacing: Spacing.xs) {
                Text("Swipe to Organize")
                    .font(.title.bold())

                Text("Choose a filter to start reviewing your photos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                HapticHelper.impact(.light)
                startSwipeSession(with: defaultFilterPreference.swipeFilter)
            } label: {
                Label("Start with \(defaultFilterPreference.title)", systemImage: "play.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.cardSurface)
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
            }
            .scaleOnPress()
        }
        .padding(.top, Spacing.lg)
    }

    // MARK: - Filter Card

    private func filterCard(
        title: String,
        description: String,
        icon: String,
        color: Color,
        filter: SwipeFilter?,
        isDefault: Bool = false
    ) -> some View {
        Button {
            HapticHelper.impact(.light)
            if let filter {
                startSwipeSession(with: filter)
            } else {
                // The picker sheet loads its own album list on appear.
                showAlbumSelection = true
            }
        } label: {
            HStack(spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(color.gradient)
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if isDefault {
                            Text("Default")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(color)
                                .clipShape(Capsule())
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .glassCard()
        }
        .scaleOnPress()
    }

    private func startSwipeSession(with filter: SwipeFilter) {
        selectedRoute = SwipeSessionRoute(filter: filter)
    }

    /// Consumes a pending filter set by another tab (e.g., Storage → Swipe deep-link).
    private func consumePendingFilter() {
        guard let filter = appNavigation.consumePendingSwipeFilter() else { return }
        // If a previous swipe session is still mounted, clear it first so the
        // next route builds a fresh view model for the new filter.
        selectedRoute = nil
        Task { @MainActor in
            await Task.yield()
            startSwipeSession(with: filter)
        }
    }
}

extension SwipeFilter: Identifiable {
    var id: String {
        switch self {
        case .allMedia: return "allMedia"
        case .notInAnyAlbum: return "notInAnyAlbum"
        case .specificAlbum(let id): return "album_\(id)"
        case .notSwipedYet: return "notSwipedYet"
        case .screenshots: return "screenshots"
        case .customAssetIds(let ids):
            // Set.hashValue is randomized per process, so it can't be an
            // identity. Derive a stable one from the sorted identifiers
            // instead (SWIPE-10).
            return "custom_\(ids.sorted().joined(separator: ","))"
        }
    }
}
