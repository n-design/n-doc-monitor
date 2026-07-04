import XCTest
@testable import NDocMonitor

/// Tests for `BuildMonitor`'s run-count tracking across polling cycles.
///
/// These tests simulate the lifecycle of a document build:
/// 1. latexmk appears (no lualatex yet) → run count = 0
/// 2. lualatex starts (PID 500) → run count = 1
/// 3. same lualatex still running → run count stays 1
/// 4. lualatex finishes, new one starts (PID 501) → run count = 2
/// 5. all done, latexmk disappears → document removed
@MainActor
final class BuildMonitorTests: XCTestCase {

    // MARK: - Helpers

    /// Create a document snapshot as `BuildDetector` would produce it
    /// (always with runCount = 0, since it's a point-in-time snapshot).
    private func snapshot(
        latexmkPID: pid_t = 120,
        name: String = "ADV_TDS",
        directory: String = "/repo/adv_tds",
        lualatexPID: pid_t? = nil
    ) -> DocumentBuild {
        DocumentBuild(
            id: latexmkPID,
            name: name,
            directory: directory,
            runCount: 0,
            isRunning: lualatexPID != nil,
            currentLualatexPID: lualatexPID
        )
    }

    // MARK: - Run count tracking

    func testFirstSnapshotWithNoLualatexHasZeroRuns() {
        let monitor = BuildMonitor()
        monitor.applyDocumentSnapshots([
            snapshot(lualatexPID: nil)
        ])
        XCTAssertEqual(monitor.documentBuilds.count, 1)
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 0)
    }

    func testFirstLualatexAppearsCountsAsRun1() {
        let monitor = BuildMonitor()
        monitor.applyDocumentSnapshots([
            snapshot(lualatexPID: 500)
        ])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1)
        XCTAssertTrue(monitor.documentBuilds[0].isRunning)
    }

    func testSameLualatexPIDDoesNotIncrementCount() {
        let monitor = BuildMonitor()

        // Cycle 1: lualatex 500 starts
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 500)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1)

        // Cycle 2: same PID still running
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 500)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1,
            "Same PID should not increment run count")
    }

    func testNewLualatexPIDIncrementsCount() {
        let monitor = BuildMonitor()

        // Cycle 1: lualatex 500
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 500)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1)

        // Cycle 2: lualatex 501 (new run)
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 501)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 2)
    }

    func testGapBetweenRunsPreservesCount() {
        let monitor = BuildMonitor()

        // Cycle 1: lualatex 500
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 500)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1)

        // Cycle 2: no lualatex (between runs)
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: nil)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1,
            "Count should be preserved when lualatex finishes")
        XCTAssertFalse(monitor.documentBuilds[0].isRunning)

        // Cycle 3: lualatex 501 (new run)
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 501)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 2)
    }

    func testFullLifecycleThreeRuns() {
        let monitor = BuildMonitor()

        // Run 1
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 500)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1)

        // Gap
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: nil)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1)

        // Run 2
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 501)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 2)

        // Run 3 (directly, no gap — lualatex 501 finished, 502 started
        // in the same polling interval)
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 502)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 3)
    }

    // MARK: - Multiple documents

    func testMultipleDocumentsTrackedIndependently() {
        let monitor = BuildMonitor()

        let doc1 = snapshot(latexmkPID: 120, name: "ADV_TDS",
                           directory: "/repo/adv_tds", lualatexPID: 500)
        let doc2 = snapshot(latexmkPID: 121, name: "ASE",
                           directory: "/repo/ase", lualatexPID: 600)

        // Cycle 1: both start
        monitor.applyDocumentSnapshots([doc1, doc2])
        XCTAssertEqual(monitor.documentBuilds.count, 2)
        let adv1 = monitor.documentBuilds.first { $0.name == "ADV_TDS" }
        let ase1 = monitor.documentBuilds.first { $0.name == "ASE" }
        XCTAssertEqual(adv1?.runCount, 1)
        XCTAssertEqual(ase1?.runCount, 1)

        // Cycle 2: ADV_TDS gets a new run, ASE stays same
        let doc1b = snapshot(latexmkPID: 120, name: "ADV_TDS",
                            directory: "/repo/adv_tds", lualatexPID: 501)
        monitor.applyDocumentSnapshots([doc1b, doc2])
        let adv2 = monitor.documentBuilds.first { $0.name == "ADV_TDS" }
        let ase2 = monitor.documentBuilds.first { $0.name == "ASE" }
        XCTAssertEqual(adv2?.runCount, 2)
        XCTAssertEqual(ase2?.runCount, 1)
    }

    // MARK: - Document disappears

    func testDocumentDisappearsCleansUpTracking() {
        let monitor = BuildMonitor()

        // Cycle 1: document present
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 500)])
        XCTAssertEqual(monitor.documentBuilds.count, 1)

        // Cycle 2: document gone (build finished)
        monitor.applyDocumentSnapshots([])
        XCTAssertTrue(monitor.documentBuilds.isEmpty)

        // Cycle 3: same latexmk PID reappears (new build) — should
        // start fresh, not carry over stale counts.
        monitor.applyDocumentSnapshots([snapshot(lualatexPID: 700)])
        XCTAssertEqual(monitor.documentBuilds[0].runCount, 1,
            "Should start fresh after document disappeared and reappeared")
    }
}
