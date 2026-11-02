import CoreML
import Foundation

// Usage: specialize <model-dir> <parakeet|silero>. Prints elapsed milliseconds as JSON.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let parts: [(String, MLComputeUnits)] = CommandLine.arguments[2] == "silero"
    ? [("silero-vad-unified-256ms-v6.2.1.mlmodelc", .cpuOnly)]
    : [
        ("Preprocessor.mlmodelc", .cpuOnly),
        ("Encoder.mlmodelc", .cpuAndNeuralEngine),
        ("Decoder.mlmodelc", .cpuAndNeuralEngine),
        ("JointDecisionv3.mlmodelc", .cpuAndNeuralEngine)
    ]

var elapsed: [String: Double] = [:]
let clock = ContinuousClock()
for (name, units) in parts {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = units
    let duration = try clock.measure {
        _ = try MLModel(contentsOf: directory.appendingPathComponent(name), configuration: configuration)
    }
    elapsed[name] = Double(duration.components.seconds) * 1000
        + Double(duration.components.attoseconds) / 1e15
}
elapsed["total"] = elapsed.values.reduce(0, +)
let data = try JSONSerialization.data(withJSONObject: elapsed, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
