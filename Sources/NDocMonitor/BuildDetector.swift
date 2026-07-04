import Foundation

/// Detects whether any running `make` process is an n-doc build.
///
/// The detection strategy:
/// 1. Enumerate all running processes.
/// 2. Filter for processes named "make".
/// 3. For each, check if `<cwd>/common/latexmkrc` exists on disk.
///    That file is unique to n-doc repositories.
///
/// This is a pure function layer with no state — it answers the
/// question "is an n-doc build running *right now*?" each time
/// it is called.
///
/// **Swift concepts introduced here:**
/// - `FileManager` — Apple's API for filesystem operations.  We use
///   `fileExists(atPath:)` to probe for the marker file.
/// - Separation of *detection* (this type) from *observation over
///   time* (`BuildMonitor`, coming next).
enum BuildDetector {

    /// A confirmed n-doc build: the root `make` process and the
    /// repository path it is building from.
    struct DetectedBuild: Equatable, Sendable {
        /// PID of the root `make` process.
        let makePID: pid_t

        /// Absolute path to the n-doc repository root (the working
        /// directory of the `make` process).
        let repoPath: String
    }

    /// The file whose presence marks a directory as an n-doc repo.
    static let markerFile = "common/latexmkrc"

    /// Scan all running processes and return any active n-doc builds.
    ///
    /// Typically returns zero or one result, but we support multiple
    /// in case someone runs two builds in parallel from different repos.
    static func detectBuilds() -> [DetectedBuild] {
        let allProcs = ProcessScanner.allProcesses()
        return findNDocMakeProcesses(in: allProcs)
    }

    /// Testable core: given a list of process snapshots, return the
    /// ones that look like n-doc root `make` processes.
    ///
    /// This is separated from `detectBuilds()` so that tests can pass
    /// in synthetic process lists without needing real processes.
    static func findNDocMakeProcesses(
        in processes: [ProcessInfo],
        fileExistsCheck: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [DetectedBuild] {
        processes.compactMap { proc in
            // Only consider processes named "make" or "gmake".
            guard isMake(proc) else { return nil }

            // Must have a known working directory.
            guard let cwd = proc.currentDirectory else { return nil }

            // Check for the n-doc marker file.
            let markerPath = (cwd as NSString).appendingPathComponent(markerFile)
            guard fileExistsCheck(markerPath) else { return nil }

            return DetectedBuild(makePID: proc.pid, repoPath: cwd)
        }
    }

    // MARK: - Step 4: Process tree walking

    /// Scan the process tree below a detected n-doc build and return
    /// a `DocumentBuild` snapshot for each `latexmk` process found.
    ///
    /// The n-doc process hierarchy looks like this:
    /// ```
    /// make (root, cwd = repo root)
    ///  └─ make -C adv_tds  (sub-make, cwd = repo/adv_tds)
    ///      └─ latexmk       (cwd = repo/adv_tds)
    ///          └─ lualatex   (child of latexmk, runs sequentially)
    /// ```
    ///
    /// We walk *all* descendants of the root `make` PID, looking for
    /// `latexmk` (actually a `perl` process — latexmk is a Perl script).
    /// For each one we also check for `lualatex` children.
    ///
    /// **Swift concept — pure-function snapshot:**
    /// This method takes the full process list and tree as parameters
    /// rather than calling `ProcessScanner` itself.  This makes it
    /// fully testable with synthetic data.
    static func findDocumentBuilds(
        rootMakePID: pid_t,
        allProcesses: [ProcessInfo],
        processTree: [pid_t: [pid_t]]
    ) -> [DocumentBuild] {
        // Index processes by PID for fast lookup.
        let byPID = Dictionary(uniqueKeysWithValues: allProcesses.map { ($0.pid, $0) })

        // Get all descendant PIDs of the root make process.
        let descendantPIDs = ProcessScanner.descendants(of: rootMakePID, in: processTree)
        let descendantSet = Set(descendantPIDs)

        // Find latexmk processes among the descendants.
        //
        // latexmk is a Perl script.  On this system the process shows
        // up as name="perl" exec="/usr/bin/perl" — there is no trace
        // of "latexmk" in the executable path because `perl` is the
        // interpreter and the script path only appears in the command-
        // line arguments, which libproc doesn't expose.
        //
        // **Detection strategy (structural):**
        // We look for `perl` processes whose *parent* is a sub-make
        // (make/gmake) that is itself a descendant of the root build.
        // In the n-doc Makefile, the only Perl child of a sub-make is
        // always latexmk.  We also still accept processes literally
        // named "latexmk" or whose exec path contains "latexmk", as
        // a fallback for installations where latexmk has its own
        // binary name.
        let latexmkPIDs = descendantPIDs.filter { pid in
            guard let info = byPID[pid] else { return false }

            // Direct match by name or exec path.
            if isLatexmk(info) { return true }

            // Structural match: perl child of a sub-make in the tree.
            if info.name == "perl" {
                if let parent = byPID[info.ppid],
                   descendantSet.contains(info.ppid),
                   isMake(parent) {
                    return true
                }
            }
            return false
        }

        return latexmkPIDs.compactMap { latexmkPID -> DocumentBuild? in
            guard let latexmkInfo = byPID[latexmkPID] else { return nil }

            // Derive the document name from latexmk's working directory.
            let name = documentName(from: latexmkInfo.currentDirectory)

            // Look for lualatex children of this latexmk process.
            let children = processTree[latexmkPID] ?? []
            let lualatexChild = children.first { pid in
                guard let info = byPID[pid] else { return false }
                return isLualatex(info)
            }

            return DocumentBuild(
                id: latexmkPID,
                name: name,
                directory: latexmkInfo.currentDirectory ?? "unknown",
                runCount: 0,  // Will be updated by BuildMonitor's state tracking
                isRunning: lualatexChild != nil,
                currentLualatexPID: lualatexChild
            )
        }
    }

    /// Convenience: scan live processes for document builds under a
    /// detected n-doc build.
    static func scanDocumentBuilds(for build: DetectedBuild) -> [DocumentBuild] {
        let allProcs = ProcessScanner.allProcesses()
        let tree = ProcessScanner.buildProcessTree()
        return findDocumentBuilds(
            rootMakePID: build.makePID,
            allProcesses: allProcs,
            processTree: tree
        )
    }

    // MARK: - Private helpers

    /// Check if a process is `make` or `gmake`.
    static func isMake(_ info: ProcessInfo) -> Bool {
        info.name == "make" || info.name == "gmake"
    }

    /// Check if a process is `latexmk`.
    ///
    /// latexmk is a Perl script, so the process name is typically
    /// "perl".  We check the executable path for "latexmk".
    /// We also accept a process literally named "latexmk" in case
    /// it's invoked via a shebang or symlink.
    static func isLatexmk(_ info: ProcessInfo) -> Bool {
        if info.name == "latexmk" { return true }
        if let path = info.executablePath, path.contains("latexmk") { return true }
        // latexmk runs as perl — but not every perl process is latexmk.
        // Unfortunately, from libproc we can't see command-line arguments.
        // We rely on the executable path containing "latexmk".
        return false
    }

    /// Check if a process is `lualatex`.
    static func isLualatex(_ info: ProcessInfo) -> Bool {
        if info.name == "lualatex" { return true }
        if info.name == "luahbtex" { return true }
        if let path = info.executablePath, path.contains("lualatex") { return true }
        return false
    }

    /// Derive a human-readable document name from a directory path.
    ///
    /// For example:
    /// - `/Users/me/n-doc/adv_tds` → "ADV_TDS"
    /// - `/Users/me/n-doc/ase`     → "ASE"
    /// - `nil`                     → "Unknown"
    static func documentName(from directory: String?) -> String {
        guard let dir = directory else { return "Unknown" }
        let lastComponent = (dir as NSString).lastPathComponent
        return lastComponent.uppercased()
    }
}
