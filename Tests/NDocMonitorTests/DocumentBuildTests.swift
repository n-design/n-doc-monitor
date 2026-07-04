import XCTest
@testable import NDocMonitor

/// Tests for Step 4: process tree walking and document build detection.
///
/// We build synthetic process trees that mirror the real n-doc hierarchy:
/// ```
/// make (PID 100, cwd = /repo)
///  └─ make (PID 110, cwd = /repo/adv_tds)
///      └─ latexmk (PID 120, cwd = /repo/adv_tds)
///          └─ lualatex (PID 130, cwd = /repo/adv_tds)
/// ```
final class DocumentBuildTests: XCTestCase {

    // MARK: - Helpers

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

    /// Build a parent→children tree from a flat process list.
    private func tree(from procs: [NDocMonitor.ProcessInfo]) -> [pid_t: [pid_t]] {
        var t: [pid_t: [pid_t]] = [:]
        for p in procs {
            t[p.ppid, default: []].append(p.pid)
        }
        return t
    }

    // MARK: - isLatexmk / isLualatex

    func testIsLatexmkByName() {
        let p = proc(1, name: "latexmk")
        XCTAssertTrue(BuildDetector.isLatexmk(p))
    }

    func testIsLatexmkByExecPath() {
        // latexmk is a Perl script — process name is "perl" but exec path
        // contains "latexmk".
        let p = proc(1, name: "perl",
                     exec: "/usr/local/bin/latexmk")
        XCTAssertTrue(BuildDetector.isLatexmk(p))
    }

    func testIsNotLatexmk() {
        let p = proc(1, name: "perl", exec: "/usr/bin/perl")
        XCTAssertFalse(BuildDetector.isLatexmk(p))
    }

    func testIsLualatexByName() {
        XCTAssertTrue(BuildDetector.isLualatex(proc(1, name: "lualatex")))
    }

    func testIsLualatexByLuahbtexName() {
        // On some TeX distributions, the binary is called "luahbtex".
        XCTAssertTrue(BuildDetector.isLualatex(proc(1, name: "luahbtex")))
    }

    func testIsLualatexByExecPath() {
        let p = proc(1, name: "luahbtex",
                     exec: "/usr/local/texlive/2025/bin/universal-darwin/lualatex")
        XCTAssertTrue(BuildDetector.isLualatex(p))
    }

    func testIsNotLualatex() {
        XCTAssertFalse(BuildDetector.isLualatex(proc(1, name: "pdflatex")))
    }

    // MARK: - documentName

    func testDocumentNameFromPath() {
        XCTAssertEqual(BuildDetector.documentName(from: "/repos/n-doc/adv_tds"), "ADV_TDS")
        XCTAssertEqual(BuildDetector.documentName(from: "/repos/n-doc/ase"), "ASE")
    }

    func testDocumentNameFromNil() {
        XCTAssertEqual(BuildDetector.documentName(from: nil), "Unknown")
    }

    // MARK: - findDocumentBuilds — simple tree

    func testFindsLatexmkInSimpleTree() {
        // make → sub-make → latexmk
        let procs = [
            proc(100, ppid: 1,   name: "make",    cwd: "/repo"),
            proc(110, ppid: 100, name: "make",    cwd: "/repo/adv_tds"),
            proc(120, ppid: 110, name: "latexmk", cwd: "/repo/adv_tds"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertEqual(builds.count, 1)
        XCTAssertEqual(builds.first?.name, "ADV_TDS")
        XCTAssertEqual(builds.first?.id, 120)
        XCTAssertFalse(builds.first?.isRunning ?? true,
            "No lualatex child, so should not be running")
    }

    func testFindsLatexmkWithActiveLualatex() {
        // make → sub-make → latexmk → lualatex
        let procs = [
            proc(100, ppid: 1,   name: "make",     cwd: "/repo"),
            proc(110, ppid: 100, name: "make",     cwd: "/repo/ase"),
            proc(120, ppid: 110, name: "latexmk",  cwd: "/repo/ase"),
            proc(130, ppid: 120, name: "lualatex", cwd: "/repo/ase"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertEqual(builds.count, 1)
        XCTAssertEqual(builds.first?.name, "ASE")
        XCTAssertTrue(builds.first?.isRunning ?? false)
        XCTAssertEqual(builds.first?.currentLualatexPID, 130)
    }

    // MARK: - Parallel document builds

    func testFindsMultipleDocuments() {
        // make -j2 building two documents in parallel:
        // make → sub-make(adv_tds) → latexmk
        //     → sub-make(ase)     → latexmk → lualatex
        let procs = [
            proc(100, ppid: 1,   name: "make",     cwd: "/repo"),
            proc(110, ppid: 100, name: "make",     cwd: "/repo/adv_tds"),
            proc(111, ppid: 100, name: "make",     cwd: "/repo/ase"),
            proc(120, ppid: 110, name: "latexmk",  cwd: "/repo/adv_tds"),
            proc(121, ppid: 111, name: "latexmk",  cwd: "/repo/ase"),
            proc(130, ppid: 121, name: "lualatex", cwd: "/repo/ase"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertEqual(builds.count, 2)

        let names = Set(builds.map(\.name))
        XCTAssertTrue(names.contains("ADV_TDS"))
        XCTAssertTrue(names.contains("ASE"))

        let ase = builds.first { $0.name == "ASE" }
        XCTAssertTrue(ase?.isRunning ?? false)

        let adv = builds.first { $0.name == "ADV_TDS" }
        XCTAssertFalse(adv?.isRunning ?? true)
    }

    // MARK: - Perl-based latexmk

    func testFindsPerlBasedLatexmkByExecPath() {
        // latexmk running as perl with latexmk in the exec path
        let procs = [
            proc(100, ppid: 1,   name: "make", cwd: "/repo"),
            proc(110, ppid: 100, name: "make", cwd: "/repo/adv_fsp"),
            proc(120, ppid: 110, name: "perl",
                 exec: "/usr/local/bin/latexmk", cwd: "/repo/adv_fsp"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertEqual(builds.count, 1)
        XCTAssertEqual(builds.first?.name, "ADV_FSP")
    }

    func testFindsPerlChildOfMakeStructurally() {
        // Real-world scenario: latexmk shows as perl with exec=/usr/bin/perl.
        // No "latexmk" anywhere in the process info.
        // Detection works because perl is a direct child of gmake in the tree.
        let procs = [
            proc(100, ppid: 1,   name: "make",  cwd: "/repo"),
            proc(110, ppid: 100, name: "gmake", cwd: "/repo/adv_tds"),
            proc(120, ppid: 110, name: "perl",
                 exec: "/usr/bin/perl", cwd: "/repo/adv_tds"),
            proc(130, ppid: 120, name: "luahbtex",
                 exec: "/usr/local/texlive/2026/bin/universal-darwin/luahbtex",
                 cwd: "/repo/adv_tds"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertEqual(builds.count, 1)
        XCTAssertEqual(builds.first?.name, "ADV_TDS")
        XCTAssertTrue(builds.first?.isRunning ?? false)
        XCTAssertEqual(builds.first?.currentLualatexPID, 130)
    }

    func testRealWorldParallelBuild() {
        // Mirrors the actual process tree observed on the user's system:
        // make -j10 → gmake (per doc) → perl (latexmk) → luahbtex
        let procs = [
            proc(100, ppid: 1,   name: "make",     cwd: "/repo"),
            proc(110, ppid: 100, name: "gmake",    cwd: "/repo/adv_tds"),
            proc(111, ppid: 100, name: "gmake",    cwd: "/repo/ase_st_pp98"),
            proc(112, ppid: 100, name: "gmake",    cwd: "/repo/ate_test_osc"),
            proc(120, ppid: 110, name: "perl", exec: "/usr/bin/perl", cwd: "/repo/adv_tds"),
            proc(121, ppid: 111, name: "perl", exec: "/usr/bin/perl", cwd: "/repo/ase_st_pp98"),
            proc(122, ppid: 112, name: "perl", exec: "/usr/bin/perl", cwd: "/repo/ate_test_osc"),
            proc(130, ppid: 120, name: "luahbtex", cwd: "/repo/adv_tds"),
            proc(131, ppid: 121, name: "luahbtex", cwd: "/repo/ase_st_pp98"),
            proc(132, ppid: 122, name: "luahbtex", cwd: "/repo/ate_test_osc"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertEqual(builds.count, 3)
        let names = Set(builds.map(\.name))
        XCTAssertEqual(names, ["ADV_TDS", "ASE_ST_PP98", "ATE_TEST_OSC"])
        XCTAssertTrue(builds.allSatisfy { $0.isRunning })
    }

    // MARK: - No latexmk processes

    func testNoLatexmkReturnsEmpty() {
        // make is running but hasn't spawned latexmk yet
        let procs = [
            proc(100, ppid: 1,   name: "make", cwd: "/repo"),
            proc(110, ppid: 100, name: "make", cwd: "/repo/adv_tds"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertTrue(builds.isEmpty)
    }

    // MARK: - Ignores unrelated processes

    func testIgnoresLatexmkOutsideTree() {
        // A latexmk process exists but is NOT a descendant of our make
        let procs = [
            proc(100, ppid: 1,  name: "make",    cwd: "/repo"),
            proc(999, ppid: 1,  name: "latexmk", cwd: "/other/project"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertTrue(builds.isEmpty,
            "Should not find latexmk processes outside the build tree")
    }

    // MARK: - luahbtex detection

    func testDetectsLuahbtexAsLualatex() {
        let procs = [
            proc(100, ppid: 1,   name: "make",     cwd: "/repo"),
            proc(110, ppid: 100, name: "make",     cwd: "/repo/ase"),
            proc(120, ppid: 110, name: "latexmk",  cwd: "/repo/ase"),
            proc(130, ppid: 120, name: "luahbtex", cwd: "/repo/ase"),
        ]
        let builds = BuildDetector.findDocumentBuilds(
            rootMakePID: 100,
            allProcesses: procs,
            processTree: tree(from: procs)
        )
        XCTAssertEqual(builds.count, 1)
        XCTAssertTrue(builds.first?.isRunning ?? false)
        XCTAssertEqual(builds.first?.currentLualatexPID, 130)
    }
}
