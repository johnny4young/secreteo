import SwiftUI

/// The voice as the capsule's material: light that rises from below with the microphone level,
/// a thin glow in silence and up to half the capsule for a loud voice.
///
/// Equatable so a caption arriving after Stop cannot redraw it: once paused, the level it stopped on is the picture.
struct DictationLiquidLevel: View, Equatable {
    let level: Float
    let motion: DictationLiquidShape.Motion
    let paused: Bool
    let dimmed: Bool
    /// Reduce Transparency: solid colour, kept under the words.
    let opaque: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.motion == rhs.motion, lhs.paused == rhs.paused, lhs.dimmed == rhs.dimmed,
              lhs.opaque == rhs.opaque else { return false }
        return lhs.paused || lhs.level == rhs.level
    }

    var body: some View {
        Group {
            if motion == .stepped {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(LinearGradient(gradient: along, startPoint: .leading, endPoint: .trailing))
                        .frame(height: proxy.size.height * DictationLiquidShape.step(for: level, opaque: opaque))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
                    Canvas(rendersAsynchronously: true) { canvas, size in
                        draw(in: &canvas, size: size, time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        // The light thins out behind the words so they keep their contrast.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0), .init(color: .black, location: DictationLiquidShape.clearBelow),
                    .init(color: .black.opacity(DictationLiquidShape.textBandOpacity),
                          location: DictationLiquidShape.textBand),
                    .init(color: .black.opacity(DictationLiquidShape.textBandOpacity), location: 1)
                ],
                startPoint: .bottom, endPoint: .top)
        }
        .accessibilityHidden(true)
    }

    private var along: Gradient { gradient(DictationLiquidShape.body) }

    private func gradient(_ stops: [DictationLiquidShape.Stop]) -> Gradient {
        let quiet = SecreteoPalette.capsuleSecondaryText.color
        return Gradient(stops: stops.map {
            let alpha = opaque ? 1 : $0.alpha
            let color = dimmed ? quiet.opacity(alpha * 0.4) : $0.color.color.opacity(alpha)
            return .init(color: color, location: $0.location)
        })
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let fill = DictationLiquidShape.fill(for: level, opaque: opaque)
        let crest = size.height * CGFloat(1 - min(1, fill * DictationLiquidShape.peak))
        let body = GraphicsContext.Shading.linearGradient(
            along, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        let glow = GraphicsContext.Shading.linearGradient(
            gradient(DictationLiquidShape.highlight),
            startPoint: CGPoint(x: 0, y: crest), endPoint: CGPoint(x: 0, y: size.height))
        if !opaque { canvas.addFilter(.blur(radius: 1.5)) }
        for (index, wave) in DictationWaveformShape.waves.prefix(2).enumerated().reversed() {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for step in stride(from: 0, through: Int(size.width), by: 2) {
                let x = Double(step) / max(1, Double(size.width))
                let surface = DictationLiquidShape.surface(at: x, time: time, wave: wave, fill: fill)
                path.addLine(to: CGPoint(x: CGFloat(step), y: size.height * CGFloat(1 - surface)))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            canvas.opacity = index == 0 ? 1 : DictationLiquidShape.backWaveOpacity
            canvas.fill(path, with: body)
            if index == 0, !opaque { canvas.fill(path, with: glow) }
        }
    }
}

/// The liquid's pure geometry and colours. Heights are fractions of the capsule's height.
enum DictationLiquidShape {
    enum Motion: Equatable {
        case flowing
        /// At Stop: a redraw per frame would hold back the stop tail and the delivery.
        case frozen
        /// Reduce Motion: a flat bar on one of three heights.
        case stepped
    }

    struct Stop {
        let color: SecreteoColor
        let alpha: Double
        let location: Double
    }

    /// Along the capsule: a trace of copper where it starts, amber where the voice is newest.
    static let body = [
        Stop(color: SecreteoPalette.capsuleCopper, alpha: 0.15, location: 0),
        Stop(color: SecreteoPalette.ember, alpha: 0.55, location: 0.55),
        Stop(color: SecreteoPalette.capsuleAmber, alpha: 0.8, location: 1)
    ]
    /// From the crest down, on the front wave only.
    static let highlight = [
        Stop(color: SecreteoPalette.capsuleHighlight, alpha: 0.4, location: 0),
        Stop(color: SecreteoPalette.capsuleAmber, alpha: 0.12, location: 1)
    ]
    static let backWaveOpacity = 0.5

    static let floor = 0.05
    static let ceiling = 0.36
    /// Solid light must stay under the words.
    static let opaqueCeiling = 0.12
    /// How far the highest crest stands above the fill.
    static let peak = 1.4
    /// Full strength up to here; from `textBand` up, where the words sit, only `textBandOpacity` is left.
    static let clearBelow = 0.18
    static let textBand = 0.28
    static let textBandOpacity = 0.2

    static func motion(microphoneIsOpen: Bool, reduceMotion: Bool) -> Motion {
        if reduceMotion { return .stepped }
        return microphoneIsOpen ? .flowing : .frozen
    }

    static func fill(for level: Float, opaque: Bool = false) -> Double {
        floor + ((opaque ? opaqueCeiling : ceiling) - floor) * DictationWaveformShape.amplitude(for: level)
    }

    static func steps(opaque: Bool = false) -> [Double] {
        opaque ? [0.06, 0.11, 0.16] : [0.08, 0.2, 0.36]
    }

    static func step(for level: Float, opaque: Bool = false) -> Double {
        let amplitude = DictationWaveformShape.amplitude(for: level)
        let steps = steps(opaque: opaque)
        return steps[min(steps.count - 1, Int(amplitude * Double(steps.count)))]
    }

    /// The surface's height at `x` in 0…1: a swell toward the middle with the waveform's ripples on it.
    static func surface(at x: Double, time: Double, wave: DictationWaveformShape.Wave, fill: Double) -> Double {
        let swell = 0.45 + 0.55 * sin(.pi * x)
        let ripple = (peak - 1) * DictationWaveformShape.offset(at: x, time: time, wave: wave, amplitude: 1)
        return max(0, min(1, fill * (swell + ripple)))
    }

    /// How much of the light is left at a height, after the fade behind the words.
    static func strength(at height: Double) -> Double {
        if height <= clearBelow { return 1 }
        if height >= textBand { return textBandOpacity }
        return 1 - (1 - textBandOpacity) * (height - clearBelow) / (textBand - clearBelow)
    }
}
