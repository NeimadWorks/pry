// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spike04",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spike04", targets: ["Spike04"])
    ],
    targets: [
        .executableTarget(
            name: "Spike04",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
