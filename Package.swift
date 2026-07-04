// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NDocMonitor",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "NDocMonitor",
            path: "Sources/NDocMonitor"
        ),
        .testTarget(
            name: "NDocMonitorTests",
            dependencies: ["NDocMonitor"],
            path: "Tests/NDocMonitorTests"
        ),
    ]
)
