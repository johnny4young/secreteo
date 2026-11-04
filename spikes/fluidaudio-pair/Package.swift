// swift-tools-version: 6.2
import Foundation
import PackageDescription
let fork = ProcessInfo.processInfo.environment["BENCH_FLUID"] == "fork"
let fluid: Package.Dependency = fork
    ? .package(url: "https://github.com/johnny4young/FluidAudio.git", revision: "16ff239818ddb6787629dab38ae43e8bdd0e7546", traits: [])
    : .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.2", traits: [])
let package = Package(name: "bench", platforms: [.macOS(.v26)],
  dependencies: [fluid, .package(url: "https://github.com/johnny4young/local-model-store.git", exact: "0.1.0")],
  targets: [
    .target(name: "SpeechCore"),
    .target(name: "LiveSpeech", dependencies: ["SpeechCore", .product(name: "FluidAudio", package: "FluidAudio"), .product(name: "LocalModelStore", package: "local-model-store")]),
    .executableTarget(name: "fluid-bench", dependencies: ["LiveSpeech", "SpeechCore", .product(name: "LocalModelStore", package: "local-model-store")]),
  ])
