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
            guard proc.name == "make" || proc.name == "gmake" else { return nil }

            // Must have a known working directory.
            guard let cwd = proc.currentDirectory else { return nil }

            // Check for the n-doc marker file.
            let markerPath = (cwd as NSString).appendingPathComponent(markerFile)
            guard fileExistsCheck(markerPath) else { return nil }

            return DetectedBuild(makePID: proc.pid, repoPath: cwd)
        }
    }
}
