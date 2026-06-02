import Foundation

/// Carries a non-`Sendable` value across an actor/isolation boundary under
/// `complete` strict concurrency.
///
/// PhotoKit/AVFoundation hand back reference types that aren't `Sendable`
/// (e.g. `AVPlayerItem`). When such a value is produced inside an `actor` and
/// returned to a `@MainActor` caller, the compiler flags the crossing. These
/// objects are safe to hand off because the producer keeps no shared mutable
/// reference after returning, so we wrap them in this box — which *is*
/// `Sendable` — and the receiver unwraps `value` in its own isolation domain.
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}
