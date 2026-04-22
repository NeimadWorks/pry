// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spike01",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spike01", targets: ["Spike01"])
    ],
    targets: [
        .executableTarget(
            name: "Spike01",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
