import AppKit
import SwiftUI

/// The capsule's face: what sits between the two parentheses. The menu bar, the capsule, the
/// small indicator and History all draw from this one set.
public enum SecreteoGlyphFace: String, CaseIterable, Sendable {
    case ready, listening, loading, polishing, inserted, sent, notSent, notSaved, noSpeech, notOwner
}

/// The glyph's geometry in a 24 × 22 box, shared by SwiftUI and the template image.
enum SecreteoGlyphGeometry {
    static let box = CGSize(width: 24, height: 22)
    static let lineWidth: CGFloat = 1.9

    enum Ink { case line, voice, tint }

    struct Mark {
        let path: CGPath
        let filled: Bool
        var ink = Ink.line
        var alpha: CGFloat = 1
        var dashed = false
    }

    static func marks(_ face: SecreteoGlyphFace) -> [Mark] {
        let arcs = face == .notSent ? [leftArc, openRightArc] : [leftArc, rightArc]
        let rim = arcs.map {
            Mark(path: $0, filled: false, alpha: face == .notOwner ? 0.3 : 1, dashed: face == .loading)
        }
        return rim + core(face)
    }

    private static func core(_ face: SecreteoGlyphFace) -> [Mark] {
        switch face {
        case .ready: [Mark(path: disc(12, 11, 1.7), filled: true)]
        case .listening: [Mark(path: listeningBars(), filled: false, ink: .voice)]
        case .loading: [9.3, 12, 14.7].map { Mark(path: disc($0, 11, 1), filled: true) }
        case .polishing: [Mark(path: spark, filled: true)]
        case .inserted: [Mark(path: check, filled: false)]
        case .sent: [Mark(path: ring, filled: false), Mark(path: halfDisc, filled: true)]
        // The words got through, so the parenthesis stays whole around the warning.
        case .notSent, .notSaved: [Mark(path: bang, filled: false), Mark(path: disc(12, 15.2, 1.1), filled: true)]
        case .noSpeech: [Mark(path: line(from: pt(9.4, 11), to: pt(14.6, 11)), filled: false)]
        case .notOwner:
            [
                Mark(path: disc(12, 11, 1.7), filled: true, alpha: 0.45),
                Mark(path: line(from: pt(5, 18.5), to: pt(19, 3.5)), filled: false)
            ]
        }
    }

    static var leftArc: CGPath { curve(pt(7.2, 3.2), pt(3.9, 6.6), pt(3.9, 15.4), pt(7.2, 18.8)) }
    static var rightArc: CGPath {
        curve(
        pt(16.8, 3.2), pt(20.1, 6.6), pt(20.1, 15.4), pt(16.8, 18.8))
    }

    /// Not sent: the right parenthesis is broken where the words did not get through.
    private static var openRightArc: CGPath {
        let path = CGMutablePath()
        path.move(to: pt(16.8, 3.2))
        path.addCurve(to: pt(19.25, 10), control1: pt(18.3, 4.8), control2: pt(19.1, 7.4))
        path.move(to: pt(19.1, 13.4))
        path.addCurve(to: pt(16.8, 18.8), control1: pt(18.8, 15.5), control2: pt(18.0, 17.5))
        return path
    }

    /// Three bars around the middle line; the small indicator shortens them in silence.
    static func listeningBars(scale: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        for (x, height) in [(9.4, 3.6), (12, 9.2), (14.6, 5.2)] as [(CGFloat, CGFloat)] {
            let half = height * scale / 2
            path.move(to: CGPoint(x: x, y: 11 - half))
            path.addLine(to: CGPoint(x: x, y: 11 + half))
        }
        return path
    }

    private static var spark: CGPath {
        let path = CGMutablePath()
        path.move(to: pt(12, 6.6))
        path.addCurve(to: pt(15.9, 11), control1: pt(12.5, 9.2), control2: pt(13.4, 10.2))
        path.addCurve(to: pt(12, 15.4), control1: pt(13.4, 11.8), control2: pt(12.5, 12.8))
        path.addCurve(to: pt(8.1, 11), control1: pt(11.5, 12.8), control2: pt(10.6, 11.8))
        path.addCurve(to: pt(12, 6.6), control1: pt(10.6, 10.2), control2: pt(11.5, 9.2))
        path.closeSubpath()
        return path
    }

    private static var check: CGPath {
        let path = CGMutablePath()
        path.addLines(between: [pt(8.9, 11.3), pt(11.1, 13.6), pt(15.2, 8.7)])
        return path
    }

    private static var ring: CGPath { disc(12, 11, 2.6) }

    private static var halfDisc: CGPath {
        let path = CGMutablePath()
        path.addArc(
            center: pt(12, 11), radius: 2.6, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.closeSubpath()
        return path
    }

    private static var bang: CGPath { line(from: pt(12, 6.8), to: pt(12, 12.2)) }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func curve(_ start: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addCurve(to: end, control1: c1, control2: c2)
        return path
    }

    private static func line(from start: CGPoint, to end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [start, end])
        return path
    }

    private static func disc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }
}

extension SecreteoGlyphFace {
    /// The colour a coloured surface gives the whole glyph; nil keeps the surrounding ink.
    var tint: SecreteoColor? {
        switch self {
        case .inserted: SecreteoPalette.verified
        case .sent: SecreteoPalette.amber
        case .notSent, .notSaved: SecreteoPalette.notSent
        default: nil
        }
    }

    /// Draws a menu bar image: one colour, so macOS tints it for the bar.
    public func templateImage(height: CGFloat = 18) -> NSImage {
        let box = SecreteoGlyphGeometry.box
        let scale = height / box.height
        let image = NSImage(size: NSSize(width: box.width * scale, height: height), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            for mark in SecreteoGlyphGeometry.marks(self) {
                Self.draw(mark, in: context, color: NSColor.black.withAlphaComponent(mark.alpha).cgColor)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Secreteo"
        return image
    }

    static func draw(_ mark: SecreteoGlyphGeometry.Mark, in context: CGContext, color: CGColor) {
        context.addPath(mark.path)
        if mark.filled {
            context.setFillColor(color)
            context.fillPath()
        } else {
            context.setStrokeColor(color)
            context.setLineWidth(SecreteoGlyphGeometry.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineDash(phase: 0, lengths: mark.dashed ? [2.2, 3] : [])
            context.strokePath()
        }
    }
}

/// The glyph in SwiftUI. `ink` is the line colour; the listening core is always amber.
public struct SecreteoGlyph: View {
    let face: SecreteoGlyphFace
    var ink: Color
    var tinted: Bool

    public init(_ face: SecreteoGlyphFace, ink: Color = .primary, tinted: Bool = true) {
        self.face = face
        self.ink = ink
        self.tinted = tinted
    }

    public var body: some View {
        Canvas { context, size in
            let box = SecreteoGlyphGeometry.box
            let scale = min(size.width / box.width, size.height / box.height)
            context.translateBy(x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let line = tinted ? face.tint?.color ?? ink : ink
            for mark in SecreteoGlyphGeometry.marks(face) {
                let shading = GraphicsContext.Shading.color(
                    (mark.ink == .voice && tinted ? SecreteoDesign.amber : line).opacity(mark.alpha))
                let path = Path(mark.path)
                if mark.filled {
                    context.fill(path, with: shading)
                } else {
                    context.stroke(
                        path, with: shading,
                        style: StrokeStyle(
                            lineWidth: SecreteoGlyphGeometry.lineWidth, lineCap: .round, lineJoin: .round,
                            dash: mark.dashed ? [2.2, 3] : []))
                }
            }
        }
        .aspectRatio(SecreteoGlyphGeometry.box.width / SecreteoGlyphGeometry.box.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
