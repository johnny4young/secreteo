import SwiftUI

/// The voice as the capsule's material: light that fills it from below and follows the
/// microphone level: a thin glow in silence, up to half the capsule for a loud voice. It redraws only while flowing.
struct DictationLiquidLevel: View {
    let level: Float
    let motion: DictationLiquidShape.Motion
    var dimmed = false

    var body: some View {
        Group {
            if motion == .stepped {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(LinearGradient(gradient: body(dimmed: dimmed), startPoint: .leading, endPoint: .trailing))
                        .frame(height: proxy.size.height * DictationLiquidShape.step(for: level))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: motion == .frozen)) { context in
                    Canvas(rendersAsynchronously: true) { canvas, size in
                        draw(in: &canvas, size: size, time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Translucent along its length: a trace of copper where it starts, amber where the voice is newest.
    private func body(dimmed: Bool) -> Gradient {
        let quiet = SecreteoPalette.capsuleSecondaryText.color
        return dimmed
            ? Gradient(colors: [quiet.opacity(0.08), quiet.opacity(0.3)])
            : Gradient(stops: [
                .init(color: SecreteoPalette.capsuleCopper.color.opacity(0.15), location: 0),
                .init(color: SecreteoDesign.ember.opacity(0.55), location: 0.55),
                .init(color: SecreteoPalette.capsuleAmber.color.opacity(0.8), location: 1)
            ])
    }

    private var highlight: Gradient {
        Gradient(colors: [
            SecreteoPalette.capsuleHighlight.color.opacity(dimmed ? 0.1 : 0.4),
            SecreteoPalette.capsuleAmber.color.opacity(dimmed ? 0 : 0.12)
        ])
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let fill = DictationLiquidShape.fill(for: level)
        let crest = size.height * CGFloat(1 - min(1, fill * DictationLiquidShape.peak))
        let along = GraphicsContext.Shading.linearGradient(
            body(dimmed: dimmed), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        let glow = GraphicsContext.Shading.linearGradient(
            highlight, startPoint: CGPoint(x: 0, y: crest), endPoint: CGPoint(x: 0, y: size.height))
        canvas.addFilter(.blur(radius: 1.5))
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
            canvas.opacity = index == 0 ? 1 : 0.5
            canvas.fill(path, with: along)
            if index == 0 { canvas.fill(path, with: glow) }
        }
    }
}

/// The liquid's pure geometry, as fractions of the capsule's height.
enum DictationLiquidShape {
    enum Motion: Equatable {
        case flowing
        /// At Stop: a redraw per frame would hold back the stop tail and the delivery.
        case frozen
        /// Reduce Motion: a flat bar on one of three heights.
        case stepped
    }

    static let floor = 0.05
    static let ceiling = 0.36
    static let steps = [0.08, 0.2, 0.36]
    /// How far the highest crest stands above the fill.
    static let peak = 1.4

    static func motion(microphoneIsOpen: Bool, reduceMotion: Bool) -> Motion {
        if reduceMotion { return .stepped }
        return microphoneIsOpen ? .flowing : .frozen
    }

    static func fill(for level: Float) -> Double {
        floor + (ceiling - floor) * DictationWaveformShape.amplitude(for: level)
    }

    static func step(for level: Float) -> Double {
        let amplitude = DictationWaveformShape.amplitude(for: level)
        return steps[min(steps.count - 1, Int(amplitude * Double(steps.count)))]
    }

    /// The surface's height at `x` in 0…1: a swell toward the middle with the waveform's ripples on it.
    static func surface(at x: Double, time: Double, wave: DictationWaveformShape.Wave, fill: Double) -> Double {
        let swell = 0.45 + 0.55 * sin(.pi * x)
        let ripple = (peak - 1) * DictationWaveformShape.offset(at: x, time: time, wave: wave, amplitude: 1)
        return max(0, min(1, fill * (swell + ripple)))
    }
}
