import DictationOwnership

/// The other app that can own dictation here. Its builds before the protocol take no lock, so
/// seeing one running can only make this app refuse. The ratchet allows these values in this file only.
enum KnownDictationPeers {
    static let all = ["app.portavoz.mac", "app.portavoz.mac.dev"].map {
        KnownPeer(identifier: $0, preferenceKey: "globalDictationEnabled")
    }
}
