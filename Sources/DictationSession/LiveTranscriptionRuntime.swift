import LiveSpeech

/// One pinned process runtime plus the composition-owned completion that ends
/// its residency lease. The bridge never knows which concrete model registry
/// backs the handle.
struct LiveTranscriptionRuntime: Sendable {
    let engine: any TranscriptionEngine
    /// The lane that was acquired; nil for fixture and benchmark engines.
    let lane: LiveSpeechSelection?
    private let completion: @MainActor @Sendable () -> Void

    init(
        engine: any TranscriptionEngine,
        lane: LiveSpeechSelection? = nil,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        self.engine = engine
        self.lane = lane
        self.completion = completion
    }

    @MainActor
    func finish() {
        completion()
    }
}
