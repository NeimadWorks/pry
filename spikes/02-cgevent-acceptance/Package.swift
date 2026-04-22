// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spike02",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spike02", targets: ["Spike02"])
    ],
    targets: [
        .executableTarget(
            name: "Spike02",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
