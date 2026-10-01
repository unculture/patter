import SwiftUI

/// The main window: dictation stats and every transcript, newest first.
struct HistoryView: View {
    @ObservedObject var store: TranscriptStore
    @ObservedObject var engine: SpeechEngine
    @ObservedObject var preferences: Preferences
    var openSettings: () -> Void = {}

    @State private var query = ""
    @State private var recentlyDeleted: Transcript?
    @State private var undoTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 34)
                .padding(.bottom, 18)

            if store.transcripts.isEmpty {
                EmptyHistoryView(engine: engine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    TranscriptList(
                        transcripts: filtered,
                        query: query,
                        onDelete: delete)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }

            Divider().opacity(0.6)
            StatusBar(engine: engine)
        }
        .background(WindowBackground())
        .overlay(alignment: .bottom) { undoToast }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                AppMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wisp")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Your dictations, newest first")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")
            }

            if !store.transcripts.isEmpty {
                StatsRow(transcripts: store.transcripts)
                SearchField(text: $query)
            }
        }
    }

    private var filtered: [Transcript] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.transcripts }
        return store.transcripts.filter { $0.text.localizedStandardContains(trimmed) }
    }

    @ViewBuilder
    private var undoToast: some View {
        if recentlyDeleted != nil {
            HStack(spacing: 12) {
                Text("Transcript deleted")
                    .font(.system(size: 12.5, weight: .medium))
                Button("Undo") {
                    if let recentlyDeleted { withAnimation { store.restore(recentlyDeleted) } }
                    withAnimation { recentlyDeleted = nil }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.cyan)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(Theme.pillFill.opacity(0.95)))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .padding(.bottom, 48)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func delete(_ transcript: Transcript) {
        withAnimation(.easeOut(duration: 0.2)) {
            store.delete(transcript)
            recentlyDeleted = transcript
        }
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation { recentlyDeleted = nil }
        }
    }
}

// MARK: - List

struct TranscriptList: View {
    let transcripts: [Transcript]
    var query = ""
    let onDelete: (Transcript) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
            if transcripts.isEmpty {
                Text("No transcripts match “\(query)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
            ForEach(sections, id: \.day) { section in
                Text(Self.title(for: section.day))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .padding(.leading, 4)
                ForEach(section.items) { transcript in
                    TranscriptRow(transcript: transcript, onDelete: { onDelete(transcript) })
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
    }

    private var sections: [(day: Date, items: [Transcript])] {
        let calendar = Calendar.current
        var result: [(day: Date, items: [Transcript])] = []
        for transcript in transcripts {
            let day = calendar.startOfDay(for: transcript.createdAt)
            if result.last?.day == day {
                result[result.count - 1].items.append(transcript)
            } else {
                result.append((day, [transcript]))
            }
        }
        return result
    }

    static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

struct TranscriptRow: View {
    let transcript: Transcript
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var copied = false
    @State private var expanded = false
    @State private var showingOriginal = false

    private var isLong: Bool { transcript.text.count > 360 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(transcript.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                    .help(transcript.createdAt.formatted(date: .complete, time: .shortened))
                Text("·").foregroundStyle(.tertiary)
                Text(Self.durationText(transcript.duration))
                Text("·").foregroundStyle(.tertiary)
                Text("\(transcript.wordCount) \(transcript.wordCount == 1 ? "word" : "words")")
                if transcript.rawText != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showingOriginal.toggle() }
                    } label: {
                        Label(showingOriginal ? "Hide original" : "Cleaned up", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(Capsule().fill(Theme.violet.opacity(0.12)))
                            .foregroundStyle(Theme.violet)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    .help(showingOriginal ? "Hide the transcript before the AI cleanup" : "Show the transcript before the AI cleanup")
                }
                Spacer(minLength: 8)
                RowButton(
                    symbol: copied ? "checkmark" : "doc.on.doc",
                    label: copied ? "Copied" : "Copy",
                    tint: copied ? Theme.success : nil,
                    action: copy)
                RowButton(symbol: "trash", label: "Delete", tint: nil, action: onDelete)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Text(transcript.text)
                .font(.system(size: 13.5))
                .lineSpacing(3.5)
                .lineLimit(expanded ? nil : 5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if showingOriginal, let rawText = transcript.rawText {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Before cleanup")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy Original") { Clipboard.copy(rawText) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.blue)
                    }
                    Text(rawText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isLong {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 1 : 0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.13 : 0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.08 : 0.03), radius: hovering ? 8 : 3, y: 2)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Copy", action: copy)
            if let rawText = transcript.rawText {
                Button("Copy Original") { Clipboard.copy(rawText) }
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func copy() {
        Clipboard.copy(transcript.text)
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { copied = false }
        }
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(1, Int(duration.rounded()))
        return seconds < 60 ? "\(seconds)s" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct RowButton: View {
    let symbol: String
    let label: String
    let tint: Color?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint ?? (hovering ? Color.primary : Color.secondary))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Header parts

struct StatsRow: View {
    let transcripts: [Transcript]

    var body: some View {
        HStack(spacing: 10) {
            StatTile(symbol: "text.word.spacing", value: totalWords.formatted(), label: "words dictated")
            StatTile(symbol: "calendar", value: wordsThisWeek.formatted(), label: "words in the last 7 days")
            StatTile(symbol: "gauge.with.dots.needle.67percent", value: wordsPerMinute, label: "words per minute")
        }
    }

    private var totalWords: Int { transcripts.reduce(0) { $0 + $1.wordCount } }

    private var wordsThisWeek: Int {
        let start = Date().addingTimeInterval(-7 * 24 * 3600)
        return transcripts.filter { $0.createdAt >= start }.reduce(0) { $0 + $1.wordCount }
    }

    private var wordsPerMinute: String {
        let timed = transcripts.filter { $0.duration >= 3 }
        let minutes = timed.reduce(0) { $0 + $1.duration } / 60
        guard minutes > 0 else { return "–" }
        let words = timed.reduce(0) { $0 + $1.wordCount }
        return Int((Double(words) / minutes).rounded()).formatted()
    }
}

private struct StatTile: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentDiagonal)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search transcripts", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? Theme.blue.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Empty state, status bar, background

struct EmptyHistoryView: View {
    @ObservedObject var engine: SpeechEngine

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.accentDiagonal)
                    .opacity(0.14)
                    .frame(width: 96, height: 96)
                    .blur(radius: 2)
                Image(systemName: "waveform")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.accentDiagonal)
            }
            VStack(spacing: 8) {
                Text("No transcripts yet")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Press the shortcut in any app and start talking. Press it again to stop. The text goes to your clipboard and shows up here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            ShortcutKeys(size: 15)
            if case .downloading = engine.state {
                Text("Wisp is downloading its speech model (\(engine.kind.downloadSize)). This happens one time only.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(.bottom, 30)
    }
}

struct StatusBar: View {
    @ObservedObject var engine: SpeechEngine

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.6), radius: 3)
            Text(engine.statusText)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if case .failed = engine.state {
                Button("Retry", action: engine.retry)
                    .buttonStyle(.link)
                    .font(.system(size: 11.5, weight: .medium))
            }
            Spacer()
            Text("Dictate")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            ShortcutKeys(size: 10)
        }
        .padding(.horizontal, 20)
        .frame(height: 38)
    }

    private var dotColor: Color {
        switch engine.state {
        case .ready: Theme.success
        case .failed: Theme.stopRed
        case .idle, .downloading, .preparing: Theme.warning
        }
    }
}

extension SpeechEngine {
    var statusText: String {
        switch state {
        case .idle: "Starting"
        case .downloading(let fraction): "Downloading \(kind.title) model: \(Int(fraction * 100))%"
        case .preparing: "Preparing \(kind.title) model"
        case .ready: "\(kind.title) model ready. Runs on this Mac."
        case .failed(let message): "Model not available: \(message)"
        }
    }
}

/// The Wisp mark: gradient bars on a dark rounded square, like the app icon.
struct AppMark: View {
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.10, blue: 0.20), Color(red: 0.05, green: 0.05, blue: 0.09)],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                HStack(spacing: size * 0.06) {
                    ForEach(Array([0.30, 0.55, 0.85, 0.55, 0.30].enumerated()), id: \.offset) { _, height in
                        Capsule().frame(width: size * 0.085, height: size * height * 0.7)
                    }
                }
                .foregroundStyle(Theme.accentDiagonal)
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: Theme.violet.opacity(0.25), radius: 6, y: 2)
    }
}

private struct WindowBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: Theme.violet.opacity(0.11), location: 0),
                        .init(color: Theme.cyan.opacity(0.04), location: 0.25),
                        .init(color: Theme.cyan.opacity(0), location: 0.5),
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .ignoresSafeArea()
    }
}
