import SwiftUI

// MARK: - Shimmer Overlay

struct ShimmerOverlayModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geometry in
                LinearGradient(
                    colors: [
                        .clear,
                        Color.primary.opacity(0.06),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 0.6)
                .offset(x: phase * geometry.size.width)
            }
            .clipped()
        }
        .onAppear {
            // E6: guard against re-arming — each re-appearance used to stack
            // another `repeatForever` animation on `phase`, visibly speeding
            // the shimmer up. Once started, the animation persists.
            guard !reduceMotion, phase == -1 else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}

extension View {
    func shimmerOverlay() -> some View {
        modifier(ShimmerOverlayModifier())
    }
}

// MARK: - Primitives

struct SkeletonView: View {
    var cornerRadius: CGFloat = CornerRadius.small

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.cardBorder, lineWidth: 0.5)
            }
            .shimmerOverlay()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct SkeletonCircle: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.cardSurface)
            .overlay {
                Circle()
                    .strokeBorder(Color.cardBorder, lineWidth: 0.5)
            }
            .shimmerOverlay()
            .clipShape(Circle())
    }
}

struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = CornerRadius.small

    var body: some View {
        SkeletonView(cornerRadius: cornerRadius)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

struct SkeletonStatBlock: View {
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: Spacing.xs) {
            SkeletonBar(width: 50, height: 10)
            SkeletonBar(width: 60, height: 22, cornerRadius: CornerRadius.small)
            SkeletonBar(width: 40, height: 10)
        }
    }
}

struct SkeletonActionRow: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            SkeletonCircle(size: 28)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                SkeletonBar(width: 140, height: 12)
                SkeletonBar(width: 100, height: 10)
            }

            Spacer()

            SkeletonBar(width: 10, height: 14, cornerRadius: 2)
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Compositions

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            SkeletonView(cornerRadius: CornerRadius.small)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                SkeletonView()
                    .frame(width: 120, height: 14)
                SkeletonView()
                    .frame(width: 80, height: 12)
            }

            Spacer()
        }
    }
}

struct SkeletonGrid: View {
    /// Approximate column count on a compact (iPhone) width; used only to size the
    /// placeholder count. The actual layout is width-adaptive, so it reflows to match the
    /// real photo grid on iPad.
    let columns: Int
    let rows: Int

    var body: some View {
        LazyVGrid(
            columns: ResponsiveGrid.photo(spacing: Spacing.sm),
            spacing: Spacing.sm
        ) {
            ForEach(0..<(columns * rows), id: \.self) { _ in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        SkeletonView(cornerRadius: CornerRadius.small)
                    }
            }
        }
    }
}
