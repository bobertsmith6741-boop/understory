// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import SwiftUI

private extension NotchArtworkTint {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

// MARK: - Lyrics

/// Synced lyrics in large type, the current line lit, from the same lyrics
/// the island shows.
struct DesktopLyricsWidget: View {
    let options: DesktopLyricsOptions
    let theme: DesktopWidgetTheme
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var service = NotchLyricsService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highlight: Color {
        options.albumColor ? music.artworkTint?.swiftUIColor ?? theme.accent : theme.accent
    }

    private var alignment: HorizontalAlignment { options.alignment == .center ? .center : .leading }
    private var textAlignment: TextAlignment { options.alignment == .center ? .center : .leading }
    private var frameAlignment: Alignment { options.alignment == .center ? .center : .leading }

    var body: some View {
        VStack(alignment: alignment, spacing: theme.s(6)) {
            if options.showTrack, let playback = music.playback {
                Text([playback.track.title, playback.track.artist].compactMap { $0 }.joined(separator: " · "))
                    .font(theme.font(11, .semibold))
                    .foregroundStyle(theme.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        }
        .padding(.horizontal, theme.s(20))
        .padding(.vertical, theme.s(14))
        .onAppear(perform: load)
        .onChange(of: music.playback?.track.title) { load() }
        .onChange(of: music.playback?.track.artist) { load() }
    }

    @ViewBuilder private var content: some View {
        if !NotchLyricsSupport.isEnabled() {
            message("Lyrics are off",
                    detail: "Turn on Show lyrics in Settings → Dynamic Island → Music")
        } else if music.playback == nil {
            message("♪", detail: "Play a song to see its lyrics")
        } else if let playback = music.playback, let lyrics = service.lyrics, !lyrics.lines.isEmpty {
            TimelineView(.explicit(lyrics.changeDates(for: playback, offset: service.offset, from: .now))) { context in
                let index = lyrics.activeIndex(at: playback.position(at: context.date), offset: service.offset)
                lines(lyrics.lines, current: index)
            }
        } else if service.lyrics?.instrumental == true {
            message("Instrumental", detail: nil)
        } else {
            switch service.state {
            case .loading: message("Finding lyrics…", detail: nil)
            case .consent:
                message("Lyrics need to be looked up online",
                        detail: "Turn on Find lyrics online in Dynamic Island settings")
            default: message("No synced lyrics for this song", detail: nil)
            }
        }
    }

    private func lines(_ all: [NotchLyricLine], current: Int?) -> some View {
        let center = current ?? -1
        let range = (center - options.contextLines)...(center + options.contextLines)
        return VStack(alignment: alignment, spacing: theme.s(6)) {
            ForEach(Array(range), id: \.self) { index in
                let isCurrent = index == center
                let text = all.indices.contains(index) ? all[index].text : ""
                Text(text.isEmpty ? (isCurrent ? "♪" : " ") : text)
                    .font(theme.font(isCurrent ? 22 : 16, isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? highlight : theme.text.opacity(abs(index - center) == 1 ? 0.5 : 0.28))
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: isCurrent ? highlight.opacity(0.45) : .clear, radius: theme.s(10))
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: center)
    }

    private func message(_ title: String, detail: String?) -> some View {
        VStack(alignment: alignment, spacing: theme.s(4)) {
            Text(title).font(theme.font(17, .semibold)).foregroundStyle(theme.secondary)
            if let detail {
                Text(detail).font(theme.font(11)).foregroundStyle(theme.tertiary)
                    .multilineTextAlignment(textAlignment)
            }
        }
    }

    /// Asks for this song's lyrics the same way the strip under the island does.
    private func load() {
        guard NotchLyricsSupport.isEnabled(), let playback = music.playback else { return }
        service.update(playback: playback, visible: true)
    }
}

// MARK: - Visualizer

struct DesktopVisualizerWidget: View {
    let options: DesktopVisualizerOptions
    let theme: DesktopWidgetTheme
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var audio = NotchAudioLevelService.shared
    @ObservedObject private var permissions = Permissions.shared

    private var color: Color {
        options.albumColor ? music.artworkTint?.swiftUIColor ?? theme.accent : theme.accent
    }

    var body: some View {
        ZStack {
            if music.playback?.isPlaying == true, let levels = audio.levels {
                DesktopVisualizerShape(levels: Self.spread(levels, to: options.barCount),
                                       style: options.style, scale: theme.style.scale)
                    .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: options.glow ? color.opacity(0.6) : .clear, radius: theme.s(12))
                    .animation(.easeOut(duration: 0.12), value: levels)
            } else {
                // Resting line so the widget still reads as a visualizer.
                DesktopVisualizerShape(levels: Array(repeating: 0, count: options.barCount),
                                       style: options.style, scale: theme.style.scale)
                    .fill(theme.text.opacity(0.25))
                if music.playback?.isPlaying == true {
                    Text("Allow Understory to hear the player in Privacy settings to see the music move")
                        .font(theme.font(10)).foregroundStyle(theme.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .padding(.horizontal, theme.s(18))
        .padding(.vertical, theme.s(16))
    }

    /// The island reads a handful of bands; more bars blend between them so
    /// neighbours move together instead of in blocks.
    static func spread(_ levels: [Double], to count: Int) -> [Double] {
        guard levels.count > 1, count > 1 else { return Array(repeating: levels.first ?? 0, count: max(count, 1)) }
        return (0..<count).map { bar in
            let position = Double(bar) / Double(count - 1) * Double(levels.count - 1)
            let lower = Int(position.rounded(.down)), upper = min(lower + 1, levels.count - 1)
            let fraction = position - Double(lower)
            let value = levels[lower] * (1 - fraction) + levels[upper] * fraction
            return min(max(value, 0), 1)
        }
    }
}

private struct DesktopVisualizerShape: Shape {
    var levels: [Double]
    let style: DesktopVisualizerStyle
    let scale: Double

    var animatableData: AnimatableVector {
        get { AnimatableVector(values: levels) }
        set { levels = newValue.values }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(levels.count, 1)
        let slot = rect.width / CGFloat(count)
        let barWidth = max(2, slot * 0.6)
        let minimum = max(3, 3 * scale)
        switch style {
        case .bars, .mirrored:
            for (index, level) in levels.enumerated() {
                let x = rect.minX + CGFloat(index) * slot + (slot - barWidth) / 2
                let height = max(minimum, rect.height * CGFloat(level) * (style == .mirrored ? 1 : 1))
                let y = style == .mirrored ? rect.midY - height / 2 : rect.maxY - height
                path.addRoundedRect(in: CGRect(x: x, y: y, width: barWidth, height: height),
                                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
            }
        case .dots:
            let dot = barWidth
            let rows = max(1, Int(rect.height / (dot * 1.4)))
            for (index, level) in levels.enumerated() {
                let x = rect.minX + CGFloat(index) * slot + (slot - dot) / 2
                let lit = max(1, Int((Double(rows) * level).rounded()))
                for row in 0..<lit {
                    let y = rect.maxY - CGFloat(row + 1) * dot * 1.4
                    path.addEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
                }
            }
        case .wave:
            // A filled band, mirrored about the middle, through every level.
            let points = levels.enumerated().map { index, level in
                CGPoint(x: rect.minX + (CGFloat(index) + 0.5) * slot,
                        y: rect.height / 2 * CGFloat(max(level, 0.04)))
            }
            guard let first = points.first else { return path }
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: first.x, y: rect.midY - first.y))
            for (previous, point) in zip(points, points.dropFirst()) {
                let mid = (previous.x + point.x) / 2
                path.addCurve(to: CGPoint(x: point.x, y: rect.midY - point.y),
                              control1: CGPoint(x: mid, y: rect.midY - previous.y),
                              control2: CGPoint(x: mid, y: rect.midY - point.y))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            let reversed = Array(points.reversed())
            path.addLine(to: CGPoint(x: reversed[0].x, y: rect.midY + reversed[0].y))
            for (previous, point) in zip(reversed, reversed.dropFirst()) {
                let mid = (previous.x + point.x) / 2
                path.addCurve(to: CGPoint(x: point.x, y: rect.midY + point.y),
                              control1: CGPoint(x: mid, y: rect.midY + previous.y),
                              control2: CGPoint(x: mid, y: rect.midY + point.y))
            }
            path.closeSubpath()
        }
        return path
    }
}

/// Lets a whole row of levels animate between readings.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableVector { AnimatableVector(values: []) }

    private static func combine(_ lhs: AnimatableVector, _ rhs: AnimatableVector,
                                _ operation: (Double, Double) -> Double) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        return AnimatableVector(values: (0..<count).map { index in
            operation(index < lhs.values.count ? lhs.values[index] : 0,
                      index < rhs.values.count ? rhs.values[index] : 0)
        })
    }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector { combine(lhs, rhs, +) }
    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector { combine(lhs, rhs, -) }

    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

// MARK: - Claude usage

struct DesktopClaudeUsageWidget: View {
    let options: DesktopClaudeUsageOptions
    let theme: DesktopWidgetTheme
    @ObservedObject private var usage = AgentUsageService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: theme.s(10)) {
            HStack(spacing: theme.s(6)) {
                Image(systemName: "sparkles").foregroundStyle(theme.accent)
                Text("Claude").font(theme.font(14, .bold))
                Spacer()
                if let plan = usage.snapshot.plans[.claude] {
                    Text(plan.name).font(theme.font(11, .semibold)).foregroundStyle(theme.secondary)
                }
            }
            if !NotchAgentSupport.isEnabled() {
                Spacer()
                Text("Usage is read by the Dynamic Island's AI section.")
                    .font(theme.font(12)).foregroundStyle(theme.secondary)
                Button("Turn on") { Self.turnOn() }
                    .buttonStyle(.plain)
                    .font(theme.font(12, .semibold))
                    .foregroundStyle(theme.accent)
                Spacer()
            } else if !usage.snapshot.loaded {
                Spacer()
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                Spacer()
            } else {
                content
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, theme.s(18))
        .padding(.vertical, theme.s(14))
    }

    @ViewBuilder private var content: some View {
        let snapshot = usage.snapshot
        let windows = snapshot.limits[.claude]?.windows.filter { $0.scope == nil } ?? []
        if options.showLimits, !windows.isEmpty {
            ForEach(windows.prefix(2)) { window in
                limit(window)
            }
        }
        if options.showToday {
            let today = snapshot.usage(.today).byProvider[.claude] ?? AgentTotals()
            HStack {
                Label("Today", systemImage: "calendar").font(theme.font(12, .semibold))
                Spacer()
                Text("\(Self.tokens(today.tokens.total)) tokens · \(today.requests) msgs")
                    .font(theme.font(12, .medium)).monospacedDigit().foregroundStyle(theme.secondary)
            }
        }
        if options.showWorking {
            let working = snapshot.working(.claude)
            HStack(spacing: theme.s(6)) {
                Circle()
                    .fill(working.isEmpty ? theme.tertiary : Color.green)
                    .frame(width: theme.s(7), height: theme.s(7))
                Text(working.isEmpty ? "Idle"
                     : working.count == 1 ? "Working on \(working[0].project)"
                     : "\(working.count) sessions working")
                    .font(theme.font(12, .medium)).foregroundStyle(theme.secondary).lineLimit(1)
            }
        }
        if windows.isEmpty, !options.showToday, !options.showWorking {
            Text("No usage yet").font(theme.font(12)).foregroundStyle(theme.secondary)
        }
    }

    private func limit(_ window: AgentLimitWindow) -> some View {
        let title: String = switch window.kind {
        case .session: "5-hour limit"
        case .weekly: "Weekly limit"
        case .other: "Limit"
        }
        let resets = window.resetsAt ?? window.estimatedResetsAt
        let color: Color = window.usedFraction > 0.9 ? .red : window.usedFraction > 0.7 ? .orange : theme.accent
        return VStack(alignment: .leading, spacing: theme.s(4)) {
            HStack {
                Text(title).font(theme.font(12, .semibold))
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(theme.font(12, .bold)).monospacedDigit().foregroundStyle(color)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.text.opacity(0.14))
                    Capsule().fill(color).frame(width: geometry.size.width * window.usedFraction)
                }
            }
            .frame(height: theme.s(6))
            if let resets {
                Text("Resets \(resets.formatted(.relative(presentation: .named)))")
                    .font(theme.font(10)).foregroundStyle(theme.tertiary)
            }
        }
    }

    static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...: return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(count) / 1_000)
        default: return "\(count)"
        }
    }

    /// Switches on the island's AI section, which does the reading. It stays
    /// hidden from the island if it was hidden before.
    private static func turnOn() {
        if !AppFeature.notchAgents.isAvailable {
            FeatureRuntime.shared.setAvailable([.notchAgents], true)
        }
        UserDefaults.standard.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        FeatureRuntime.shared.sync([.notchAgents])
    }
}
