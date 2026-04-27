// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pry",
    platforms: [.macOS(.v14)],
    products: [
        // In-process side: linked into the target app under #if DEBUG.
        .library(name: "PryHarness", targets: ["PryHarness"]),
        // Shared wire types (Codable JSON-RPC messages).
        .library(name: "PryWire", targets: ["PryWire"]),
        // Out-of-process runner: app lifecycle, AX, event injection, spec runner,
        // verdict formatting. Use this from any Swift code (tests, CLIs, custom
        // harnesses) without going through the MCP layer.
        .library(name: "PryRunner", targets: ["PryRunner"]),
        // Thin stdio MCP wrapper around PryRunner. The "register me in Claude
        // Code" entry point.
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
        .target(
            name: "PryRunner",
            dependencies: ["PryWire", "PryHarness"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .executableTarget(
            name: "pry-mcp",
            dependencies: ["PryRunner"],
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
        .testTarget(
            name: "PryRunnerTests",
            dependencies: ["PryRunner"]
        ),
    ]
)
