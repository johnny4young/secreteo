import DictationOwnership

/// The other app that can own dictation here. Its builds before the protocol take no lock, so
/// seeing one running can only make this app refuse. The ratchet allows these values in this file only.
enum KnownDictationPeers {
    /// The Release build, whose saved settings Settings can import.
    static let release = "app.portavoz.mac"
    static let all = [release, "app.portavoz.mac.dev"].map {
        KnownPeer(identifier: $0, preferenceKey: "globalDictationEnabled")
    }
}
