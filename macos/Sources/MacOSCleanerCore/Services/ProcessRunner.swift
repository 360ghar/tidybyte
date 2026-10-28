import Foundation
import os

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    /// True when a stream exceeded the capture cap, so the output is a
    /// prefix of the real output and must not be treated as complete.
    let truncated: Bool

    init(exitCode: Int32, stdout: String, stderr: String, truncated: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.truncated = truncated
    }
}

enum ProcessRunner {
    /// Per-stream cap for captured output. Output beyond this is still drained
    /// (so the child never blocks on a full pipe buffer) but discarded, with a
    /// truncation note appended so callers know the output is incomplete.
    static let maxCapturedBytesPerStream = 1_048_576
    private static let readChunkSize = 16_384
    private static let truncationNote = "\n[ProcessRunner: output exceeded \(maxCapturedBytesPerStream) bytes; only the first portion is captured]"

    static func run(_ command: URL, arguments: [String], timeout: TimeInterval) async -> ProcessResult {
        let process = Process()
        process.executableURL = command
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let handle = ProcessExecutionHandle(process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        var startError: String?
        var timeoutTask: Task<Void, Never>?

        // Drain stdout and stderr concurrently WHILE the process runs. Reading
        // the pipes only after the process exits deadlocks the child once a
        // 64 KB pipe buffer fills, which previously forced a kill via timeout.
        // Each drain runs in its own Task and keeps consuming until EOF, so
        // producing large output can never block or kill the child.
        let stdoutTask = Task { drain(handle.stdoutPipe.fileHandleForReading) }
        let stderrTask = Task { drain(handle.stderrPipe.fileHandleForReading) }

        let exitCode = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                startError = error.localizedDescription
                continuation.resume(returning: 1)
                return
            }

            timeoutTask = Task { [handle] in
                try? await Task.sleep(for: .seconds(timeout))
                if handle.process.isRunning {
                    handle.markTimedOut()
                    handle.process.terminate()
                }
            }
        }

        timeoutTask?.cancel()

        if let startError {
            // The process never started, so the pipes will never reach EOF on
            // their own. Closing BOTH ends unblocks the drain tasks: the read-end
            // close makes any pending read fail, and dropping the write end
            // guarantees no reader can block forever waiting for data.
            try? handle.stdoutPipe.fileHandleForReading.close()
            try? handle.stderrPipe.fileHandleForReading.close()
            try? handle.stdoutPipe.fileHandleForWriting.close()
            try? handle.stderrPipe.fileHandleForWriting.close()
            _ = await stdoutTask.value
            _ = await stderrTask.value
            return ProcessResult(exitCode: 1, stdout: "", stderr: startError)
        }

        let stdoutStr = String(data: await stdoutTask.value.data, encoding: .utf8) ?? ""
        let stderrDrained = await stderrTask.value
        let stderrStr = String(data: stderrDrained.data, encoding: .utf8) ?? ""
        let truncated = (await stdoutTask.value).capped || stderrDrained.capped

        if handle.didTimeOut {
            return ProcessResult(
                exitCode: 124, stdout: stdoutStr,
                stderr: "Command timed out after \(Int(timeout)) seconds.",
                truncated: truncated)
        }
        return ProcessResult(exitCode: exitCode, stdout: stdoutStr, stderr: stderrStr, truncated: truncated)
    }

    private struct DrainedOutput: Sendable {
        var data = Data()
        var capped = false
    }

    /// Reads a pipe until EOF in small chunks so a full buffer never blocks the
    /// child. Captures at most `maxCapturedBytesPerStream` bytes and keeps
    /// discarding the rest, appending a truncation note when output was cut.
    private static func drain(_ fileHandle: FileHandle) -> DrainedOutput {
        var output = DrainedOutput()
        while let chunk = try? fileHandle.read(upToCount: readChunkSize), !chunk.isEmpty {
            if output.data.count >= maxCapturedBytesPerStream {
                output.capped = true
                continue
            }
            let remaining = maxCapturedBytesPerStream - output.data.count
            output.data.append(chunk.prefix(remaining))
            if chunk.count > remaining {
                output.capped = true
            }
        }
        if output.capped {
            output.data.append(Data(truncationNote.utf8))
        }
        return output
    }
}

/// Thread-safe handle for process execution state.
/// Uses `OSAllocatedUnfairLock` for safe concurrent access to the timeout flag.
private struct ProcessExecutionHandle: Sendable {
    let process: Process
    let stdoutPipe: Pipe
    let stderrPipe: Pipe
    private let stateLock = OSAllocatedUnfairLock(initialState: false)

    var didTimeOut: Bool {
        stateLock.withLock { $0 }
    }

    init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    func markTimedOut() {
        stateLock.withLock { $0 = true }
    }
}
