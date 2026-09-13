import XCTest
@testable import Tidybyte

// MARK: - Fixtures

private func makeAsset(
    id: String,
    fileSize: Int64 = 8_000_000,
    pixelWidth: Int = 4032,
    pixelHeight: Int = 3024,
    locallyAvailable: Bool = true,
    isFavorite: Bool = false,
    creationDate: Date? = .now
) -> AssetSummary {
    AssetSummary(
        id: id,
        mediaType: .photo,
        creationDate: creationDate,
        modificationDate: creationDate,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        duration: 0,
        fileSize: fileSize,
        filename: "\(id).jpg",
        isFavorite: isFavorite,
        isBurst: false,
        burstIdentifier: nil,
        isLivePhoto: false,
        isScreenshot: false,
        isLocallyAvailable: locallyAvailable
    )
}

/// Deterministic pseudo-random 64-bit hashes (no Foundation randomness).
private func pseudoRandomHashes(count: Int) -> [String: UInt64] {
    var state: UInt64 = 0x9E3779B97F4A7C15
    var result: [String: UInt64] = [:]
    for index in 0..<count {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        result["asset-\(index)"] = state
    }
    return result
}

/// Greedy grouping with the same semantics as `findVisualDuplicates`'s
/// comparison phase: anchors in order, first-match-wins membership.
/// `candidates` mirrors the pre-filter — when non-nil, pairs outside it are
/// never compared.
private func greedyGroups(
    hashes: [String: UInt64],
    similar: (UInt64, UInt64) -> Bool,
    candidates: Set<PairKey>?
) -> [[String]] {
    let ids = hashes.keys.sorted()
    var visited = Set<String>()
    var groups: [[String]] = []
    for anchor in ids {
        guard !visited.contains(anchor) else { continue }
        var group = [anchor]
        visited.insert(anchor)
        for other in ids where other > anchor && !visited.contains(other) {
            if let candidates, !candidates.contains(PairKey(anchor, other)) {
                continue
            }
            if similar(hashes[anchor]!, hashes[other]!) {
                group.append(other)
                visited.insert(other)
            }
        }
        if group.count > 1 { groups.append(group) }
    }
    return groups
}

// MARK: - DUP-01 / DUP-12: visual scan pre-filter

@MainActor
final class DuplicatesRegressionTests: XCTestCase {

    // MARK: Hash

    func testHash64IsStableForIdenticalGrids() {
        let grid: [UInt8] = (0..<64).map { UInt8(($0 * 4) % 256) }
        XCTAssertEqual(VisualPreFilter.hash64(from: grid), VisualPreFilter.hash64(from: grid))
    }

    func testHash64DistinguishesVeryDifferentGrids() {
        let flat: [UInt8] = Array(repeating: 0, count: 64)
        let checkerboard: [UInt8] = (0..<64).map { $0 % 2 == 0 ? 0 : 255 }
        let distance = VisualPreFilter.hammingDistance(
            VisualPreFilter.hash64(from: flat),
            VisualPreFilter.hash64(from: checkerboard)
        )
        XCTAssertGreaterThan(distance, VisualPreFilter.maxHammingDistance)
    }

    func testLuminanceGridFromCGImage() throws {
        let width = 16
        let height = 16
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let grid = try XCTUnwrap(VisualPreFilter.luminanceGrid(from: image))
        XCTAssertEqual(grid.count, 64)
        XCTAssertTrue(grid.allSatisfy { $0 > 200 })
        // Same image, same grid — the pre-filter hash is deterministic.
        XCTAssertEqual(grid, VisualPreFilter.luminanceGrid(from: image))
    }

    // MARK: Hamming bound

    func testShouldCompareAdmitsWithinBoundPairs() {
        let a: UInt64 = 0xAAAAAAAAAAAAAAAA
        let identical = a
        let nearThreshold = a ^ 0b11111 // 5 bits differ
        let atBound = a ^ 0xFFF // 12 bits differ — exactly at the bound
        XCTAssertTrue(VisualPreFilter.shouldCompare(a, identical))
        XCTAssertTrue(VisualPreFilter.shouldCompare(a, nearThreshold))
        XCTAssertTrue(VisualPreFilter.shouldCompare(a, atBound))
    }

    func testShouldCompareRejectsFarPairs() {
        let a: UInt64 = 0xAAAAAAAAAAAAAAAA
        XCTAssertFalse(VisualPreFilter.shouldCompare(a, ~a))
        let pastBound = a ^ 0x1FFF // 13 bits differ — one past the bound
        XCTAssertFalse(VisualPreFilter.shouldCompare(a, pastBound))
    }

    func testShouldCompareNeverPrunesSentinel() {
        // The 0 sentinel carries no hash information — it must never be pruned
        // by the cheap gate, matching `candidatePairs`'s sentinel pairing.
        XCTAssertTrue(VisualPreFilter.shouldCompare(0, 0xAAAAAAAAAAAAAAAA))
        XCTAssertTrue(VisualPreFilter.shouldCompare(0xAAAAAAAAAAAAAAAA, 0))
        XCTAssertTrue(VisualPreFilter.shouldCompare(0, ~UInt64(0)))
        XCTAssertTrue(VisualPreFilter.shouldCompare(0, 0))
    }

    func testPairKeyIsOrderIndependent() {
        XCTAssertEqual(PairKey("b", "a"), PairKey("a", "b"))
        XCTAssertEqual(PairKey("b", "a").hashValue, PairKey("a", "b").hashValue)
    }

    // MARK: Candidate-pair bucketing

    func testCandidatePairsAdmitsEveryWithinBoundPair() {
        let hashes = pseudoRandomHashes(count: 40)
        let candidates = VisualPreFilter.candidatePairs(hashes)
        for (a, hashA) in hashes {
            for (b, hashB) in hashes where a < b {
                if VisualPreFilter.hammingDistance(hashA, hashB) <= VisualPreFilter.maxHammingDistance {
                    XCTAssertTrue(
                        candidates.contains(PairKey(a, b)),
                        "pre-filter must admit pair (\(a), \(b)) with hamming \(VisualPreFilter.hammingDistance(hashA, hashB))"
                    )
                }
            }
        }
    }

    func testCandidatePairsRejectsFarPair() {
        let a: UInt64 = 0xAAAAAAAAAAAAAAAA
        // 16 differing bits spread 2 per 8-bit chunk — every chunk differs by
        // at least 2 bits, so no radius-1 bucket collision can ever surface
        // the pair, and the total (16) also exceeds the 12-bit bound.
        let mask: UInt64 = 0xC0C0C0C0C0C0C0C0
        let far = a ^ mask
        XCTAssertEqual(VisualPreFilter.hammingDistance(a, far), 16)
        let hashes = ["a": a, "far": far]
        XCTAssertFalse(VisualPreFilter.candidatePairs(hashes).contains(PairKey("a", "far")))
    }

    func testCandidatePairsAdmitsPairAtBound() {
        let a: UInt64 = 0xAAAAAAAAAAAAAAAA
        // Exactly 12 differing bits — the boundary of the bound. The pair must
        // survive the bucketing (some 8-bit chunk differs by <= 1 bit) AND the
        // Hamming re-check (<= 12).
        let atBound = a ^ 0x0FFF
        XCTAssertEqual(VisualPreFilter.hammingDistance(a, atBound), 12)
        let hashes = ["a": a, "b": atBound]
        XCTAssertTrue(VisualPreFilter.candidatePairs(hashes).contains(PairKey("a", "b")))
    }

    func testCandidatePairsRejectsPairJustPastBound() {
        let a: UInt64 = 0xAAAAAAAAAAAAAAAA
        let pastBound = a ^ 0x1FFF // 13 bits — one past the bound
        XCTAssertEqual(VisualPreFilter.hammingDistance(a, pastBound), 13)
        let hashes = ["a": a, "b": pastBound]
        XCTAssertFalse(VisualPreFilter.candidatePairs(hashes).contains(PairKey("a", "b")))
    }

    // MARK: Sentinel (no-hash) handling

    func testCandidatePairsWithSentinelHashPairsWithEverything() {
        let a: UInt64 = 0xAAAAAAAAAAAAAAAA
        let far = ~a
        let hashes = ["normal": a, "no-hash": 0, "far": far]
        let candidates = VisualPreFilter.candidatePairs(hashes)

        // An asset whose luminance grid failed (hash 0) carries no information
        // and must never be pruned — not even against a hash that is maximally
        // far from everything else.
        XCTAssertTrue(candidates.contains(PairKey("no-hash", "normal")))
        XCTAssertTrue(candidates.contains(PairKey("no-hash", "far")), "a no-hash asset must never be pruned")
        // Two hashed assets far apart stay pruned as before.
        XCTAssertFalse(candidates.contains(PairKey("normal", "far")))
    }

    func testHash64IsNeverZeroForNonEmptyGrid() {
        // The 0 sentinel must never be produced naturally: uniform grids hash
        // to all-ones (every cell >= the grid mean), and a varied grid has a
        // mix of bits.
        XCTAssertEqual(VisualPreFilter.hash64(from: Array(repeating: 0, count: 64)), UInt64.max)
        XCTAssertEqual(VisualPreFilter.hash64(from: Array(repeating: 255, count: 64)), UInt64.max)
        let varied: [UInt8] = (0..<64).map { UInt8(($0 * 4) % 256) }
        let variedHash = VisualPreFilter.hash64(from: varied)
        XCTAssertNotEqual(variedHash, 0)
        XCTAssertNotEqual(variedHash, UInt64.max)
    }

    // MARK: Group equivalence with the old pairwise scan

    func testPreFilteredGroupingMatchesOldPairwiseForIdenticalPair() {
        let a: UInt64 = 0xAAAAAAAAAAAAAAAA
        let hashes = ["a": a, "b": a, "c": ~a]
        let candidates = VisualPreFilter.candidatePairs(hashes)
        let similar: (UInt64, UInt64) -> Bool = { VisualPreFilter.shouldCompare($0, $1) }

        let oldGroups = greedyGroups(hashes: hashes, similar: similar, candidates: nil)
        let newGroups = greedyGroups(hashes: hashes, similar: similar, candidates: candidates)

        XCTAssertEqual(Set(oldGroups), Set([["a", "b"]]))
        XCTAssertEqual(Set(newGroups), Set(oldGroups))
    }

    func testPreFilteredGroupingMatchesOldPairwiseForNearThresholdPair() {
        let a: UInt64 = 0xAAAAAAAAAAAAAAAA
        let near = a ^ 0b11111 // hamming 5 — near the pre-filter bound
        let hashes = ["a": a, "b": near, "c": ~a]
        let candidates = VisualPreFilter.candidatePairs(hashes)
        let similar: (UInt64, UInt64) -> Bool = { VisualPreFilter.shouldCompare($0, $1) }

        let oldGroups = greedyGroups(hashes: hashes, similar: similar, candidates: nil)
        let newGroups = greedyGroups(hashes: hashes, similar: similar, candidates: candidates)

        XCTAssertEqual(Set(oldGroups), Set([["a", "b"]]))
        XCTAssertEqual(Set(newGroups), Set(oldGroups))
    }

    func testPreFilteredGroupingMatchesOldPairwiseAcrossRandomSet() {
        let hashes = pseudoRandomHashes(count: 30)
        let candidates = VisualPreFilter.candidatePairs(hashes)
        let similar: (UInt64, UInt64) -> Bool = { VisualPreFilter.shouldCompare($0, $1) }

        let oldGroups = greedyGroups(hashes: hashes, similar: similar, candidates: nil)
        let newGroups = greedyGroups(hashes: hashes, similar: similar, candidates: candidates)

        // The candidate set is a superset of all within-bound pairs, so the
        // pre-filter must never change which groups the pairwise scan produces.
        XCTAssertEqual(Set(newGroups), Set(oldGroups))
    }

    // MARK: DUP-03: iCloud-only skipping

    func testSplitByLocalAvailabilityCountsSkipped() {
        let assets = [
            makeAsset(id: "local"),
            makeAsset(id: "icloud-1", locallyAvailable: false),
            makeAsset(id: "icloud-2", locallyAvailable: false)
        ]
        let (candidates, skipped) = DuplicateDetectionService.splitByLocalAvailability(assets)
        XCTAssertEqual(skipped, 2)
        XCTAssertEqual(Set(candidates.map(\.id)), ["local"])
    }

    func testSplitByLocalAvailabilityAllLocal() {
        let assets = [makeAsset(id: "a"), makeAsset(id: "b")]
        let (candidates, skipped) = DuplicateDetectionService.splitByLocalAvailability(assets)
        XCTAssertEqual(skipped, 0)
        XCTAssertEqual(Set(candidates.map(\.id)), ["a", "b"])
    }

    // MARK: DUP-04: group-scoped delete and select-all

    func testNonBestAssetIdsTargetsGroupSelection() {
        let group = DuplicateGroup(
            id: "group",
            assets: [makeAsset(id: "best"), makeAsset(id: "second"), makeAsset(id: "third")],
            bestAssetId: "best",
            type: .exact
        )
        XCTAssertEqual(DuplicateFinderViewModel.nonBestAssetIds(in: group), ["second", "third"])
    }

    func testSelectAllAndDeselectAllAcrossGroups() {
        let viewModel = DuplicateFinderViewModel()
        viewModel.exactGroups = [
            DuplicateGroup(id: "g1", assets: [makeAsset(id: "a"), makeAsset(id: "b")], bestAssetId: "a", type: .exact),
            DuplicateGroup(id: "g2", assets: [makeAsset(id: "c"), makeAsset(id: "d")], bestAssetId: "c", type: .exact)
        ]
        viewModel.scanType = .exact

        XCTAssertFalse(viewModel.allSelectedForDeletion)
        // C7: Select All targets only the NON-BEST assets — keepers are never
        // armed, so a single confirmation can't delete every copy of a photo.
        viewModel.selectAllForDeletion()
        XCTAssertEqual(viewModel.selectedForDeletion, ["b", "d"])
        XCTAssertTrue(viewModel.allSelectedForDeletion)

        viewModel.deselectAllForDeletion()
        XCTAssertTrue(viewModel.selectedForDeletion.isEmpty)
        XCTAssertFalse(viewModel.allSelectedForDeletion)
    }

    /// C7 invariant: keepers are never part of the select-all set.
    func testAllSelectedExcludesKeepers() {
        let viewModel = DuplicateFinderViewModel()
        viewModel.exactGroups = [
            DuplicateGroup(id: "g1", assets: [makeAsset(id: "a"), makeAsset(id: "b")], bestAssetId: "a", type: .exact)
        ]
        viewModel.scanType = .exact

        viewModel.selectAllForDeletion()
        XCTAssertEqual(viewModel.selectedForDeletion, ["b"])
        // All *deletable* (non-best) assets are selected.
        XCTAssertTrue(viewModel.allSelectedForDeletion)
        XCTAssertFalse(viewModel.selectedForDeletion.contains("a"), "the keeper is never armed by select-all")
    }

    func testDeletedCountStartsAtZero() {
        let viewModel = DuplicateFinderViewModel()
        XCTAssertEqual(viewModel.deletedCount, 0)
    }

    // MARK: DUP-07: .all de-duplication

    func testAllScanDropsExactClaimedAssetsFromVisualGroups() {
        let exact = DuplicateGroup(
            id: "exact",
            assets: [makeAsset(id: "a"), makeAsset(id: "b")],
            bestAssetId: "a",
            type: .exact
        )
        let visual = DuplicateGroup(
            id: "visual",
            assets: [makeAsset(id: "b"), makeAsset(id: "c"), makeAsset(id: "d")],
            bestAssetId: "d",
            type: .visual
        )
        let result = DuplicateFinderViewModel.deduplicateVisualGroups(
            exactGroups: [exact],
            visualGroups: [visual]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(Set(result[0].assets.map(\.id)), ["c", "d"])
        XCTAssertEqual(result[0].bestAssetId, "d") // keeper survived the claim
    }

    func testAllScanDropsVisualGroupThatCollapsesBelowTwo() {
        let exact = DuplicateGroup(
            id: "exact",
            assets: [makeAsset(id: "a"), makeAsset(id: "b")],
            bestAssetId: "a",
            type: .exact
        )
        let visual = DuplicateGroup(
            id: "visual",
            assets: [makeAsset(id: "b"), makeAsset(id: "c")],
            bestAssetId: "c",
            type: .visual
        )
        let result = DuplicateFinderViewModel.deduplicateVisualGroups(
            exactGroups: [exact],
            visualGroups: [visual]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testAllScanRepicksVisualBestWhenClaimedByExactGroup() {
        let exact = DuplicateGroup(
            id: "exact",
            assets: [makeAsset(id: "a"), makeAsset(id: "b")],
            bestAssetId: "a",
            type: .exact
        )
        // Three members so two survive the exact-claim; the visual best ("b")
        // is claimed by the exact group and must be re-picked from survivors.
        let visual = DuplicateGroup(
            id: "visual",
            assets: [
                makeAsset(id: "b", pixelWidth: 100, pixelHeight: 100),
                makeAsset(id: "c", pixelWidth: 200, pixelHeight: 200),
                makeAsset(id: "d", pixelWidth: 300, pixelHeight: 300)
            ],
            bestAssetId: "b", // claimed by the exact group
            type: .visual
        )
        let result = DuplicateFinderViewModel.deduplicateVisualGroups(
            exactGroups: [exact],
            visualGroups: [visual]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].assets.map(\.id), ["c", "d"], "claimed asset must be dropped")
        XCTAssertEqual(result[0].bestAssetId, "d", "BestAssetSelector re-pick from survivors")
    }

    // MARK: DUP-10 / de-slop: shared selection semantics

    func testSelectionStateSetBestSwap() {
        var state = SelectionState(ids: ["new-best"])
        state.setBest(newBest: "new-best", oldBest: "old-best")
        XCTAssertEqual(state.ids, ["old-best"])

        // No-op when the best doesn't change.
        state.setBest(newBest: "old-best", oldBest: "old-best")
        XCTAssertEqual(state.ids, ["old-best"])
    }

    func testSelectionStateSelectNonBest() {
        var state = SelectionState()
        state.selectNonBest(
            assets: [makeAsset(id: "best"), makeAsset(id: "x"), makeAsset(id: "y")],
            bestAssetId: "best"
        )
        XCTAssertEqual(state.ids, ["x", "y"])
    }
}
