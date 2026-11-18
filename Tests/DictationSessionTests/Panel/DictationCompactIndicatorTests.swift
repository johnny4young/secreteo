import AppKit
import SwiftUI
import XCTest

@testable import DictationSession

final class DictationCompactIndicatorTests: XCTestCase {
    func testOnlyCaptureShrinksTheStrip() throws {
        let suite = "compact-indicator-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        isolateArgumentDomain()
        XCTAssertFalse(DictationCompactIndicator.applies(to: .listening, defaults: defaults), "off by default")

        defaults.set(true, forKey: DictationCompactIndicator.defaultsKey)
        for phase: DictationController.Phase in [.preparing, .listening, .delivering] {
            XCTAssertTrue(DictationCompactIndicator.applies(to: phase, defaults: defaults), "\(phase)")
        }
        for phase: DictationController.Phase in [.idle, .noSpeech, .failed("x"), .recovery(.cancelled)] {
            XCTAssertFalse(DictationCompactIndicator.applies(to: phase, defaults: defaults),
                           "\(phase) needs the full panel's actions")
        }
        for phase: DictationController.Phase in [.verified(3), .dispatched(3)] {
            XCTAssertFalse(DictationCompactIndicator.applies(to: phase, defaults: defaults),
                           "\(phase): words that went out close the panel, and a pill needs its words")
        }
    }

    func testTheGlyphIsAloneUntilAnOptionAddsTheTimeOrTheBead() throws {
        let suite = "compact-options-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        isolateArgumentDomain()
        XCTAssertEqual(DictationCompactIndicator.Options.current(defaults), .init(), "both options are off by default")
        XCTAssertEqual(DictationCompactIndicator.size(for: .init()), NSSize(width: 30, height: 24))
        XCTAssertEqual(
            DictationCompactIndicator.size(for: .init(showsElapsedTime: true)), NSSize(width: 68, height: 24))
        XCTAssertEqual(DictationCompactIndicator.size(for: .init(showsBackdrop: true)), NSSize(width: 30, height: 30))
        XCTAssertEqual(
            DictationCompactIndicator.size(for: .init(showsElapsedTime: true, showsBackdrop: true)),
            NSSize(width: 68, height: 30))
        XCTAssertEqual(
            DictationCompactIndicator.windowSize(for: .init()), NSSize(width: 38, height: 32),
            "4 pt of clear room on every side holds the shadow")
        XCTAssertEqual(
            DictationCompactIndicator.windowSize(for: .init(showsElapsedTime: true, showsBackdrop: true)),
            NSSize(width: 76, height: 38))

        defaults.set(true, forKey: "dictationCompactShowsElapsedTime")
        defaults.set(true, forKey: "dictationCompactShowsBackdrop")
        XCTAssertEqual(
            DictationCompactIndicator.Options.current(defaults), .init(showsElapsedTime: true, showsBackdrop: true))
    }

    func testItSitsUnderTheCaretAndFallsBackToTheBottomOfTheScreen() {
        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 820)
        let size = NSSize(width: 30, height: 24)
        let caret = NSRect(x: 400, y: 500, width: 2, height: 18)
        XCTAssertEqual(
            DictationCompactIndicator.origin(for: size, near: .caret(caret), in: visible), NSPoint(x: 396, y: 466),
            "the glyph inside the window's margin: left edge on the caret, 6 pt under its line")
        XCTAssertEqual(DictationCompactIndicator.pinnedEdge(for: size, near: .caret(caret), in: visible), .top)

        let low = NSRect(x: 1_430, y: 50, width: 2, height: 18)
        XCTAssertEqual(
            DictationCompactIndicator.origin(for: size, near: .caret(low), in: visible), NSPoint(x: 1_406, y: 70),
            "above the line and inside the screen when there is no room below")
        XCTAssertEqual(DictationCompactIndicator.pinnedEdge(for: size, near: .caret(low), in: visible), .bottom)

        let fallback = NSPoint(x: 701, y: 84)
        XCTAssertEqual(DictationCompactIndicator.origin(for: size, near: nil, in: visible), fallback)
        XCTAssertEqual(
            DictationCompactIndicator.origin(for: size, near: .pointer(NSPoint(x: 10, y: 10)), in: visible), fallback,
            "a pointer is not a caret")
        XCTAssertEqual(DictationCompactIndicator.pinnedEdge(for: size, near: nil, in: visible), .bottom)
    }

    func testTheGapBetweenTheParenthesesIsTheMeter() {
        XCTAssertEqual(DictationAsideShape.openness(for: 0), 0, "closed in silence")
        XCTAssertEqual(DictationAsideShape.openness(for: 0.031_6), 0.5, accuracy: 0.01)
        XCTAssertEqual(DictationAsideShape.openness(for: 2), 1)
        XCTAssertEqual(DictationAsideShape.spread(for: 0), 0)
        XCTAssertEqual(DictationAsideShape.spread(for: 0.5), 1, "speaking opens 1 pt each side")
        XCTAssertEqual(DictationAsideShape.spread(for: 1), 2)
        XCTAssertEqual(DictationAsideShape.spread(for: 3), 2, "never past 2 pt")
        XCTAssertEqual(DictationAsideShape.barScale(for: 0), 0.45)
        XCTAssertEqual(DictationAsideShape.barScale(for: 1), 1)
        XCTAssertLessThan(DictationAsideShape.barScale(for: 0.3), DictationAsideShape.barScale(for: 0.6))
        XCTAssertEqual(
            [0, 0.002, 0.05, 1].map { DictationAsideShape.barStep(for: $0) }, [0.45, 0.45, 0.72, 1],
            "Reduce Motion rests on three heights")
    }

    func testTheGlyphOpensAtOnceAndClosesOverTheRelease() {
        XCTAssertEqual(DictationAsideShape.envelope(from: 0.1, to: 0.9, elapsed: 1.0 / 30), 0.9, "fast attack")
        XCTAssertEqual(DictationAsideShape.envelope(from: 1, to: 0, elapsed: 0.09), 0.5, accuracy: 0.000_1)
        XCTAssertEqual(DictationAsideShape.envelope(from: 1, to: 0, elapsed: 0.18), 0, accuracy: 0.000_1)
        XCTAssertEqual(DictationAsideShape.envelope(from: 1, to: 0.8, elapsed: 0.18), 0.8, "never under the voice")
        XCTAssertEqual(DictationAsideShape.frameInterval, 1.0 / 30)
    }

    func testAResultHoldsItsFaceAndAShortPressIsAClick() {
        XCTAssertEqual(DictationCompactIndicator.hold(for: .noSpeech), .milliseconds(1_200))
        XCTAssertNil(DictationCompactIndicator.hold(for: .verified(3)), "words that went out close the panel")
        XCTAssertNil(DictationCompactIndicator.hold(for: .dispatched(3)))
        XCTAssertNil(DictationCompactIndicator.hold(for: .listening))
        XCTAssertNil(DictationCompactIndicator.hold(for: .delivering))
        XCTAssertNil(DictationCompactIndicator.hold(for: .recovery(.cancelled)), "the card stays until you choose")
        XCTAssertEqual(DictationCompactIndicator.growth, 0.32)
        XCTAssertEqual(DictationCompactIndicator.growthAnchor(pinned: .top, atCaret: true), .topLeading)
        XCTAssertEqual(DictationCompactIndicator.growthAnchor(pinned: .bottom, atCaret: true), .bottomLeading)
        XCTAssertEqual(DictationCompactIndicator.growthAnchor(pinned: .bottom, atCaret: false), .bottom)
        XCTAssertEqual(DictationCompactIndicator.growthAnchor(pinned: .top, atCaret: false), .top)
        XCTAssertTrue(DictationCompactIndicator.isClick(translation: CGSize(width: 2, height: -2)))
        XCTAssertFalse(DictationCompactIndicator.isClick(translation: CGSize(width: 3, height: 3)))
    }

    func testASecondClickNeverLandsOnWhatTheFirstOneOpened() {
        XCTAssertFalse(DictationCompactIndicator.swallowsPress(clickCount: 1, sinceExpansion: nil, doubleClick: 0.5))
        XCTAssertTrue(DictationCompactIndicator.swallowsPress(clickCount: 2, sinceExpansion: nil, doubleClick: 0.5))
        XCTAssertTrue(DictationCompactIndicator.swallowsPress(clickCount: 1, sinceExpansion: 0.2, doubleClick: 0.5))
        XCTAssertTrue(
            DictationCompactIndicator.swallowsPress(clickCount: 1, sinceExpansion: 0.3, doubleClick: 0.1),
            "at least while the capsule grows")
        XCTAssertFalse(DictationCompactIndicator.swallowsPress(clickCount: 1, sinceExpansion: 0.6, doubleClick: 0.5))

        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 820)
        let capsule = NSSize(width: DictationPanelLayout.width, height: DictationPanelLayout.capsuleHeight)
        let card = NSSize(width: DictationPanelLayout.width, height: 288)
        let atEdge = NSRect(x: visible.maxX - 34, y: 500, width: 30, height: 24)
        for (size, pinned) in [(capsule, DictationPanelAnchor.PinnedEdge.top), (card, .top), (card, .bottom)] {
            let origin = DictationCompactIndicator.origin(
                growingFrom: atEdge, to: size, pinned: pinned, in: visible, atCaret: true)
            let controls = NSRect(
                x: origin.x + size.width - DictationCompactIndicator.trailingControls, y: origin.y,
                width: DictationCompactIndicator.trailingControls, height: size.height)
            XCTAssertFalse(controls.intersects(atEdge), "Cancel and Discard are never under the glyph just clicked")
            XCTAssertGreaterThanOrEqual(origin.x, visible.minX)
        }
        XCTAssertGreaterThan(
            DictationCompactIndicator.trailingControls,
            DictationCapsuleBudget.trailing + DictationCapsuleBudget.cancel, "the zone covers the capsule's Cancel")

        let inText = NSRect(x: 400, y: 500, width: 30, height: 24)
        XCTAssertEqual(
            DictationCompactIndicator.origin(
                growingFrom: inText, to: capsule, pinned: .top, in: visible, atCaret: true),
            NSPoint(x: 400, y: 468), "anywhere else it grows from the caret")
    }

    func testVoiceOverHearsOneButtonAndTheOutcome() {
        XCTAssertEqual(
            DictationCompactIndicator.accessibilityLabel(face: .listening, time: "0:07"),
            "Secreteo, \(SecreteoGlyphFace.listening.accessibilityName), 0:07")
        XCTAssertEqual(
            DictationCompactIndicator.accessibilityLabel(face: .polishing, time: nil),
            "Secreteo, \(SecreteoGlyphFace.polishing.accessibilityName)")
        XCTAssertEqual(
            DictationCompactIndicator.accessibilityLabel(face: .inserted, time: ""),
            "Secreteo, \(SecreteoGlyphFace.inserted.accessibilityName)", "a result has no time to read")
        XCTAssertEqual(
            DictationCompactIndicator.announcement(for: .verified(3)), SecreteoGlyphFace.inserted.accessibilityName)
        XCTAssertEqual(
            DictationCompactIndicator.announcement(for: .dispatched(3)), SecreteoGlyphFace.sent.accessibilityName)
        XCTAssertNil(DictationCompactIndicator.announcement(for: .listening))
        XCTAssertNil(DictationCompactIndicator.announcement(for: .delivering))
    }

    func testEveryFaceKeepsItsContrastOnTheInkOutline() {
        for face in SecreteoGlyphFace.allCases {
            let ink = DictationAsideShape.ink(for: face)
            XCTAssertEqual(ink.light, ink.dark, "\(face) does not follow the appearance: the surface is unknown")
        }
        XCTAssertEqual(DictationAsideShape.ink(for: .inserted), SecreteoPalette.capsuleVerified)
        XCTAssertEqual(DictationAsideShape.ink(for: .notSent), SecreteoPalette.capsuleNotSent)
        XCTAssertEqual(DictationAsideShape.ink(for: .listening), SecreteoPalette.capsuleText)
    }

    func testElapsedTimeReadsAsMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(DictationCompactIndicator.elapsed(since: nil, now: start), "0:00")
        XCTAssertEqual(DictationCompactIndicator.elapsed(since: start, now: start.addingTimeInterval(7.9)), "0:07")
        XCTAssertEqual(DictationCompactIndicator.elapsed(since: start, now: start.addingTimeInterval(125)), "2:05")
        XCTAssertEqual(DictationCompactIndicator.elapsed(since: start, now: start.addingTimeInterval(-3)), "0:00")
    }
}

final class DictationWaveformTests: XCTestCase {
    func testSilenceStaysAFlatLineAndLoudSpeechFillsTheHeight() {
        XCTAssertEqual(DictationWaveformShape.amplitude(for: 0), 0.04, "silence keeps a visible line")
        XCTAssertEqual(DictationWaveformShape.amplitude(for: 0.000_5), 0.04, accuracy: 0.000_1)
        XCTAssertEqual(DictationWaveformShape.amplitude(for: 0.031_6), 0.5, accuracy: 0.01, "−30 dB is half height")
        XCTAssertEqual(DictationWaveformShape.amplitude(for: 2), 1, "clipped input never overflows")
    }

    func testEveryWaveMeetsTheCenterAtBothEndsAndStaysInBounds() {
        for wave in DictationWaveformShape.waves {
            XCTAssertEqual(DictationWaveformShape.offset(at: 0, time: 3.7, wave: wave, amplitude: 1), 0, accuracy: 1e-9)
            XCTAssertEqual(DictationWaveformShape.offset(at: 1, time: 3.7, wave: wave, amplitude: 1), 0, accuracy: 1e-9)
            for step in 0...20 {
                let y = DictationWaveformShape.offset(at: Double(step) / 20, time: 1.3, wave: wave, amplitude: 1)
                XCTAssertLessThanOrEqual(abs(y), 1)
            }
        }
        let moving = DictationWaveformShape.waves[0]
        XCTAssertNotEqual(
            DictationWaveformShape.offset(at: 0.4, time: 0, wave: moving, amplitude: 1),
            DictationWaveformShape.offset(at: 0.4, time: 0.2, wave: moving, amplitude: 1),
            "the waves move over time")
    }
}
