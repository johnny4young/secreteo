// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Secreteo",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LiveSpeech", targets: ["LiveSpeech"]),
        .library(name: "AppUI", targets: ["AppUI"]),
        .library(name: "DictationAgents", targets: ["DictationAgents"]),
        .executable(name: "secreteo-mcp", targets: ["secreteo-mcp"]),
        .library(name: "DictationKit", targets: ["DictationKit"]),
        .library(name: "DictationOwnership", targets: ["DictationOwnership"]),
        .library(name: "DictationSession", targets: ["DictationSession"]),
        .library(name: "DictationStore", targets: ["DictationStore"]),
        .library(name: "MicCapture", targets: ["MicCapture"]),
        .library(name: "SpeechCore", targets: ["SpeechCore"])
    ],
    dependencies: [
        // Exact on purpose: patch releases change decoder behavior, so a move needs paired evidence.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.2", traits: []),
        .package(url: "https://github.com/johnny4young/local-model-store.git", exact: "0.1.3"),
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "7.11.1"))
    ],
    targets: [
        .target(name: "AppUI", dependencies: ["DictationSession"]),
        .target(name: "DictationAgents", dependencies: ["DictationKit", "DictationStore", "SpeechCore"]),
        .executableTarget(name: "secreteo-mcp", dependencies: ["DictationAgents"]),
        .target(name: "DictationKit", dependencies: ["SpeechCore"]),
        .target(name: "DictationOwnership"),
        .target(
            name: "DictationSession",
            dependencies: [
                "DictationKit", "DictationOwnership", "DictationStore", "LiveSpeech", "MicCapture", "SpeechCore",
                .product(name: "LocalModelStore", package: "local-model-store")
            ]),
        .target(
            name: "DictationStore",
            dependencies: ["DictationKit", "SpeechCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(
            name: "LiveSpeech",
            dependencies: [
                "SpeechCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "LocalModelStore", package: "local-model-store")
            ]),
        .target(name: "MicCapture", dependencies: ["SpeechCore"]),
        .target(name: "SpeechCore"),
        .executableTarget(name: "ownership-test-client", dependencies: ["DictationOwnership"], path: "Tests/OwnershipTestClient"),
        .testTarget(name: "AppUITests", dependencies: ["AppUI"]),
        .testTarget(name: "DictationAgentsTests", dependencies: ["DictationAgents", "DictationKit", "DictationStore", "SpeechCore"]),
        .testTarget(name: "DictationKitTests", dependencies: ["DictationKit", "SpeechCore"]),
        .testTarget(
            name: "DictationStoreTests",
            dependencies: ["DictationStore", "DictationKit", "SpeechCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(
            name: "DictationSessionTests",
            dependencies: [
                "DictationSession", "DictationKit", "DictationStore", "LiveSpeech", "SpeechCore",
                .product(name: "LocalModelStore", package: "local-model-store")
            ]),
        .testTarget(
            name: "LiveSpeechTests",
            dependencies: [
                "LiveSpeech", "SpeechCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "LocalModelStore", package: "local-model-store")
            ]),
        .testTarget(name: "MicCaptureTests", dependencies: ["MicCapture", "SpeechCore"]),
        .testTarget(name: "DictationOwnershipTests", dependencies: ["DictationOwnership", "ownership-test-client"])
    ]
)
