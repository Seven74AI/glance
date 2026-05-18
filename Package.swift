// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GlanceCapture",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CaptureEngine",
            targets: ["CaptureEngine"]
        ),
        .executable(
            name: "GlanceTestApp",
            targets: ["GlanceTestApp"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CaptureEngine",
            dependencies: [],
            path: "Sources/CaptureEngine",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CaptureEngineTests",
            dependencies: ["CaptureEngine"],
            path: "Tests/CaptureEngineTests"
        ),
        .executableTarget(
            name: "GlanceTestApp",
            dependencies: ["CaptureEngine"],
            path: "App"
        ),
    ]
)
