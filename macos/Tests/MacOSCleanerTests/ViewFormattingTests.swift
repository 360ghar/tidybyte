import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Unit tests for the byte-count formatting used across views
/// (`Int64.formattedByteCount`), covering the UX-05 regression where
/// 0-byte files rendered as "Zero KB" instead of the "31 bytes" style
/// used for other small sizes.
final class ViewFormattingTests: XCTestCase {

    func testZeroBytesFormatsAsZeroBytes() {
        XCTAssertEqual(Int64(0).formattedByteCount, "0 bytes")
    }

    func testSmallByteCountsUseByteStyle() {
        XCTAssertEqual(Int64(31).formattedByteCount, "31 bytes")
        XCTAssertEqual(Int64(1024).formattedByteCount, "1 KB")
        XCTAssertEqual(Int64(1_048_576).formattedByteCount, "1 MB")
    }

    func testLargeByteCountsUseDecimalStyle() {
        XCTAssertEqual(Int64(1_200_000_000).formattedByteCount, "1.2 GB")
        XCTAssertEqual(Int64(5_000_000_000).formattedByteCount, "5 GB")
    }

    func testNegativeByteCountsRemainFormatted() {
        XCTAssertEqual(Int64(-31).formattedByteCount, "-31 bytes")
    }

    func testNonZeroValuesAreNeverZeroBytes() {
        // Regression guard: the zero special-case must not swallow tiny or
        // fractional sizes.
        XCTAssertNotEqual(Int64(1).formattedByteCount, "0 bytes")
        XCTAssertEqual(Int64(1).formattedByteCount, "1 byte")
    }
}
