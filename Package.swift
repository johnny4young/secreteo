// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Secreteo",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppUI", targets: ["AppUI"])
    ],
    targets: [
        .target(name: "AppUI"),
        .testTarget(name: "AppUITests", dependencies: ["AppUI"])
    ]
)
