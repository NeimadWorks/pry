// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DemoApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DemoApp", targets: ["DemoApp"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DemoApp",
            dependencies: [
                .product(name: "PryHarness", package: "pry")
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        )
    ]
)
