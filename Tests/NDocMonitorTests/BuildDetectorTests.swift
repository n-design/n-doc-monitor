import XCTest
@testable import NDocMonitor

/// Tests for `BuildDetector`.
///
/// These use the injectable `fileExistsCheck` parameter to simulate
/// the presence or absence of `common/latexmkrc` without needing
/// real n-doc repositories or running `make` processes.  This
/// demonstrates a common testing pattern: **dependency injection**
/// via closures.
final class BuildDetectorTests: XCTestCase {

    // MARK: - Helpers

    /// Create a fake `ProcessInfo` for testing.
    private func fakeProcess(
        pid: pid_t,
        ppid: pid_t = 1,
        name: String,
        cwd: String? = "/some/path"
    ) -> NDocMonitor.ProcessInfo {
        NDocMonitor.ProcessInfo(
            pid: pid,
            ppid: ppid,
            name: name,
            executablePath: "/usr/bin/\(name)",
            currentDirectory: cwd
        )
    }

    /// A `fileExistsCheck` that always returns `true`.
    private func alwaysExists(_ path: String) -> Bool { true }

    /// A `fileExistsCheck` that always returns `false`.
    private func neverExists(_ path: String) -> Bool { false }

    // MARK: - Detection logic

    func testDetectsMakeProcessInNDocRepo() {
        let processes = [
            fakeProcess(pid: 100, name: "make", cwd: "/Users/me/n-doc"),
        ]
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: alwaysExists
        )
        XCTAssertEqual(builds.count, 1)
        XCTAssertEqual(builds.first?.makePID, 100)
        XCTAssertEqual(builds.first?.repoPath, "/Users/me/n-doc")
    }

    func testIgnoresNonMakeProcesses() {
        let processes = [
            fakeProcess(pid: 200, name: "latexmk", cwd: "/Users/me/n-doc"),
            fakeProcess(pid: 201, name: "lualatex", cwd: "/Users/me/n-doc"),
            fakeProcess(pid: 202, name: "bash", cwd: "/Users/me/n-doc"),
        ]
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: alwaysExists
        )
        XCTAssertTrue(builds.isEmpty,
            "Should not detect non-make processes as n-doc builds")
    }

    func testIgnoresMakeProcessNotInNDocRepo() {
        let processes = [
            fakeProcess(pid: 300, name: "make", cwd: "/Users/me/other-project"),
        ]
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: neverExists
        )
        XCTAssertTrue(builds.isEmpty,
            "Should not detect make in non-n-doc directory")
    }

    func testIgnoresMakeProcessWithNoCwd() {
        let processes = [
            fakeProcess(pid: 400, name: "make", cwd: nil),
        ]
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: alwaysExists
        )
        XCTAssertTrue(builds.isEmpty,
            "Should not detect make process without a working directory")
    }

    func testDetectsMultipleBuilds() {
        let processes = [
            fakeProcess(pid: 500, name: "make", cwd: "/repos/project-a"),
            fakeProcess(pid: 501, name: "make", cwd: "/repos/project-b"),
        ]
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: alwaysExists
        )
        XCTAssertEqual(builds.count, 2)
    }

    func testDetectsGmake() {
        let processes = [
            fakeProcess(pid: 600, name: "gmake", cwd: "/Users/me/n-doc"),
        ]
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: alwaysExists
        )
        XCTAssertEqual(builds.count, 1,
            "Should also detect gmake (GNU make alternative name)")
    }

    func testChecksCorrectMarkerPath() {
        let processes = [
            fakeProcess(pid: 700, name: "make", cwd: "/Users/me/n-doc"),
        ]
        var checkedPath: String?
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: { path in
                checkedPath = path
                return true
            }
        )
        XCTAssertEqual(checkedPath, "/Users/me/n-doc/common/latexmkrc",
            "Should check for common/latexmkrc in the make process's cwd")
        XCTAssertEqual(builds.count, 1)
    }

    func testSelectiveDetection() {
        // Mix of n-doc and non-n-doc make processes
        let processes = [
            fakeProcess(pid: 800, name: "make", cwd: "/repos/n-doc"),
            fakeProcess(pid: 801, name: "make", cwd: "/repos/other"),
            fakeProcess(pid: 802, name: "bash", cwd: "/repos/n-doc"),
        ]
        let builds = BuildDetector.findNDocMakeProcesses(
            in: processes,
            fileExistsCheck: { path in
                // Only the first one has the marker file
                path == "/repos/n-doc/common/latexmkrc"
            }
        )
        XCTAssertEqual(builds.count, 1)
        XCTAssertEqual(builds.first?.makePID, 800)
    }

    // MARK: - DetectedBuild

    func testDetectedBuildEquatable() {
        let a = BuildDetector.DetectedBuild(makePID: 1, repoPath: "/a")
        let b = BuildDetector.DetectedBuild(makePID: 1, repoPath: "/a")
        let c = BuildDetector.DetectedBuild(makePID: 2, repoPath: "/a")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
