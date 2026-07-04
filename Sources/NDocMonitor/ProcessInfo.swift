import Darwin

/// Information about a single running process.
///
/// This is a lightweight, pure-Swift value type that holds the data we
/// care about for each process.  It is decoupled from the C structs
/// returned by `libproc` so that the rest of the app never has to deal
/// with unsafe pointers or fixed-size C character arrays.
///
/// **Swift concept — `struct`**:
/// Structs in Swift are *value types* — when you assign one to a
/// variable or pass it to a function, a copy is made.  This makes them
/// safe to use across threads without synchronisation.
struct ProcessInfo: Sendable, Equatable, Identifiable {
    /// The process identifier (PID).  Unique while the process is alive.
    let pid: pid_t

    /// The parent process identifier (PPID).
    let ppid: pid_t

    /// The short process name (e.g. "make", "latexmk", "lualatex").
    /// On macOS this is limited to 16 characters (MAXCOMLEN).
    let name: String

    /// The full path to the executable, if available.
    let executablePath: String?

    /// The current working directory of the process, if available.
    let currentDirectory: String?

    /// Conformance to `Identifiable` — SwiftUI uses this when
    /// displaying collections with `ForEach`.
    var id: pid_t { pid }
}
