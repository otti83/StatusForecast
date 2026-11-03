// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StatusForecast",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StatusForecast", targets: ["StatusForecast"])
    ],
    targets: [
        .executableTarget(
            name: "StatusForecast",
            path: "Sources/StatusForecast",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
