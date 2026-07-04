import XCTest
@testable import NDocMonitor

/// Step 7: robustness and edge-case tests.
///
/// These tests exercise scenarios that occur in real-world usage:
/// - Multiple n-doc repositories building simultaneously.
/// - Processes dying unexpectedly (stale entry cleanup).
/// - Build→idle transitions and the "completed" summary.
/// - Rapid start/stop cycling.

// MARK: - BuildDetector edge cases

final class BuildDetectorRobustnessTests: XCTestCase {

    private func proc(
        _ pid: pid_t,
        ppid: pid_t = 1,
        name: String,
        exec: String? = nil,
        cwd: String? = nil
    ) -> NDocMonitor.ProcessInfo {
        NDocMonitor.ProcessInfo(
            pid: pid,
            ppid: ppid,
            name: name,
            executablePath: exec ?? "/usr/bin/\(name)",
            currentDirectory: cwd
        )
    }

    private func tree(from procs: [NDocMonitor.ProcessInfo]) -> [pid_t: [pid_t]] {
        var t: [pid_t: [pid_t]] = [:]
        for p in procs {
            t[p.ppid, default: []].append(p.pid)
        }
        return t
    }

    // MARK: - Multiple n-doc repos

    func testDetectsTwoReposSimultaneously() {
        let processes = [
            proc(100, name: "make", cwd: "/repos/project-a"),
            proc(200, name: "make", cwd: "/repos/project-b"),
        ]
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: { _ in true }
        )
        XCTAssertEqual(builds.count, 2)
        let paths = Set(builds.map(\.repoPath))
        XCTAssertEqual(paths, ["/repos/project-a", "/repos/project-b"])
    }

    func testTwoReposWithSeparateDocumentTrees() {
        let procs = [
            // Repo A
            proc(100, ppid: 1,   name: "make",   cwd: "/repos/a"),
            proc(110, ppid: 100, name: "gmake",  cwd: "/repos/a/doc1"),
            proc(120, ppid: 110, name: "perl", exec: "/usr/bin/perl", cwd: "/repos/a/doc1"),
            proc(130, ppid: 120, name: "luahbtex", cwd: "/repos/a/doc1"),
            // Repo B
            proc(200, ppid: 1,   name: "make",   cwd: "/repos/b"),
            proc(210, ppid: 200, name: "gmake",  cwd: "/repos/b/doc2"),
            proc(220, ppid: 210, name: "perl", exec: "/usr/bin/perl", cwd: "/repos/b/doc2"),
        ]
        let t = tree(from: procs)

        let docsA = BuildDetector.findDocumentBuilds(
            rootMakePID: 100, allProcesses: procs, processTree: t)
        XCTAssertEqual(docsA.count, 1)
        XCTAssertEqual(docsA.first?.name, "DOC1")
        XCTAssertTrue(docsA.first?.isRunning ?? false)

        let docsB = BuildDetector.findDocumentBuilds(
            rootMakePID: 200, allProcesses: procs, processTree: t)
        XCTAssertEqual(docsB.count, 1)
        XCTAssertEqual(docsB.first?.name, "DOC2")
        XCTAssertFalse(docsB.first?.isRunning ?? true)
    }

    // MARK: - Processes with nil cwd

    func testHandlesProcessesWithNilCwd() {
        // A perl process with no cwd shouldn't crash, just produce "Unknown" name.
        let procs = [
            proc(100, ppid: 1,   name: "make",  cwd: "/repo"),
            proc(110, ppid: 100, name: "gmake", cwd: nil),
            proc(120, ppid: 110, name: "perl", exec: "/usr/bin/perl", cwd: nil),
        ]
        let docs = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        // gmake has nil cwd, but perl child still structurally matches
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs.first?.name, "Unknown")
        XCTAssertEqual(docs.first?.directory, "unknown")
    }

    // MARK: - Empty process list

    func testEmptyProcessListReturnsNothing() {
        let builds = BuildDetector.findNDocMakeProcesses(
            in: [],
            fileExistsCheck: { _ in true }
        )
        XCTAssertTrue(builds.isEmpty)

        let docs = BuildDetector.findDocumentBuilds(
            rootMakePID: 999,
            allProcesses: [],
            processTree: [:]
        )
        XCTAssertTrue(docs.isEmpty)
    }

    // MARK: - isMake

    func testIsMakeAcceptsMakeAndGmake() {
        XCTAssertTrue(BuildDetector.isMake(proc(1, name: "make")))
        XCTAssertTrue(BuildDetector.isMake(proc(1, name: "gmake")))
        XCTAssertFalse(BuildDetector.isMake(proc(1, name: "cmake")))
        XCTAssertFalse(BuildDetector.isMake(proc(1, name: "ninja")))
    }
}

// MARK: - BuildMonitor robustness

@MainActor
final class BuildMonitorRobustnessTests: XCTestCase {

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

    // MARK: - Stale entry cleanup

    func testStaleDocumentIsCleaned() {
        let monitor = BuildMonitor()

        // Cycle 1: two documents active
        monitor.applyDocumentSnapshots([
            snapshot(latexmkPID: 120, name: "ADV_TDS", lualatexPID: 500),
            snapshot(latexmkPID: 121, name: "ASE", lualatexPID: 600),
        ])
        XCTAssertEqual(monitor.documentBuilds.count, 2)

        // Cycle 2: ADV_TDS's latexmk process died unexpectedly
        monitor.applyDocumentSnapshots([
            snapshot(latexmkPID: 121, name: "ASE", lualatexPID: 601),
        ])
        XCTAssertEqual(monitor.documentBuilds.count, 1)
        XCTAssertEqual(monitor.documentBuilds.first?.name, "ASE")
        XCTAssertEqual(monitor.documentBuilds.first?.runCount, 2,
            "ASE should show run 2 after new lualatex PID")
    }

    // MARK: - Rapid start/stop

    func testStartStopClearState() {
        let monitor = BuildMonitor()
        monitor.applyDocumentSnapshots([
            snapshot(lualatexPID: 500),
        ])
        XCTAssertEqual(monitor.documentBuilds.count, 1)

        monitor.stopMonitoring()
        XCTAssertTrue(monitor.documentBuilds.isEmpty)
        XCTAssertTrue(monitor.activeBuilds.isEmpty)
        XCTAssertNil(monitor.lastCompletedBuild)

        // After stop + restart, counts should be fresh
        monitor.applyDocumentSnapshots([
            snapshot(lualatexPID: 700),
        ])
        XCTAssertEqual(monitor.documentBuilds.first?.runCount, 1,
            "Should start fresh after stop")
    }

    // MARK: - Build-finished transition

    func testBuildFinishedSummaryIsCaptured() {
        let monitor = BuildMonitor()

        let fakeBuild = BuildDetector.DetectedBuild(makePID: 100, repoPath: "/repo")

        // Cycle 1: build is active with two documents.
        monitor.simulateScanResult(
            builds: [fakeBuild],
            documents: [
                snapshot(latexmkPID: 120, name: "ADV_TDS", lualatexPID: 500),
                snapshot(latexmkPID: 121, name: "ASE", lualatexPID: 600),
            ]
        )
        XCTAssertTrue(monitor.isBuildActive)
        XCTAssertNil(monitor.lastCompletedBuild,
            "Should not show completed while build is active")

        // Cycle 2: build finished — no builds, no documents.
        monitor.simulateScanResult(builds: [], documents: [])
        XCTAssertFalse(monitor.isBuildActive)
        XCTAssertNotNil(monitor.lastCompletedBuild)
        XCTAssertEqual(monitor.lastCompletedBuild?.documents.count, 2)
        let names = Set(monitor.lastCompletedBuild?.documents.map(\.name) ?? [])
        XCTAssertEqual(names, ["ADV_TDS", "ASE"])
    }

    func testNoCompletedBuildWhenNeverActive() {
        let monitor = BuildMonitor()

        // Going from idle to idle should not create a completed build.
        monitor.simulateScanResult(builds: [], documents: [])
        XCTAssertNil(monitor.lastCompletedBuild)
    }

    // MARK: - CompletedBuild model

    func testCompletedBuildEquatable() {
        let a = CompletedBuild(
            repoPath: "/a",
            documents: [.init(name: "DOC", totalRuns: 3)],
            finishedAt: Date(timeIntervalSince1970: 1000)
        )
        let b = CompletedBuild(
            repoPath: "/a",
            documents: [.init(name: "DOC", totalRuns: 3)],
            finishedAt: Date(timeIntervalSince1970: 1000)
        )
        XCTAssertEqual(a, b)
    }
}
