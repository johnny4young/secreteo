import SwiftUI

/// The small indicator's pure geometry: the gap between the parentheses is the meter.
enum DictationAsideShape {
    static let maxSpread: CGFloat = 2
    static let release: TimeInterval = 0.18
    static let frameInterval: TimeInterval = 1.0 / 30
    static let quietBars = 0.45
    /// Reduce Motion: the bars rest on one of three heights.
    static let barSteps = [0.45, 0.72, 1]
    static let outline: CGFloat = 1
    static let outlineOpacity = 0.92
    static let shadowRadius: CGFloat = 1.6

    /// 0 in silence, 1 for a loud voice.
    static func openness(for level: Float) -> Double {
        level > 0.000_1 ? DictationWaveformShape.amplitude(for: level) : 0
    }

    /// How far each parenthesis moves outward, in points.
    static func spread(for openness: Double) -> CGFloat {
        maxSpread * CGFloat(min(1, max(0, openness)))
    }

    static func barScale(for openness: Double) -> Double {
        quietBars + (1 - quietBars) * min(1, max(0, openness))
    }

    static func barStep(for level: Float) -> Double {
        barSteps[min(barSteps.count - 1, Int(openness(for: level) * Double(barSteps.count)))]
    }

    /// Opens at once and closes over `release`.
    static func envelope(from previous: Double, to target: Double, elapsed: TimeInterval) -> Double {
        target >= previous ? target : max(target, previous - max(0, elapsed) / release)
    }

    /// Light enough for the ink outline on any surface, whatever the system appearance.
    static func ink(for face: SecreteoGlyphFace) -> SecreteoColor {
        switch face {
        case .inserted: SecreteoPalette.capsuleVerified
        case .sent: SecreteoPalette.capsuleAmber
        case .notSent: SecreteoPalette.capsuleNotSent
        case .noSpeech: SecreteoPalette.asideQuiet
        default: SecreteoPalette.capsuleText
        }
    }

    struct Pose: Equatable {
        var spread: CGFloat = 0
        var barScale = 1.0
        var scale: CGFloat = 1.25
        var outlined = true
    }

    static func draw(_ face: SecreteoGlyphFace, pose: Pose, in context: inout GraphicsContext, size: CGSize) {
        let box = SecreteoGlyphGeometry.box
        context.translateBy(
            x: (size.width - box.width * pose.scale) / 2, y: (size.height - box.height * pose.scale) / 2)
        context.scaleBy(x: pose.scale, y: pose.scale)
        var marks = SecreteoGlyphGeometry.marks(face)
        if face == .listening, let bars = marks.indices.last {
            marks[bars] = .init(
                path: SecreteoGlyphGeometry.listeningBars(scale: pose.barScale), filled: false, ink: .voice)
        }
        let line = ink(for: face).color
        let passes = pose.outlined ? [true, false] : [false]
        for outline in passes {
            for (index, mark) in marks.enumerated() {
                // The first two marks are the parentheses.
                let shift = index == 0 ? -pose.spread : index == 1 ? pose.spread : 0
                let path = Path(mark.path).offsetBy(dx: shift / pose.scale, dy: 0)
                let color = outline
                    ? SecreteoPalette.asideOutline.color.opacity(outlineOpacity)
                    : (mark.ink == .voice ? SecreteoPalette.capsuleAmber.color : line).opacity(mark.alpha)
                let extra = outline ? 2 * Self.outline / pose.scale : 0
                let style = StrokeStyle(
                    lineWidth: (mark.filled ? 0 : SecreteoGlyphGeometry.lineWidth) + extra,
                    lineCap: .round, lineJoin: .round, dash: mark.dashed ? [2.2, 3] : [])
                if mark.filled { context.fill(path, with: .color(color)) }
                if !mark.filled || outline { context.stroke(path, with: .color(color), style: style) }
            }
        }
    }
}

/// Keeps the last opening between frames so it can close slowly.
@MainActor
final class DictationAsideEnvelope {
    private(set) var value = 0.0
    private var last: Date?

    func advance(to target: Double, at date: Date) -> Double {
        value = DictationAsideShape.envelope(
            from: value, to: target, elapsed: last.map { date.timeIntervalSince($0) } ?? 0)
        last = date
        return value
    }
}

/// The two parentheses and the face between them, readable with no background.
struct DictationAsideGlyph: View {
    let face: SecreteoGlyphFace
    var level: Float = 0
    /// False from Stop on: a redraw per frame would hold back the stop tail and the delivery.
    var live = false
    var outlined = true
    var scale: CGFloat = 1.25
    /// A still picture, for Settings.
    var fixedOpenness: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var envelope = DictationAsideEnvelope()

    var body: some View {
        Group {
            if let fixedOpenness {
                canvas(openness: fixedOpenness)
            } else if face != .listening {
                canvas(openness: 0)
            } else if reduceMotion {
                canvas(openness: 0, barScale: DictationAsideShape.barStep(for: level))
            } else {
                let frames = AnimationTimelineSchedule.animation(
                    minimumInterval: DictationAsideShape.frameInterval, paused: !live)
                TimelineView(frames) { frame in
                    canvas(openness: live
                        ? envelope.advance(to: DictationAsideShape.openness(for: level), at: frame.date)
                        : envelope.value)
                }
            }
        }
        .shadow(
            color: outlined ? SecreteoPalette.lacquer.color.opacity(0.38) : .clear,
            radius: DictationAsideShape.shadowRadius, y: 1.2)
        .accessibilityHidden(true)
    }

    private func canvas(openness: Double, barScale: Double? = nil) -> some View {
        let face = face
        let pose = DictationAsideShape.Pose(
            spread: DictationAsideShape.spread(for: openness),
            barScale: barScale ?? DictationAsideShape.barScale(for: openness), scale: scale, outlined: outlined)
        return Canvas { context, size in
            DictationAsideShape.draw(face, pose: pose, in: &context, size: size)
        }
    }
}

/// The glyph with its optional time and dark bead; Settings draws its previews with it.
struct DictationAsideBody: View {
    let face: SecreteoGlyphFace
    var level: Float = 0
    var live = false
    var fixedOpenness: Double?
    /// Nil hides the time.
    var time: String?
    var bead = false
    var ring = true

    var body: some View {
        let glyph = DictationCompactIndicator.glyphSize
        HStack(spacing: 2) {
            DictationAsideGlyph(
                face: face, level: level, live: live, outlined: !bead, scale: bead ? 1 : 1.25,
                fixedOpenness: fixedOpenness)
                .frame(width: glyph.width, height: glyph.height)
                .id(face)
                .transition(.opacity)
            if let time {
                Text(verbatim: time)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SecreteoPalette.capsuleText.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .modifier(DictationAsideInkOutline(isOn: !bead))
                    .frame(width: 32, alignment: .leading)
            }
        }
        .padding(.trailing, time == nil ? 0 : 4)
        .frame(height: bead ? DictationCompactIndicator.beadHeight : glyph.height)
        .background {
            if bead {
                Capsule()
                    .fill(LinearGradient(
                        colors: [SecreteoPalette.capsuleHighlight.color, SecreteoPalette.asideOutline.color],
                        startPoint: .top, endPoint: .bottom))
                    .overlay {
                        if ring { Capsule().strokeBorder(SecreteoPalette.capsuleAmber.color.opacity(0.55)) }
                    }
            }
        }
        .animation(
            DictationCapsuleMotion.indicatorChange(
                microphoneIsOpen: live, duration: DictationCompactIndicator.faceChange),
            value: face)
    }
}

/// Text with no backdrop keeps a dark edge, like the glyph.
private struct DictationAsideInkOutline: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            let ink = SecreteoPalette.asideOutline.color.opacity(DictationAsideShape.outlineOpacity)
            content
                .shadow(color: ink, radius: 0, x: 0.8, y: 0.8)
                .shadow(color: ink, radius: 0, x: -0.8, y: -0.8)
                .shadow(color: ink, radius: 0, x: 0.8, y: -0.8)
                .shadow(color: ink, radius: 0, x: -0.8, y: 0.8)
                .shadow(
                    color: SecreteoPalette.lacquer.color.opacity(0.38), radius: DictationAsideShape.shadowRadius,
                    y: 1.2)
        } else {
            content
        }
    }
}

/// The small indicator in the dictation panel.
struct DictationAsideView: View {
    let controller: DictationController
    let options: DictationCompactIndicator.Options
    /// What the time read at Stop; it does not count through the delivery.
    @State private var stoppedTime: String?
    @State private var faded = false

    var body: some View {
        let size = DictationCompactIndicator.size(for: options)
        let isRunning = DictationWaveform.animates(for: controller)
        Group {
            if options.showsElapsedTime, isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    indicator(time: DictationCompactIndicator.time(
                        start: controller.captureStartedAt, tick: tick.date, stoppedAt: nil))
                }
            } else {
                indicator(time: stillTime)
            }
        }
        .opacity(faded ? 0 : 1)
        .frame(width: size.width, height: size.height, alignment: .leading)
        // Fully clear pixels let clicks through the window; a barely-there fill keeps the glyph a target.
        .background(Color.black.opacity(0.01))
        .padding(DictationCompactIndicator.margin)
        .onChange(of: isRunning, initial: true) {
            stoppedTime = isRunning ? nil : DictationCompactIndicator.time(
                start: controller.captureStartedAt, tick: .now, stoppedAt: nil)
        }
        .onChange(of: controller.phase) {
            guard let words = DictationCompactIndicator.announcement(for: controller.phase) else { return }
            AccessibilityNotification.Announcement(words).post()
        }
        .task(id: controller.phase) {
            faded = false
            let phase = controller.phase
            guard let hold = DictationCompactIndicator.hold(for: phase) else { return }
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            if phase == .noSpeech {
                controller.expandCompactIndicator()
            } else {
                withAnimation(DictationCapsuleMotion.resultFade(
                    for: phase, duration: DictationCompactIndicator.fade)) { faded = true }
            }
        }
    }

    /// A result keeps the width, without a time that no longer runs.
    private var stillTime: String? {
        guard options.showsElapsedTime else { return nil }
        return controller.isActive ? stoppedTime ?? "" : ""
    }

    private func indicator(time: String?) -> some View {
        DictationAsideBody(
            face: controller.statusFace, level: controller.micLevel, live: DictationWaveform.animates(for: controller),
            time: time, bead: options.showsBackdrop)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DictationCompactIndicator.accessibilityLabel(face: controller.statusFace, time: time))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { controller.expandCompactIndicator() }
            .accessibilityIdentifier("dictation-panel-compact")
    }
}
