// swift-tools-version: 5.9
// Glance — macOS screen-to-AI tool
// Unified package for all Phase 1 modules.
// Integration task (1.5) will wire all modules together.

import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Capture engine library (Phase 1.1)
        .library(
            name: "CaptureEngine",
            targets: ["CaptureEngine"]
        ),
        // Frame processor library (Phase 1.2) — Metal + JPEG pipeline
        .library(
            name: "GlanceFrameProcessor",
            targets: ["FrameProcessor"]
        ),
        // AI Provider library (Phase 1.3) — Claude/GPT/Gemini
        .library(
            name: "AIProvider",
            targets: ["AIProvider"]
        ),
        // UI framework library (Phase 1.4)
        .library(
            name: "GlanceUI",
            targets: ["GlanceUI"]
        ),
        // Main test app executable (dev/testing)
        .executable(
            name: "GlanceTestApp",
            targets: ["GlanceTestApp"]
        ),
        // Main Glance app executable (production)
        .executable(
            name: "Glance",
            targets: ["GlanceApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        // Capture Engine — ScreenCaptureKit integration (Phase 1.1)
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

        // Frame Processor — Metal preprocessing + JPEG encoding (Phase 1.2)
        .target(
            name: "FrameProcessor",
            dependencies: [],
            path: "Sources/FrameProcessor",
            resources: [
                .process("PreprocessShader.metal")
            ]
        ),
        .testTarget(
            name: "FrameProcessorTests",
            dependencies: ["FrameProcessor"],
            path: "Tests/FrameProcessorTests",
            exclude: ["Benchmarks"]
        ),
        .testTarget(
            name: "FrameProcessorBenchmarks",
            dependencies: ["FrameProcessor"],
            path: "Tests/FrameProcessorTests/Benchmarks"
        ),

        // AI Provider — Claude/GPT/Gemini HTTP clients (Phase 1.3)
        .target(
            name: "AIProvider",
            dependencies: [],
            path: "Sources/AIProvider"
        ),
        .testTarget(
            name: "AIProviderTests",
            dependencies: ["AIProvider"],
            path: "Tests/AIProviderTests"
        ),

        // Glance UI — Menu bar, overlay, preferences (Phase 1.4)
        .target(
            name: "GlanceUI",
            dependencies: [
                "KeyboardShortcuts",
            ],
            path: "Sources/GlanceUI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GlanceUITests",
            dependencies: ["GlanceUI"],
            path: "Tests/GlanceUITests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // GlanceTestApp — Test executable using CaptureEngine
        .executableTarget(
            name: "GlanceTestApp",
            dependencies: ["CaptureEngine"],
            path: "App/GlanceTestApp"
        ),

        // GlanceApp — Main .app executable
        .executableTarget(
            name: "GlanceApp",
            dependencies: [
                "GlanceUI",
                "CaptureEngine",
                "FrameProcessor",
                "AIProvider",  // Post-MVP: AIClient will delegate to AIProvider providers
            ],
            path: "App/GlanceApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // GlanceAppTests — Integration tests for pipeline + AI client
        .testTarget(
            name: "GlanceAppTests",
            dependencies: ["GlanceApp"],
            path: "Tests/GlanceAppTests"
        ),
    ]
)
