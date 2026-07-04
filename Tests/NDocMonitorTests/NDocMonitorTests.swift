import XCTest
import SwiftUI
@testable import NDocMonitor

/// Smoke tests for the n-doc-monitor app skeleton.
///
/// These verify that the core types can be instantiated — a basic
/// sanity check that the project compiles and the module is importable.
///
/// We use XCTest here because Swift Testing (`import Testing`) is not
/// yet available in Swift Package Manager command-line builds.  The
/// `XCTestCase` subclass is the traditional way to write tests on Apple
/// platforms.  Each method starting with `test` is discovered and run
/// automatically.
final class NDocMonitorTests: XCTestCase {

    @MainActor func testMonitorViewCreation() {
        let view = MonitorView()
        // If we get here without crashing, the view's body was synthesized
        // successfully.
        _ = view.body
    }
}
