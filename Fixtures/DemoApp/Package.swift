// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DemoApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DemoApp", targets: ["DemoApp"])
    ],
    targets: [
        .executableTarget(
            name: "DemoApp",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
