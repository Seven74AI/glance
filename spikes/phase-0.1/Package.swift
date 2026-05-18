// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GlanceSpike",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "glance-spike",
            targets: ["GlanceSpike"]
        )
    ],
    targets: [
        .executableTarget(
            name: "GlanceSpike",
            path: "Sources/GlanceSpike",
            resources: [
                .process("Shaders.metal")
            ]
        )
    ]
)
