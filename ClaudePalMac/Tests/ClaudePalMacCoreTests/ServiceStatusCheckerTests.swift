import XCTest
@testable import ClaudePalMacCore

final class ServiceStatusCheckerTests: XCTestCase {

    func testClaudeServiceStatusOperational() {
        let status = ClaudeServiceStatus(indicator: "none", description: "All Systems Operational")
        XCTAssertTrue(status.isOperational)
        XCTAssertFalse(status.isDegraded)
        XCTAssertFalse(status.isCritical)
    }

    func testClaudeServiceStatusDegraded() {
        let status = ClaudeServiceStatus(indicator: "minor", description: "Minor Service Degradation")
        XCTAssertFalse(status.isOperational)
        XCTAssertTrue(status.isDegraded)
        XCTAssertFalse(status.isCritical)
    }

    func testClaudeServiceStatusMajor() {
        let status = ClaudeServiceStatus(indicator: "major", description: "Major Outage")
        XCTAssertFalse(status.isOperational)
        XCTAssertTrue(status.isDegraded)
        XCTAssertFalse(status.isCritical)
    }

    func testClaudeServiceStatusCritical() {
        let status = ClaudeServiceStatus(indicator: "critical", description: "Critical Outage")
        XCTAssertFalse(status.isOperational)
        XCTAssertFalse(status.isDegraded)
        XCTAssertTrue(status.isCritical)
    }

    func testLocalTokenFormatterSmall() {
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(0), "0")
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(500), "500")
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(999), "999")
    }

    func testLocalTokenFormatterThousands() {
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(1000), "1.0K")
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(1234), "1.2K")
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(9999), "10.0K")
    }

    func testLocalTokenFormatterLarge() {
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(10000), "10K")
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(123456), "123K")
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(1000000), "1.0M")
        XCTAssertEqual(LocalTokenTracker.formatTokenCount(1500000), "1.5M")
    }
}
