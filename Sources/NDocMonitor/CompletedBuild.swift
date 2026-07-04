import Foundation

/// Summary of a build that has finished.
///
/// **Step 7 — robustness:**
/// When the root `make` process exits, the monitor captures a
/// snapshot of the final state so the UI can show a brief summary
/// ("Build finished — 10 documents") before returning to idle.
struct CompletedBuild: Equatable, Sendable {
    /// The repo path that was being built.
    let repoPath: String

    /// The documents that were being typeset when the build ended.
    let documents: [DocumentSummary]

    /// When the build completion was detected.
    let finishedAt: Date

    /// Summary of one document's build result.
    struct DocumentSummary: Equatable, Sendable {
        let name: String
        let totalRuns: Int
    }
}
