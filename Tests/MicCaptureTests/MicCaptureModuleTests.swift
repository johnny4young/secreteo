import Foundation
import Testing

struct MicCaptureModuleTests {
    @Test
    func captureStaysFreeOfUIAndModels() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MicCapture")
        let allowed: Set<String> = ["AudioToolbox", "AVFAudio", "AVFoundation", "CoreAudio", "Foundation", "os", "SpeechCore"]
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            let imports = text.split(separator: "\n").compactMap { line -> String? in
                let words = line.split(separator: " ")
                guard let keyword = words.firstIndex(of: "import"), keyword + 1 < words.count, !line.hasPrefix("//") else {
                    return nil
                }
                return String(words[keyword + 1])
            }
            #expect(Set(imports).isSubset(of: allowed), "\(name) imports \(imports)")
        }
    }
}
