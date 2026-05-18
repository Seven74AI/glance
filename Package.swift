// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIProvider",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "AIProvider",
            targets: ["AIProvider"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AIProvider",
            path: "Sources/AIProvider"
        ),
        .testTarget(
            name: "AIProviderTests",
            dependencies: ["AIProvider"],
            path: "Tests/AIProviderTests"
        ),
    ]
)
