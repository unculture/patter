import SwiftUI

/// The bars in the floating indicator. In live mode the bars follow the microphone level.
/// In processing mode a wave moves across the bars while the model works.
struct WaveformView: View {
    enum Mode {
        case live
        case processing
    }

    let mode: Mode
    var meter: AudioLevelMeter?
    var barCount = 15

    @State private var smoother = LevelSmoother()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let level = mode == .live ? smoother.next(target: Double(meter?.level ?? 0), at: time) : 0
                draw(in: &context, size: size, time: time, level: level)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double, level: Double) {
        let spacing: CGFloat = 3
        let barWidth = max(2, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
        let minHeight = barWidth
        var bars = Path()

        for index in 0..<barCount {
            let position = Double(index) / Double(barCount - 1) * 2 - 1  // -1 at the left, 1 at the right
            let amplitude: Double
            switch mode {
            case .live:
                // Taller bars in the middle, and a small wobble per bar so that speech looks alive.
                let envelope = exp(-position * position * 1.4)
                let speed = 7.0 + Double(index % 5) * 1.6
                let wobble = 0.62 + 0.38 * sin(time * speed + Double(index) * 2.1)
                amplitude = level * envelope * wobble
            case .processing:
                let wave = 0.5 + 0.5 * sin(time * 5.5 - Double(index) * 0.55)
                amplitude = 0.12 + 0.5 * wave * wave
            }

            let height = minHeight + (size.height - minHeight) * CGFloat(min(max(amplitude, 0), 1))
            let x = CGFloat(index) * (barWidth + spacing)
            let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
            bars.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }

        context.fill(
            bars,
            with: .linearGradient(
                Gradient(colors: Theme.accentColors),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)))
    }
}

/// Smooths the raw level: fast rise when speech starts, slower fall when it stops.
final class LevelSmoother {
    private var value = 0.0
    private var lastTime: Double?

    func next(target: Double, at time: Double) -> Double {
        let elapsed = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 1.0 / 60
        lastTime = time
        // Ignore the room noise floor, and lift quiet speech a little.
        let gated = pow(max(0, (target - 0.1) / 0.9), 0.8)
        let rate = gated > value ? 22.0 : 7.0
        value += (gated - value) * (1 - exp(-rate * elapsed))
        return value
    }
}
