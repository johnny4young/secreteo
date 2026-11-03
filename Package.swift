// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Secreteo",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppUI", targets: ["AppUI"]),
        .library(name: "DictationOwnership", targets: ["DictationOwnership"])
    ],
    targets: [
        .target(name: "AppUI"),
        .target(name: "DictationOwnership"),
        .executableTarget(name: "ownership-test-client", dependencies: ["DictationOwnership"], path: "Tests/OwnershipTestClient"),
        .testTarget(name: "AppUITests", dependencies: ["AppUI"]),
        .testTarget(name: "DictationOwnershipTests", dependencies: ["DictationOwnership", "ownership-test-client"])
    ]
)
