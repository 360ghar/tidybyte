import CoreGraphics
import Foundation

/// Zoom/pan state for pinch-to-zoom inspection of the top swipe card.
///
/// Pure value logic so the clamping and toggle rules are unit-testable;
/// `CardView` renders `scale`/`offset` via `scaleEffect`/`offset` and feeds
/// gesture values in. While zoomed, the session's swipe drag is suspended
/// (see `SwipeSessionView`'s gesture gating) so a pan pans the photo instead
/// of committing a swipe.
struct ZoomState: Equatable {
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero

    static let maxScale: CGFloat = 5.0
    static let doubleTapScale: CGFloat = 2.5
    /// A pinch that ends below this zoom snaps back to 1x — a barely-moved
    /// pinch shouldn't latch the card into zoom mode and disable swiping.
    static let latchThreshold: CGFloat = 1.05

    var isZoomed: Bool { scale > 1.001 }

    /// Applies a pinch result, clamping scale and re-clamping pan so the
    /// image still covers the frame at the new scale.
    mutating func setScale(_ newScale: CGFloat, frame: CGSize, contentSize: CGSize? = nil) {
        scale = min(max(newScale, 1.0), Self.maxScale)
        offset = Self.clampPan(offset, scale: scale, frame: frame, contentSize: contentSize)
    }

    /// Applies a pinch drag on top of the scale captured at gesture start.
    /// Mirrors `setPan`: `MagnifyGesture` reports magnification relative to the
    /// current gesture's start (1.0), not the card's scale, so callers must
    /// capture `scale` on first-fire and pass it as `base` — applying the raw
    /// magnification directly snaps a second pinch back to ~1x.
    mutating func setPinch(base: CGFloat, magnification: CGFloat, frame: CGSize, contentSize: CGSize? = nil) {
        setScale(base * magnification, frame: frame, contentSize: contentSize)
    }

    /// Applies a pan drag on top of the offset captured at gesture start.
    mutating func setPan(base: CGSize, translation: CGSize, frame: CGSize, contentSize: CGSize? = nil) {
        offset = Self.clampPan(
            CGSize(width: base.width + translation.width, height: base.height + translation.height),
            scale: scale,
            frame: frame,
            contentSize: contentSize
        )
    }

    /// Double-tap: toggles between 1x and the double-tap zoom level.
    mutating func toggle(frame: CGSize, contentSize: CGSize? = nil) {
        if isZoomed {
            reset()
        } else {
            setScale(Self.doubleTapScale, frame: frame, contentSize: contentSize)
        }
    }

    /// Pinch ended: snap back to 1x when the pinch barely moved.
    mutating func endPinch() {
        if scale < Self.latchThreshold {
            reset()
        }
    }

    mutating func reset() {
        scale = 1.0
        offset = .zero
    }

    /// Bounds pan so no edge of the image can be pulled inside the frame.
    /// contentSize is the aspect-fill rendered size (already overflowing one axis at 1x);
    /// defaults to the frame, preserving the exact-fit assumption; limit is half the
    /// overflow of the SCALED rendered content per axis, floored at zero for degenerate frames.
    static func clampPan(_ offset: CGSize, scale: CGFloat, frame: CGSize, contentSize: CGSize? = nil) -> CGSize {
        guard scale > 1.0 else { return .zero }
        let content = contentSize ?? frame
        let limitX = max((content.width * scale - frame.width) / 2.0, 0)
        let limitY = max((content.height * scale - frame.height) / 2.0, 0)
        return CGSize(
            width: min(max(offset.width, -limitX), limitX),
            height: min(max(offset.height, -limitY), limitY)
        )
    }
}
