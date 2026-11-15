import AppKit
import Foundation
import SwiftUI
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
        #expect(Set(heights) == Set(DictationLiquidShape.steps()), "three heights and nothing between")
        #expect(heights == heights.sorted(), "a louder voice never lowers the bar")
        #expect(DictationLiquidShape.step(for: 0) == DictationLiquidShape.steps()[0])
        #expect(DictationLiquidShape.step(for: 2) == DictationLiquidShape.steps()[2])
    }

    @Test
    func theRimFollowsTheFace() {
        #expect(DictationCapsuleRim(face: .listening) == .voice)
        #expect(DictationCapsuleRim(face: .loading) == .loading)
        #expect(DictationCapsuleRim(face: .polishing) == .quiet)
        #expect(DictationCapsuleRim(face: .notSent) == .notSent)
        #expect(DictationCapsuleRim.voice.glows && DictationCapsuleRim.polish.glows && DictationCapsuleRim.notSent.glows)
        #expect(DictationCapsuleRim(face: .inserted) == .verified)
        #expect(DictationCapsuleRim(face: .sent) == .sent)
        for rim: DictationCapsuleRim in [.quiet, .loading, .verified, .sent] {
            #expect(!rim.glows, "only the voice, the polish and a refusal glow")
        }
        #expect(DictationCapsuleRim(face: .polishing, transforms: true) == .polish)
        #expect(DictationCapsuleRim(face: .polishing, transforms: false) == .quiet, "a plain paste is not copper")
        for face: SecreteoGlyphFace in [.ready, .noSpeech, .notOwner] {
            #expect(DictationCapsuleRim(face: face) == .quiet)
        }
    }

    @Test
    func theCapsuleIsOneLineInEveryDictatingPhase() {
        for phase: DictationController.Phase in [.preparing, .listening, .delivering, .failed("x")] {
            #expect(DictationPanelLayout.isCapsule(phase))
            #expect(!DictationPanelLayout.isCard(phase))
        }
        #expect(DictationPanelLayout.capsuleHeight() == 56)
        #expect(DictationPanelLayout.capsuleHeight(showsNotice: true) == 82, "the notice hangs under it")
        #expect(DictationPanelLayout.width == 520)
    }

    @Test
    func anOutcomeIsAsTallAsItsContent() {
        let screen = CGSize(width: 1_512, height: 944)
        #expect(DictationPanelLayout.outcomeSize(measuredHeight: 187.2, visible: screen) == NSSize(width: 520, height: 188))
        #expect(DictationPanelLayout.outcomeSize(measuredHeight: 56, visible: screen) == NSSize(width: 520, height: 56))
        #expect(
            DictationPanelLayout.outcomeSize(measuredHeight: 86.5, visible: nil) == NSSize(width: 520, height: 87),
            "without a screen it is still the content")
        for unmeasured: CGFloat? in [nil, 0, 12, -4, .infinity, .nan] {
            #expect(
                DictationPanelLayout.outcomeSize(measuredHeight: unmeasured, visible: screen)
                    == NSSize(width: 520, height: 56),
                "never shorter than the capsule")
        }
    }

    @Test
    func anOutcomeNeverLeavesTheScreen() {
        #expect(
            DictationPanelLayout.outcomeSize(measuredHeight: 900, visible: CGSize(width: 1_280, height: 640.5))
                == NSSize(width: 520, height: 640))
        #expect(
            DictationPanelLayout.outcomeSize(measuredHeight: 200, visible: CGSize(width: 480.9, height: 300))
                == NSSize(width: 480, height: 200))
        #expect(
            DictationPanelLayout.outcomeSize(measuredHeight: 200, visible: .zero) == NSSize(width: 520, height: 200),
            "an unknown screen clamps nothing")
    }

    @Test
    func theWordsGrowToAFewLinesAndThenScroll() {
        #expect(DictationPanelLayout.wordsHeight(forContent: 28.4) == 29)
        #expect(DictationPanelLayout.wordsHeight(forContent: 87) == 87)
        #expect(DictationPanelLayout.wordsHeight(forContent: 4_000) == DictationPanelLayout.wordsMaxHeight)
        for empty: CGFloat in [0, -1, .nan, .infinity] {
            #expect(DictationPanelLayout.wordsHeight(forContent: empty) == 0)
        }
    }

    @Test
    func onlyTheOutcomesWithWordsOpenIntoACard() {
        for phase: DictationController.Phase in [.recovery(.cancelled), .dispatched(3), .noSpeech] {
            #expect(DictationPanelLayout.isCard(phase))
            #expect(!DictationPanelLayout.isCapsule(phase))
        }
        #expect(!DictationPanelLayout.isCard(.verified(3)) && !DictationPanelLayout.isCapsule(.verified(3)))
        #expect(!DictationPanelLayout.isCard(.idle) && !DictationPanelLayout.isCapsule(.idle))
    }

    @Test @MainActor
    func cancellingDoesNotResizeAPanelStillOnScreen() {
        let idle = DictationController(presentsPanel: false)
        #expect(idle.phase == .idle)
        #expect(
            DictationPanelLayout.size(for: idle, outcomeHeight: 240, visible: CGSize(width: 1_512, height: 944))
                == NSSize(width: 520, height: DictationPanelLayout.capsuleHeight()),
            "idle keeps the capsule's height, whatever an earlier card measured")
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

    @Test
    func aPausedLiquidIgnoresNewLevelsSoNothingRedrawsAfterStop() {
        func liquid(_ level: Float, paused: Bool) -> DictationLiquidLevel {
            DictationLiquidLevel(
                level: level, motion: paused ? .frozen : .flowing, paused: paused, dimmed: false, opaque: false)
        }
        #expect(liquid(0.1, paused: true) == liquid(0.9, paused: true))
        #expect(liquid(0.1, paused: false) != liquid(0.9, paused: false))
        #expect(liquid(0.1, paused: false) != liquid(0.1, paused: true), "Stop itself is drawn once")
    }

    @Test
    func nothingAnimatesOnceTheMicrophoneCloses() {
        #expect(DictationCapsuleMotion.settle(microphoneIsOpen: true) == .easeOut(duration: 0.14))
        #expect(DictationCapsuleMotion.settle(microphoneIsOpen: false) == nil)
        #expect(DictationCapsuleMotion.phaseChange(microphoneIsOpen: true, reduceMotion: false) != nil)
        #expect(DictationCapsuleMotion.phaseChange(microphoneIsOpen: false, reduceMotion: false) == nil)
        #expect(DictationCapsuleMotion.phaseChange(microphoneIsOpen: true, reduceMotion: true) == nil)
    }

    @Test
    func theElapsedTimeStopsAtStop() {
        let stop = Date(timeIntervalSince1970: 1_000)
        let later = stop.addingTimeInterval(9)
        #expect(DictationCapsuleMotion.clock(tick: later, stoppedAt: nil) == later)
        #expect(DictationCapsuleMotion.clock(tick: later, stoppedAt: stop) == stop)
    }

    @Test
    func theWordsKeepAtLeastFortyFivePercentOfTheLine() {
        let budget = DictationCapsuleBudget.self
        #expect(budget.words >= budget.content * 0.45)
        let used = budget.face + budget.words + budget.chips + budget.cancel + 3 * budget.spacing
        #expect(used <= budget.content)
        #expect(budget.leading + budget.content + budget.trailing == DictationPanelLayout.width)
    }

    /// The chips' box never exceeds its budget, whatever the names: it falls back to a tighter row.
    @Test
    @MainActor
    func longNamesNeverTakeTheWordsRoom() {
        let limit = DictationCapsuleBudget.chips
        func width(_ target: String, _ recipe: String) -> CGFloat {
            let chips = DictationCappedWidth(limit: limit) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { Text(target).fixedSize(); Text(recipe).fixedSize(); Text(verbatim: "0:07") }
                    HStack(spacing: 6) { Text(verbatim: "✎"); Text(recipe).lineLimit(1); Text(verbatim: "0:07") }
                }
            }
            return NSHostingView(rootView: chips).fittingSize.width
        }
        let long = width("Microsoft Visual Studio Code Insiders", "Polish: Formal letter to the committee")
        #expect(long <= limit)
        #expect(long > limit - 40, "the tighter row still uses its room")
        let short = width("Notes", "Clean")
        #expect(short < limit - 40, "short names hug their content")
    }

    @Test(arguments: [false, true])
    func theWordsKeepTheirContrastOverTheLoudestLight(opaque: Bool) {
        let fill = DictationLiquidShape.fill(for: 2, opaque: opaque)
        let crest = fill * DictationLiquidShape.peak
        if opaque {
            #expect(crest <= DictationLiquidShape.clearBelow, "solid light stays under the words")
            #expect(DictationLiquidShape.steps(opaque: true).allSatisfy { $0 <= DictationLiquidShape.clearBelow })
            return
        }
        #expect(crest > DictationLiquidShape.textBand, "a loud voice does reach the words, so the fade must hold")
        let strength = DictationLiquidShape.strength(at: DictationLiquidShape.textBand)
        #expect(DictationLiquidShape.strength(at: 1) == strength)
        #expect(DictationLiquidShape.strength(at: 0) == 1)
        let lacquer = Self.rgb(SecreteoPalette.lacquer.dark)
        for stop in DictationLiquidShape.body {
            // Both waves and the crest's highlight, all at their strongest, behind the text band.
            var behind = Self.over(
                Self.rgb(stop.color.dark), stop.alpha * DictationLiquidShape.backWaveOpacity * strength, lacquer)
            behind = Self.over(Self.rgb(stop.color.dark), stop.alpha * strength, behind)
            let highlight = DictationLiquidShape.highlight[0]
            behind = Self.over(Self.rgb(highlight.color.dark), highlight.alpha * strength, behind)
            let settled = Self.rgb(SecreteoPalette.capsuleText.dark)
            let provisional = Self.over(
                Self.rgb(SecreteoPalette.capsuleProvisionalText.dark),
                DictationCapsuleTranscript.provisionalOpacity, behind)
            #expect(Self.contrast(settled, behind) >= 4.5, "settled words at \(stop.location)")
            #expect(Self.contrast(provisional, behind) >= 4.5, "provisional words at \(stop.location)")
        }
    }

    private typealias RGB = (red: Double, green: Double, blue: Double)

    private static func rgb(_ hex: UInt32) -> RGB {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func over(_ top: RGB, _ alpha: Double, _ bottom: RGB) -> RGB {
        (
            top.red * alpha + bottom.red * (1 - alpha), top.green * alpha + bottom.green * (1 - alpha),
            top.blue * alpha + bottom.blue * (1 - alpha)
        )
    }

    private static func contrast(_ one: RGB, _ other: RGB) -> Double {
        func luminance(_ color: RGB) -> Double {
            func channel(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
        }
        let lighter = max(luminance(one), luminance(other)), darker = min(luminance(one), luminance(other))
        return (lighter + 0.05) / (darker + 0.05)
    }
}
