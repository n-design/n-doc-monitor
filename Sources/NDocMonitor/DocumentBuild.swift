import Darwin

/// Represents a single n-doc document being typeset.
///
/// Each document corresponds to one `latexmk` process (e.g. in the
/// `adv_tds/` subdirectory).  That `latexmk` process spawns one or
/// more sequential `lualatex` runs.
///
/// **Swift concepts introduced here:**
/// - `Identifiable` — required by SwiftUI's `ForEach` to track items
///   across re-renders.  We use the `latexmk` PID as the identity.
/// - `Equatable` — lets us compare snapshots to detect changes.
/// - `Sendable` — marks the type as safe to pass across concurrency
///   boundaries (important for `@MainActor`-isolated code).
struct DocumentBuild: Identifiable, Equatable, Sendable {
    /// The `latexmk` process ID — unique identity for this document build.
    let id: pid_t

    /// Human-readable document name, derived from the working directory.
    /// For example, a `latexmk` process in `/repos/n-doc/adv_tds` produces
    /// the name "ADV_TDS".
    let name: String

    /// The working directory of the `latexmk` process.
    let directory: String

    /// Number of `lualatex` invocations observed so far.
    var runCount: Int

    /// Whether a `lualatex` process is currently running right now
    /// (i.e. a child of this `latexmk` process exists).
    var isRunning: Bool

    /// The PID of the currently running `lualatex` process, if any.
    /// Used to detect when a *new* run starts (different PID = new run).
    var currentLualatexPID: pid_t?
}
