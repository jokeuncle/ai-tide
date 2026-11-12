import Foundation
import TideCore

// Standalone runner: Command Line Tools installs no XCTest framework on this machine.
private var failures = 0
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected)") }
}
private func XCTAssertNil<T>(_ actual: T?, file: StaticString = #filePath, line: UInt = #line) {
    if actual != nil { failures += 1; print("FAIL \(file):\(line): expected nil") }
}
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); failures += 1; print("FAIL \(file):\(line): expected error") } catch {}
}

final class TrafficTests {
    func testParsesPIDFromLastDotAndUsesHeaderOrder() throws {
        let result = try NettopParser.parse(",bytes_out,extra,bytes_in,\nCodex.helper.42,120,x,400,\n\"A, B.9\",7,x,11,\n")
        XCTAssertEqual(result, [.init(pid: 42, received: 400, sent: 120), .init(pid: 9, received: 11, sent: 7)])
    }
    func testRejectsBrokenCountersInsteadOfDisplayingZero() {
        XCTAssertThrowsError(try NettopParser.parse(",bytes_in,bytes_out,\nclaude.42,garbage,12,\n"))
        XCTAssertThrowsError(try NettopParser.parse(""))
        XCTAssertThrowsError(try NettopParser.parse(",bytes_in,\nclaude.42,30,\n"))
    }
    func testHeaderOnlyMeansNoVisibleSockets() throws {
        XCTAssertEqual(try NettopParser.parse(",bytes_in,bytes_out,\n"), [])
    }
    func testRejectsDuplicatePIDsAndNegativeCounts() {
        XCTAssertThrowsError(try NettopParser.parse(",bytes_in,bytes_out,\na.9,2,3,\na.9,2,3,\n"))
        XCTAssertThrowsError(try NettopParser.parse(",bytes_in,bytes_out,\na.9,-2,3,\n"))
    }
    func testSignaturePolicyRejectsNameSpoofingAndUnrelatedVendorTools() {
        XCTAssertNil(IdentityPolicy.classify(team: "EVIL", identifier: "com.anthropic.claude-code", valid: true))
        XCTAssertNil(IdentityPolicy.classify(team: "Q6L2SF6YDW", identifier: "com.anthropic.claude-code", valid: false))
        XCTAssertNil(IdentityPolicy.classify(team: "2DC432GLL2", identifier: "node", valid: true))
        XCTAssertNil(IdentityPolicy.classify(team: "2DC432GLL2", identifier: "com.openai.codex.evil", valid: true))
        XCTAssertEqual(IdentityPolicy.classify(team: "Q6L2SF6YDW", identifier: "com.anthropic.claude-code", valid: true), .claudeCode)
        XCTAssertEqual(IdentityPolicy.classify(team: "2DC432GLL2", identifier: "com.openai.codex.helper", valid: true), .codex)
        XCTAssertEqual(IdentityPolicy.classify(team: "2DC432GLL2", identifier: "com.openai.chat", valid: true), .chatGPT)
    }
    private func identity(_ birth: UInt64 = 1, path: String = "/verified/claude") -> ProcessIdentity {
        .init(pid: 42, birth: birth, path: path, team: "Q6L2SF6YDW", signingID: "com.anthropic.claude-code", client: .claudeCode)
    }
    func testFirstReadingIsBaselineAndRateUsesActualElapsedTime() {
        var accumulator = TrafficAccumulator()
        XCTAssertNil(accumulator.observe(.init(pid: 42, received: 1_000, sent: 100), identity: identity(), at: 10))
        XCTAssertEqual(accumulator.observe(.init(pid: 42, received: 1_600, sent: 180), identity: identity(), at: 12), .init(received: 600, sent: 80, elapsed: 2))
    }
    func testReusedPIDAndChangedExecutableNeverInheritTraffic() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.observe(.init(pid: 42, received: 100, sent: 100), identity: identity(), at: 1)
        XCTAssertNil(accumulator.observe(.init(pid: 42, received: 900, sent: 900), identity: identity(2), at: 2))
        XCTAssertNil(accumulator.observe(.init(pid: 42, received: 990, sent: 990), identity: identity(2, path: "/other/claude"), at: 3))
    }
    func testCounterResetRebaselinesWithoutInventingBytes() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.observe(.init(pid: 42, received: 1_000, sent: 500), identity: identity(), at: 1)
        XCTAssertNil(accumulator.observe(.init(pid: 42, received: 10, sent: 5), identity: identity(), at: 2))
        XCTAssertEqual(accumulator.observe(.init(pid: 42, received: 30, sent: 9), identity: identity(), at: 3), .init(received: 20, sent: 4, elapsed: 1))
    }
    func testMissingSampleBreaksBaselineInsteadOfSmearingActivity() {
        var accumulator = TrafficAccumulator()
        _ = accumulator.observe(.init(pid: 42, received: 100, sent: 50), identity: identity(), at: 1)
        accumulator.retain([])
        XCTAssertNil(accumulator.observe(.init(pid: 42, received: 800, sent: 90), identity: identity(), at: 9))
    }
}

@main struct Runner {
    static func main() {
        let suite = TrafficTests()
        let tests: [(String, () throws -> Void)] = [
            ("header order / quoted name", suite.testParsesPIDFromLastDotAndUsesHeaderOrder),
            ("corrupt output", suite.testRejectsBrokenCountersInsteadOfDisplayingZero),
            ("no visible sockets", suite.testHeaderOnlyMeansNoVisibleSockets),
            ("duplicate PID / negative counter", suite.testRejectsDuplicatePIDsAndNegativeCounts),
            ("signature spoofing", suite.testSignaturePolicyRejectsNameSpoofingAndUnrelatedVendorTools),
            ("baseline / elapsed time", suite.testFirstReadingIsBaselineAndRateUsesActualElapsedTime),
            ("PID reuse / executable change", suite.testReusedPIDAndChangedExecutableNeverInheritTraffic),
            ("counter reset", suite.testCounterResetRebaselinesWithoutInventingBytes),
            ("missing data", suite.testMissingSampleBreaksBaselineInsteadOfSmearingActivity)
        ]
        for (name, test) in tests {
            let before = failures
            do { try test() } catch { failures += 1; print("FAIL \(name): \(error)") }
            if failures == before { print("PASS \(name)") }
        }
        print("\(tests.count) cases, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
