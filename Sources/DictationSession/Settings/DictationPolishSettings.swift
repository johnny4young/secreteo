import AppKit
import Polish
import SwiftUI

/// The engine Polish and Rewrite use. Both run on this Mac.
struct DictationPolishSettings: View {
    let dictation: DictationFeature
    /// Nil while checking or when Ollama does not answer.
    @State private var ollamaModels: [OllamaService.Model]?
    @State private var checkedOllama = false

    var body: some View {
        let capability = dictation.foundationModelsCapability
        Section("Polish") {
            Picker("Polish With", selection: dictation.polishEngineBinding(capability: capability)) {
                Text("Apple Intelligence").tag(DictationPolishEngine.appleOnDevice)
                Text("Ollama").tag(DictationPolishEngine.ollama)
            }
            .accessibilityIdentifier("settings-dictation-polish-engine")
            switch dictation.polishEngine(capability: capability) {
            case .appleOnDevice:
                if case .unavailable(let reason) = capability {
                    Text(L10n.format("Apple Intelligence is unavailable: %@.", reason))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings-dictation-polish-unavailable")
                }
            case .ollama:
                ollamaRows
            }
        }
        // The window is kept when closed, so Ollama may have started or pulled a model since.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard checkedOllama, dictation.polishEngine(capability: capability) == .ollama else { return }
            Task { await refresh() }
        }
    }

    @ViewBuilder private var ollamaRows: some View {
        let model = dictation.polishOllamaModelBinding
        if ollamaModels?.isEmpty == true, model.wrappedValue.isEmpty {
            Text("Ollama has no models yet. Pull one with “ollama pull”.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings-dictation-polish-ollama-empty")
            checkAgain
        } else if let ollamaModels {
            Picker("Ollama Model", selection: model) {
                if model.wrappedValue.isEmpty {
                    Text("None").tag("")
                }
                ForEach(ollamaModels) { entry in
                    Text(verbatim: entry.name).tag(entry.name)
                }
                if !model.wrappedValue.isEmpty, !ollamaModels.contains(where: { $0.name == model.wrappedValue }) {
                    Text(L10n.format("%@ (Not Installed)", model.wrappedValue)).tag(model.wrappedValue)
                }
            }
            .accessibilityIdentifier("settings-dictation-polish-ollama-model")
        } else if checkedOllama {
            Text("Ollama is not running on this Mac.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings-dictation-polish-ollama-missing")
            checkAgain
        } else {
            ProgressView()
                .controlSize(.small)
                .accessibilityIdentifier("settings-dictation-polish-ollama-checking")
                .task { await refresh() }
        }
    }

    private var checkAgain: some View {
        Button("Check Again") { Task { await refresh() } }
            .accessibilityIdentifier("settings-dictation-polish-ollama-retry")
    }

    private func refresh() async {
        ollamaModels = await dictation.ollamaModels()
        checkedOllama = true
    }
}
