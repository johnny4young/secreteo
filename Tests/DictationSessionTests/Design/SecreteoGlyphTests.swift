import AppKit
import Testing

@testable import DictationSession

struct SecreteoGlyphTests {
    @Test(arguments: [
        (DictationController.Phase.idle, false, SecreteoGlyphFace.ready),
        (.preparing, false, .loading),
        (.listening, true, .loading),
        (.listening, false, .listening),
        (.delivering, false, .polishing),
        (.verified(3), false, .inserted),
        (.dispatched(3), false, .sent),
        (.noSpeech, false, .noSpeech),
        (.failed("x"), false, .notSent),
        (.recovery(.cancelled), false, .notSent)
    ])
    func eachPhaseShowsItsFace(_ phase: DictationController.Phase, _ loading: Bool, _ face: SecreteoGlyphFace) {
        #expect(DictationController.statusFace(for: phase, isLoadingModel: loading) == face)
    }

    @Test(arguments: SecreteoGlyphFace.allCases)
    func everyFaceDrawsATemplateForTheMenuBar(_ face: SecreteoGlyphFace) throws {
        let image = face.templateImage()
        #expect(image.isTemplate)
        #expect(image.size.height == 18)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 40, height: 36))
        NSGraphicsContext.restoreGraphicsState()
        let inked = (0..<40).flatMap { x in (0..<36).map { (x, $0) } }
            .filter { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 0) > 0.5 }.count
        #expect(inked > 40, "the glyph drew too little")
    }

    @Test
    func facesThatMeanSomethingCarryTheirColour() {
        #expect(SecreteoGlyphFace.inserted.tint == SecreteoPalette.verified)
        #expect(SecreteoGlyphFace.sent.tint == SecreteoPalette.amber)
        #expect(SecreteoGlyphFace.notSent.tint == SecreteoPalette.notSent)
        #expect(SecreteoGlyphFace.notSaved.tint == SecreteoPalette.notSent)
        #expect(SecreteoGlyphFace.notSaved.accessibilityName == L10n.text("Not saved to your dictation history."))
        #expect(SecreteoGlyphFace.ready.tint == nil)
    }

    @Test
    func onlyNotSentBreaksTheRightParenthesis() {
        for face in SecreteoGlyphFace.allCases {
            let rim = SecreteoGlyphGeometry.marks(face).prefix(2).map(\.path)
            #expect((rim.last == SecreteoGlyphGeometry.rightArc) == (face != .notSent), "\(face)")
        }
    }
}
