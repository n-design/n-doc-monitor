import Darwin

/// Enumerates running processes and retrieves their metadata using
/// the macOS `libproc` C API.
///
/// ## How `libproc` works
///
/// macOS exposes process information through a small set of C functions
/// declared in `<libproc.h>` (imported automatically via `Darwin`):
///
/// - `proc_listallpids` — fills a buffer with every active PID.
/// - `proc_pidinfo`     — retrieves structured data about a single PID
///                        (name, ppid, etc.) depending on a "flavor" constant.
/// - `proc_pidpath`     — retrieves the full executable path for a PID.
///
/// These work for any process owned by the *same user* — no elevated
/// privileges needed.
///
/// ## Why a separate type?
///
/// Keeping all `libproc` calls in one place means the rest of the app
/// never touches unsafe C pointers.  It also makes testing easier:
/// in future steps we can create a protocol and swap in a mock.
///
/// **Swift concepts introduced here:**
/// - `withUnsafeMutablePointer(to:)` — provides a typed pointer to a
///   stack-allocated value so we can pass it to C functions.
/// - Tuple-to-String conversion for C char arrays (`pbi_name`, etc.).
/// - `static` functions — called on the type, not an instance.
enum ProcessScanner {

    // MARK: - Public API

    /// Return the PIDs of all currently running processes.
    static func listAllPIDs() -> [pid_t] {
        // First call with nil buffer returns the required buffer size
        // (number of pids).
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }

        // Allocate a buffer and fill it.  The process list can change
        // between the two calls, so we add a small margin.
        var pids = [pid_t](repeating: 0, count: Int(estimatedCount) + 20)
        let bufferSize = Int32(pids.count) * Int32(MemoryLayout<pid_t>.size)
        let actualCount = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, bufferSize)
        }
        guard actualCount > 0 else { return [] }

        return Array(pids.prefix(Int(actualCount)))
    }

    /// Retrieve metadata for a single process.
    ///
    /// Returns `nil` if the process has already exited or if we lack
    /// permission to inspect it.
    static func getProcessInfo(pid: pid_t) -> ProcessInfo? {
        // --- BSD info (name + ppid) ---
        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = withUnsafeMutablePointer(to: &bsdInfo) { ptr in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, bsdSize)
        }
        guard result == bsdSize else { return nil }

        let name = withUnsafeBytes(of: bsdInfo.pbi_name) { rawBuffer in
            // pbi_name is a fixed-size C char array (MAXCOMLEN+1 = 17).
            // We interpret it as a null-terminated UTF-8 string.
            guard let baseAddress = rawBuffer.baseAddress else { return "" }
            return String(cString: baseAddress.assumingMemoryBound(to: CChar.self))
        }

        // --- Executable path ---
        let executablePath = getExecutablePath(pid: pid)

        // --- Current working directory ---
        let cwd = getCurrentDirectory(pid: pid)

        return ProcessInfo(
            pid: pid,
            ppid: pid_t(bsdInfo.pbi_ppid),
            name: name,
            executablePath: executablePath,
            currentDirectory: cwd
        )
    }

    /// Build a mapping from parent PID → list of child PIDs.
    ///
    /// This lets us walk the tree downward from any process to find
    /// its descendants (e.g. make → latexmk → lualatex).
    static func buildProcessTree() -> [pid_t: [pid_t]] {
        let allPIDs = listAllPIDs()
        var tree: [pid_t: [pid_t]] = [:]

        for pid in allPIDs {
            if let info = getProcessInfo(pid: pid) {
                tree[info.ppid, default: []].append(pid)
            }
        }
        return tree
    }

    /// Return `ProcessInfo` for every running process we can inspect.
    static func allProcesses() -> [ProcessInfo] {
        listAllPIDs().compactMap { getProcessInfo(pid: $0) }
    }

    /// A consistent point-in-time view of all processes and their tree.
    ///
    /// **Step 7 — robustness fix:**
    /// Previously, `allProcesses()` and `buildProcessTree()` each
    /// called `listAllPIDs()` independently, creating a window where
    /// processes could appear or disappear between the two scans.
    /// This struct captures everything in a single PID enumeration.
    struct Snapshot {
        let processes: [ProcessInfo]
        let tree: [pid_t: [pid_t]]
    }

    /// Take a single consistent snapshot of all processes.
    static func snapshot() -> Snapshot {
        let infos = allProcesses()
        var tree: [pid_t: [pid_t]] = [:]
        for info in infos {
            tree[info.ppid, default: []].append(info.pid)
        }
        return Snapshot(processes: infos, tree: tree)
    }

    /// Find all descendants of a given PID using a pre-built tree.
    static func descendants(of pid: pid_t, in tree: [pid_t: [pid_t]]) -> [pid_t] {
        var result: [pid_t] = []
        var queue = tree[pid] ?? []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            result.append(current)
            queue.append(contentsOf: tree[current] ?? [])
        }
        return result
    }

    // MARK: - Private helpers

    /// Get the full executable path for a PID (e.g. "/usr/bin/make").
    private static func getExecutablePath(pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        guard length > 0 else { return nil }
        // Truncate at the null terminator and decode as UTF-8.
        let truncated = pathBuffer.prefix(while: { $0 != 0 }).map { UInt8($0) }
        return String(decoding: truncated, as: UTF8.self)
    }

    /// Get the current working directory for a PID.
    ///
    /// Uses `PROC_PIDVNODEPATHINFO` which returns both the current
    /// directory and the root directory of the process.
    private static func getCurrentDirectory(pid: pid_t) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let vnodeSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = withUnsafeMutablePointer(to: &vnodeInfo) { ptr in
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, ptr, vnodeSize)
        }
        guard result == vnodeSize else { return nil }

        let cwd = withUnsafeBytes(of: vnodeInfo.pvi_cdir.vip_path) { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return "" }
            return String(cString: baseAddress.assumingMemoryBound(to: CChar.self))
        }
        return cwd.isEmpty ? nil : cwd
    }
}
