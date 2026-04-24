// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pry",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PryHarness", targets: ["PryHarness"]),
        .library(name: "PryWire", targets: ["PryWire"]),
        .executable(name: "pry-mcp", targets: ["pry-mcp"]),
    ],
    targets: [
        .target(
            name: "PryWire",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .target(
            name: "PryHarness",
            dependencies: ["PryWire"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .executableTarget(
            name: "pry-mcp",
            dependencies: ["PryWire", "PryHarness"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "PryWireTests",
            dependencies: ["PryWire"]
        ),
        .testTarget(
            name: "PryHarnessTests",
            dependencies: ["PryHarness"]
        ),
    ]
)
