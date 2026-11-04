// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Secreteo",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppUI", targets: ["AppUI"]),
        .library(name: "DictationKit", targets: ["DictationKit"]),
        .library(name: "DictationOwnership", targets: ["DictationOwnership"]),
        .library(name: "SpeechCore", targets: ["SpeechCore"])
    ],
    targets: [
        .target(name: "AppUI"),
        .target(name: "DictationKit", dependencies: ["SpeechCore"]),
        .target(name: "DictationOwnership"),
        .target(name: "SpeechCore"),
        .executableTarget(name: "ownership-test-client", dependencies: ["DictationOwnership"], path: "Tests/OwnershipTestClient"),
        .testTarget(name: "AppUITests", dependencies: ["AppUI"]),
        .testTarget(name: "DictationKitTests", dependencies: ["DictationKit", "SpeechCore"]),
        .testTarget(name: "DictationOwnershipTests", dependencies: ["DictationOwnership", "ownership-test-client"])
    ]
)
