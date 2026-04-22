// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spike05",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spike05", targets: ["Spike05"])
    ],
    targets: [
        .executableTarget(
            name: "Spike05",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
