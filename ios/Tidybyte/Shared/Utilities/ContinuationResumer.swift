import Foundation

/// Thread-safe, resume-exactly-once wrapper around a `CheckedContinuation`.
///
/// PhotoKit / AVFoundation completion handlers can fire on arbitrary threads and,
/// for some requests, more than once (e.g. `PHImageManager` delivers a degraded
/// placeholder followed by the full result). Resuming a `CheckedContinuation`
/// twice traps, and never resuming it hangs the awaiting task forever. This box
/// guarantees a single resume and runs an optional cleanup hook (used to cancel
/// the in-flight request and any timeout) on the first resume.
final class ContinuationResumer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var continuation: CheckedContinuation<T, Never>?

    /// Invoked exactly once, on the first `resume(_:)`. Set this after creating
    /// the resumer to cancel the underlying request and/or timeout task. Not
    /// `@Sendable` so it can capture thread-safe-but-non-`Sendable` request
    /// managers (e.g. `PHImageManager`); the box itself is `@unchecked Sendable`.
    var onResume: (() -> Void)?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    /// Resumes the continuation with `value` if it has not already been resumed.
    /// Subsequent calls are no-ops.
    func resume(_ value: sending T) {
        lock.lock()
        guard !resumed, let continuation else {
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        let cleanup = onResume
        onResume = nil
        lock.unlock()

        cleanup?()
        continuation.resume(returning: value)
    }
}

/// Throwing counterpart of `ContinuationResumer`, for `withCheckedThrowingContinuation`.
final class ThrowingContinuationResumer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var continuation: CheckedContinuation<T, Error>?

    var onResume: (() -> Void)?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.lock()
        guard !resumed, let continuation else {
            lock.unlock()
            return nil
        }
        resumed = true
        self.continuation = nil
        let cleanup = onResume
        onResume = nil
        lock.unlock()
        cleanup?()
        return continuation
    }

    func resume(returning value: sending T) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }
}
