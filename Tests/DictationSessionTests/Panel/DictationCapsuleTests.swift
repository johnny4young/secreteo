import Foundation
import Testing

@testable import DictationSession

struct DictationCapsuleTests {
    @Test
    func theLiquidRisesWithTheVoiceAndNeverLeavesTheCapsule() {
        let silence = DictationLiquidShape.fill(for: 0)
        let speech = DictationLiquidShape.fill(for: 0.031_6)
        let clipped = DictationLiquidShape.fill(for: 2)
        #expect(abs(silence - 0.062_4) < 0.000_1, "silence is a thin glow")
        #expect(abs(speech - 0.205) < 0.01, "−30 dB is half the range")
        #expect(clipped == DictationLiquidShape.ceiling)
        #expect(silence < speech && speech < clipped)

        for wave in DictationWaveformShape.waves {
            for step in 0...40 {
                let surface = DictationLiquidShape.surface(
                    at: Double(step) / 40, time: Double(step) * 0.37, wave: wave, fill: clipped)
                #expect((0...1).contains(surface))
                #expect(surface <= 0.51, "a loud voice fills about half")
            }
        }
        let wave = DictationWaveformShape.waves[0]
        #expect(
            DictationLiquidShape.surface(at: 0.4, time: 0, wave: wave, fill: speech)
                != DictationLiquidShape.surface(at: 0.4, time: 0.2, wave: wave, fill: speech))
    }

    @Test
    func theLiquidFreezesAtStopAndStepsUnderReduceMotion() {
        #expect(DictationLiquidShape.motion(microphoneIsOpen: true, reduceMotion: false) == .flowing)
        #expect(DictationLiquidShape.motion(microphoneIsOpen: false, reduceMotion: false) == .frozen)
        #expect(DictationLiquidShape.motion(microphoneIsOpen: true, reduceMotion: true) == .stepped)
        #expect(DictationLiquidShape.motion(microphoneIsOpen: false, reduceMotion: true) == .stepped)

        let heights = stride(from: Float(0), through: 1.2, by: 0.001).map { DictationLiquidShape.step(for: $0) }
        #expect(Set(heights) == Set(DictationLiquidShape.steps), "three heights and nothing between")
        #expect(heights == heights.sorted(), "a louder voice never lowers the bar")
        #expect(DictationLiquidShape.step(for: 0) == DictationLiquidShape.steps[0])
        #expect(DictationLiquidShape.step(for: 2) == DictationLiquidShape.steps[2])
    }

    @Test
    func theRimFollowsTheFace() {
        #expect(DictationCapsuleRim(face: .listening) == .voice)
        #expect(DictationCapsuleRim(face: .loading) == .loading)
        #expect(DictationCapsuleRim(face: .polishing) == .polish)
        #expect(DictationCapsuleRim(face: .notSent) == .notSent)
        #expect(DictationCapsuleRim.voice.glows && DictationCapsuleRim.polish.glows && DictationCapsuleRim.notSent.glows)
        #expect(!DictationCapsuleRim.quiet.glows && !DictationCapsuleRim.loading.glows)
        for face: SecreteoGlyphFace in [.ready, .inserted, .sent, .noSpeech, .notOwner] {
            #expect(DictationCapsuleRim(face: face) == .quiet)
        }
    }

    @Test
    func theCapsuleIsOneLineInEveryDictatingPhase() {
        for phase: DictationController.Phase in [.preparing, .listening, .delivering, .failed("x")] {
            #expect(DictationPanelLayout.isCapsule(phase))
            #expect(DictationPanelLayout.height(for: phase) == 56)
            #expect(DictationPanelLayout.height(for: phase, showsNotice: true) == 82, "the notice hangs under it")
        }
        #expect(DictationPanelLayout.width == 520)
    }

    @Test
    func outcomesKeepTheirOwnHeights() {
        #expect(DictationPanelLayout.height(for: .verified(3)) == 96)
        for phase: DictationController.Phase in [.recovery(.cancelled), .dispatched(3), .noSpeech] {
            #expect(!DictationPanelLayout.isCapsule(phase))
            #expect(DictationPanelLayout.height(for: phase) == 288)
            #expect(DictationPanelLayout.height(for: phase, showsNotice: true) == 288)
        }
        #expect(!DictationPanelLayout.isCapsule(.verified(3)))
        #expect(!DictationPanelLayout.isCapsule(.idle))
    }

    @Test
    func theTranscriptSplitsSettledWordsFromTheProvisionalTail() {
        #expect(
            DictationPanelTranscript.visible(confirmed: "Hola Lucía,", partial: "gracias por")
                == .init(confirmed: "Hola Lucía,", partial: " gracias por"))
        #expect(
            DictationPanelTranscript.visible(confirmed: "Hola", partial: "") == .init(confirmed: "Hola", partial: ""))
        #expect(
            DictationPanelTranscript.visible(confirmed: "", partial: "hola") == .init(confirmed: "", partial: " hola"))
    }

    @Test
    func aLongTranscriptKeepsItsNewestWords() {
        let confirmed = "uno dos tres cuatro cinco seis siete ocho"
        let visible = DictationPanelTranscript.visible(confirmed: confirmed, partial: "nueve diez", limit: 24)
        #expect(visible.confirmed.hasPrefix("…"))
        #expect(visible.partial == " nueve diez", "the tail stays whole and provisional")
        #expect((visible.confirmed + visible.partial).hasSuffix("ocho nueve diez"))
        #expect(!visible.confirmed.dropFirst().hasPrefix(" "), "it starts on a word")

        let tailOnly = DictationPanelTranscript.visible(
            confirmed: "uno", partial: "dos tres cuatro cinco seis siete ocho nueve", limit: 12)
        #expect(tailOnly.confirmed == "…")
        #expect(tailOnly.partial.hasSuffix("ocho nueve"))
    }
}
