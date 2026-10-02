import Foundation
import XCTest
@testable import StepquestKit

final class RandomTests: XCTestCase {
    func testSplitMix64ReferenceValues() {
        // Reference outputs of SplitMix64 seeded with 0.
        var rng = SplitMix64(seed: 0)
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(rng.next(), 0x6E78_9E6A_A1B9_65F4)
        XCTAssertEqual(rng.next(), 0x06C4_5D18_8009_454F)
    }

    func testDeterministicForSameSeed() {
        var a = SplitMix64(seed: 1234)
        var b = SplitMix64(seed: 1234)
        for _ in 0..<1000 { XCTAssertEqual(a.next(), b.next()) }
        var c = SplitMix64(seed: 1235)
        XCTAssertNotEqual(SplitMix64(seed: 1234).state, c.state)
        XCTAssertNotEqual(a.next(), c.next())
    }

    func testUnitAndBoundedRanges() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<10_000 {
            let u = rng.nextUnit()
            XCTAssertGreaterThanOrEqual(u, 0)
            XCTAssertLessThan(u, 1)
            let i = rng.nextInt(below: 3)
            XCTAssertTrue((0..<3).contains(i))
        }
    }

    func testChanceExtremesAndRate() {
        var rng = SplitMix64(seed: 99)
        XCTAssertFalse(rng.chance(0))
        XCTAssertTrue(rng.chance(1))
        let hits = (0..<20_000).filter { _ in rng.chance(0.25) }.count
        XCTAssertEqual(Double(hits) / 20_000, 0.25, accuracy: 0.02)
    }

    func testWeightedPickFollowsWeights() {
        var rng = SplitMix64(seed: 5)
        var counts = [String: Int]()
        let items = [("a", 3.0), ("b", 1.0), ("zero", 0.0)]
        for _ in 0..<40_000 {
            let p = rng.weightedPick(items) { $0.1 }!
            counts[p.0, default: 0] += 1
        }
        XCTAssertNil(counts["zero"])
        XCTAssertEqual(Double(counts["a"]!) / 40_000, 0.75, accuracy: 0.02)
        XCTAssertNil(rng.weightedPick([("x", 0.0)]) { $0.1 })
    }

    func testWorksWithStandardLibraryAPIs() {
        var rng = SplitMix64(seed: 1)
        let x = Int.random(in: 1...6, using: &rng)
        XCTAssertTrue((1...6).contains(x))
        XCTAssertEqual([1, 2, 3].shuffled(using: &rng).sorted(), [1, 2, 3])
    }

    func testCodableRoundTripPreservesFullState() throws {
        var rng = SplitMix64(seed: UInt64.max - 3)
        _ = rng.next()
        let data = try JSONEncoder().encode(rng)
        var decoded = try JSONDecoder().decode(SplitMix64.self, from: data)
        XCTAssertEqual(decoded, rng)
        XCTAssertEqual(decoded.next(), rng.next())
    }

    func testIdentifierFormat() {
        var rng = SplitMix64(seed: 3)
        let id = rng.nextIdentifier()
        XCTAssertEqual(id.count, 16)
        XCTAssertNotEqual(id, rng.nextIdentifier())
    }
}
