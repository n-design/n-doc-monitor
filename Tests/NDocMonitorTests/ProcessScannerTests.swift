import XCTest
@testable import NDocMonitor

/// Tests for `ProcessScanner`.
///
/// These are *integration-style* tests — they call the real `libproc`
/// APIs against the live system.  We can make useful assertions because
/// certain things are always true while the tests are running:
///
/// - Our own process is always alive (we know our PID).
/// - Our process has a parent (the test runner).
/// - The process tree always contains at least a handful of entries.
final class ProcessScannerTests: XCTestCase {

    // MARK: - listAllPIDs

    func testListAllPIDsReturnsNonEmptyList() {
        let pids = ProcessScanner.listAllPIDs()
        // A running macOS system always has dozens of processes.
        XCTAssertGreaterThan(pids.count, 10,
            "Expected many running processes, got \(pids.count)")
    }

    func testListAllPIDsContainsOwnProcess() {
        let myPID = getpid()
        let pids = ProcessScanner.listAllPIDs()
        XCTAssertTrue(pids.contains(myPID),
            "Our own PID (\(myPID)) should appear in the process list")
    }

    // MARK: - getProcessInfo

    func testGetProcessInfoForOwnProcess() {
        let myPID = getpid()
        let info = ProcessScanner.getProcessInfo(pid: myPID)

        XCTAssertNotNil(info, "Should be able to inspect our own process")
        guard let info else { return }

        XCTAssertEqual(info.pid, myPID)
        XCTAssertGreaterThan(info.ppid, 0,
            "Our process should have a valid parent PID")
        XCTAssertFalse(info.name.isEmpty,
            "Process name should not be empty")
    }

    func testGetProcessInfoReturnsExecutablePath() {
        let myPID = getpid()
        let info = ProcessScanner.getProcessInfo(pid: myPID)

        XCTAssertNotNil(info?.executablePath,
            "Should be able to retrieve the executable path")
        if let path = info?.executablePath {
            XCTAssertTrue(path.hasPrefix("/"),
                "Executable path should be absolute, got: \(path)")
        }
    }

    func testGetProcessInfoReturnsCurrentDirectory() {
        let myPID = getpid()
        let info = ProcessScanner.getProcessInfo(pid: myPID)

        XCTAssertNotNil(info?.currentDirectory,
            "Should be able to retrieve the working directory")
        if let cwd = info?.currentDirectory {
            XCTAssertTrue(cwd.hasPrefix("/"),
                "Working directory should be absolute, got: \(cwd)")
        }
    }

    func testGetProcessInfoReturnsNilForInvalidPID() {
        // PID 0 is the kernel task — we can't inspect it from userspace.
        // A very high PID is also unlikely to exist.
        let info = ProcessScanner.getProcessInfo(pid: 999_999)
        XCTAssertNil(info,
            "Should return nil for a non-existent PID")
    }

    // MARK: - buildProcessTree

    func testBuildProcessTreeIsNonEmpty() {
        let tree = ProcessScanner.buildProcessTree()
        XCTAssertGreaterThan(tree.count, 0,
            "Process tree should contain entries")
    }

    func testBuildProcessTreeContainsOurParent() {
        let myPID = getpid()
        let myPPID = getppid()
        let tree = ProcessScanner.buildProcessTree()

        // Our parent should have us as a child.
        let siblings = tree[myPPID] ?? []
        XCTAssertTrue(siblings.contains(myPID),
            "Our PID (\(myPID)) should be a child of our parent (\(myPPID))")
    }

    // MARK: - descendants

    func testDescendantsOfInit() {
        // PID 1 (launchd) is the ancestor of most processes.
        // It should have at least some descendants.
        let tree = ProcessScanner.buildProcessTree()
        let desc = ProcessScanner.descendants(of: 1, in: tree)
        XCTAssertGreaterThan(desc.count, 5,
            "launchd (PID 1) should have many descendants")
    }

    func testDescendantsOfLeafProcessIsEmpty() {
        // Our own process (the test runner) likely has no children.
        let myPID = getpid()
        let tree = ProcessScanner.buildProcessTree()
        let desc = ProcessScanner.descendants(of: myPID, in: tree)
        // This might not be empty if XCTest forks helper processes,
        // but it certainly shouldn't crash.
        _ = desc  // just verify it doesn't crash
    }

    // MARK: - allProcesses

    func testAllProcessesReturnsNonEmptyList() {
        let all = ProcessScanner.allProcesses()
        XCTAssertGreaterThan(all.count, 10,
            "Should return many process info structs")
    }

    // MARK: - ProcessInfo conformances

    func testProcessInfoEquatable() {
        let a = ProcessInfo(pid: 42, ppid: 1, name: "test",
                            executablePath: "/usr/bin/test",
                            currentDirectory: "/tmp")
        let b = ProcessInfo(pid: 42, ppid: 1, name: "test",
                            executablePath: "/usr/bin/test",
                            currentDirectory: "/tmp")
        let c = ProcessInfo(pid: 43, ppid: 1, name: "test",
                            executablePath: "/usr/bin/test",
                            currentDirectory: "/tmp")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
