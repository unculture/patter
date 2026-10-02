import SwiftUI

/// The floating pill at the bottom of the screen.
struct IndicatorView: View {
    @ObservedObject var dictation: DictationController
    @ObservedObject var engine: SpeechEngine

    var body: some View {
        ZStack(alignment: .bottom) {
            if dictation.phase != .idle {
                PillView(
                    phase: dictation.phase,
                    engineState: engine.state,
                    meter: dictation.recorder.meter,
                    onCancel: dictation.cancel,
                    onStop: dictation.stop,
                    onSkip: dictation.skipCleanup,
                    onRetry: dictation.retryFailedRecording,
                    onOpenSettings: dictation.openMicrophoneSettings,
                    onAllowPasting: dictation.openAccessibilitySettings,
                    onRetryModel: engine.retry
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: dictation.phase)
    }
}

struct PillView: View {
    let phase: DictationController.Phase
    let engineState: SpeechEngine.State
    let meter: AudioLevelMeter
    var onCancel: () -> Void = {}
    var onStop: () -> Void = {}
    var onSkip: () -> Void = {}
    var onRetry: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onAllowPasting: () -> Void = {}
    var onRetryModel: () -> Void = {}

    var body: some View {
        content
            .padding(.horizontal, 6)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.pillFill.opacity(0.95))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.06)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .starting:
            // Same layout as recording, so that the pill does not change size when the microphone is ready.
            HStack(spacing: 10) {
                PillButton(symbol: "xmark", label: "Cancel", style: .subtle, action: onCancel)
                StartingLabel()
                    .frame(width: 92, height: 24)
                Color.clear.frame(width: 30, height: 1)
                PillButton(symbol: "stop.fill", label: "Cancel", style: .waiting, action: onCancel)
            }

        case .recording(let startedAt):
            HStack(spacing: 10) {
                PillButton(symbol: "xmark", label: "Cancel", style: .subtle, action: onCancel)
                WaveformView(mode: .live, meter: meter)
                    .frame(width: 92, height: 24)
                ElapsedTime(since: startedAt)
                PillButton(symbol: "stop.fill", label: "Stop", style: .stop, action: onStop)
            }
            .transition(.opacity)

        case .transcribing:
            HStack(spacing: 10) {
                WaveformView(mode: .processing, barCount: 9)
                    .frame(width: 52, height: 20)
                Text(transcribingMessage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)

        case .polishing:
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentDiagonal)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Cleaning up")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                PillTextButton(title: "Skip", action: onSkip)
            }
            .padding(.leading, 12)

        case .finished(let delivery, let cleanupFailed):
            HStack(spacing: 8) {
                if delivery == .noTextField {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(cleanupFailed ? Theme.warning : .white.opacity(0.85))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(cleanupFailed ? Theme.warning : Theme.success)
                        .symbolEffect(.bounce, value: phase)
                }
                Text(Self.message(for: delivery, cleanupFailed: cleanupFailed))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if delivery == .needsAccess {
                    PillTextButton(title: "Allow Pasting", action: onAllowPasting)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, delivery == .needsAccess ? 0 : 10)

        case .failed(let message, let action):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                switch action {
                case .none:
                    EmptyView()
                case .retry:
                    PillTextButton(title: "Retry", action: onRetry)
                case .openMicrophoneSettings:
                    PillTextButton(title: "Open Settings", action: onOpenSettings)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, action == .none ? 10 : 0)

        case .waitingForModel:
            modelStatus
        }
    }

    /// Why Patter did not record. The text changes while the pill shows, for example when the download finishes.
    @ViewBuilder
    private var modelStatus: some View {
        switch engineState {
        case .downloading(let fraction):
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                TwoLineLabel(title: "Downloading the speech model", detail: "Dictation works when it finishes")
                PillProgressBar(fraction: fraction)
                    .frame(width: 56, height: 4)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .padding(.horizontal, 10)
        case .failed:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                TwoLineLabel(title: "The speech model did not download", detail: "Dictation works after the download")
                PillTextButton(title: "Retry", action: onRetryModel)
            }
            .padding(.leading, 10)
        case .idle:
            HStack(spacing: 10) {
                WaveformView(mode: .processing, barCount: 9)
                    .frame(width: 52, height: 20)
                TwoLineLabel(title: "Loading the speech model", detail: "Dictation works in a moment")
            }
            .padding(.horizontal, 10)
        case .preparing, .ready:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.success)
                TwoLineLabel(title: "The download finished", detail: "You can dictate now")
            }
            .padding(.horizontal, 10)
        }
    }

    private static func message(for delivery: DictationController.Delivery, cleanupFailed: Bool) -> String {
        switch delivery {
        case .pasted: cleanupFailed ? "Pasted without cleanup" : "Pasted"
        case .copied, .needsAccess: cleanupFailed ? "Copied without cleanup" : "Copied to clipboard"
        case .noTextField: "Copied. No text field to paste into"
        }
    }

    private var transcribingMessage: String {
        switch engineState {
        case .downloading(let fraction): "Downloading model \(Int(fraction * 100))%"
        case .preparing, .idle: "Preparing model"
        case .ready, .failed: "Transcribing"
        }
    }
}

private struct TwoLineLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .fixedSize()
    }
}

private struct PillProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// Shown while the microphone starts: "Wait" with a pulsing dot. The bars replace it when audio flows.
private struct StartingLabel: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.warning)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)
            Text("Starting mic")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()
        }
        .onAppear { pulse = true }
        .accessibilityLabel("Starting the microphone. Wait before you speak.")
    }
}

private struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
                .frame(minWidth: 30)
        }
    }
}

private struct PillButton: View {
    enum Style {
        case subtle
        case stop
        /// The stop button while the microphone starts: grey, because there is nothing to stop yet.
        case waiting
    }

    let symbol: String
    let label: String
    let style: Style
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                Image(systemName: symbol)
                    .font(.system(size: style == .subtle ? 9.5 : 10, weight: .heavy))
                    .foregroundStyle(style == .subtle ? Color.white.opacity(hovering ? 0.95 : 0.65) : Color.white.opacity(style == .stop ? 1 : 0.5))
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }

    private var fill: Color {
        switch style {
        case .subtle: .white.opacity(hovering ? 0.18 : 0.09)
        case .stop: Theme.stopRed.opacity(hovering ? 1 : 0.88)
        case .waiting: .white.opacity(0.09)
        }
    }
}

private struct PillTextButton: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Capsule().fill(.white.opacity(hovering ? 0.22 : 0.13)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
