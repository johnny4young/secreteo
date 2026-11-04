// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Secreteo",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LiveSpeech", targets: ["LiveSpeech"]),
        .library(name: "AppUI", targets: ["AppUI"]),
        .library(name: "DictationKit", targets: ["DictationKit"]),
        .library(name: "DictationOwnership", targets: ["DictationOwnership"]),
        .library(name: "DictationSession", targets: ["DictationSession"]),
        .library(name: "MicCapture", targets: ["MicCapture"]),
        .library(name: "SpeechCore", targets: ["SpeechCore"])
    ],
    dependencies: [
        // Exact on purpose: patch releases change decoder behavior, so a move needs paired evidence.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.2", traits: []),
        .package(url: "https://github.com/johnny4young/local-model-store.git", exact: "0.1.0")
    ],
    targets: [
        .target(name: "AppUI"),
        .target(name: "DictationKit", dependencies: ["SpeechCore"]),
        .target(name: "DictationOwnership"),
        .target(
            name: "DictationSession",
            dependencies: [
                "DictationKit", "LiveSpeech", "MicCapture", "SpeechCore",
                .product(name: "LocalModelStore", package: "local-model-store")
            ]),
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
        .testTarget(name: "DictationKitTests", dependencies: ["DictationKit", "SpeechCore"]),
        .testTarget(
            name: "DictationSessionTests",
            dependencies: [
                "DictationSession", "DictationKit", "LiveSpeech", "SpeechCore",
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
