// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import SwiftUI

// MARK: - Shared styling

extension Color {
    /// A hex or CSS color from the widget settings, or the fallback.
    init(widgetHex: String, fallback: Color = .white) {
        if let value = ColorValue(text: widgetHex) {
            self = Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
        } else {
            self = fallback
        }
    }

    /// The `#RRGGBB` text a ColorPicker choice is saved as.
    var widgetHex: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X",
                      Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()),
                      Int((color.blueComponent * 255).rounded()))
    }
}

/// What every widget view draws with: its scale, colors and font.
struct DesktopWidgetTheme {
    let style: DesktopWidgetStyle

    var accent: Color { Color(widgetHex: style.accentHex, fallback: .pink) }
    var text: Color { Color(widgetHex: style.textHex) }
    var secondary: Color { text.opacity(0.68) }
    var tertiary: Color { text.opacity(0.42) }

    func s(_ value: CGFloat) -> CGFloat { value * style.scale }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let design: Font.Design
        switch style.font {
        case .standard: design = .default
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        }
        return .system(size: s(size), weight: weight, design: design)
    }
}

private struct DesktopWidgetBackdrop: ViewModifier {
    let theme: DesktopWidgetTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.s(theme.style.cornerRadius), style: .continuous)
        content
            .background {
                backdrop(shape).opacity(theme.style.backgroundOpacity)
            }
            .clipShape(shape)
            .shadow(color: theme.style.shadow && theme.style.background != .none ? .black.opacity(0.28) : .clear,
                    radius: theme.s(14), y: theme.s(6))
            // Shadows draw outside the content, so leave them room.
            .padding(theme.s(14))
    }

    @ViewBuilder private func backdrop(_ shape: RoundedRectangle) -> some View {
        let tint = Color(widgetHex: theme.style.tintHex, fallback: .black)
        switch theme.style.background {
        case .none:
            Color.clear
        case .solid:
            shape.fill(tint)
        case .glass, .tinted:
            ZStack {
                if reduceTransparency {
                    shape.fill(Color(white: 0.12))
                } else {
                    glass(shape)
                }
                shape.fill(theme.style.background == .tinted ? tint.opacity(0.55) : .black.opacity(0.18))
                shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
            }
        }
    }

    @ViewBuilder private func glass(_ shape: RoundedRectangle) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.clear, in: shape)
                .environment(\.appearsActive, true)
        } else {
            DesktopWidgetMaterial()
        }
#else
        DesktopWidgetMaterial()
#endif
    }
}

private struct DesktopWidgetMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Root

/// Hosted once per panel; picks the widget and keeps it in step with its
/// saved style.
struct DesktopWidgetRoot: View {
    let kind: DesktopWidgetKind
    @ObservedObject private var service = DesktopWidgetService.shared

    var body: some View {
        let widget = service.configuration[kind]
        let theme = DesktopWidgetTheme(style: widget.style)
        content(widget, theme: theme)
            .foregroundStyle(theme.text)
            .frame(width: widget.size.width - theme.s(28), height: widget.size.height - theme.s(28))
            .modifier(DesktopWidgetBackdrop(theme: theme))
            .frame(width: widget.size.width, height: widget.size.height)
            .contextMenu {
                Button("Customize \(kind.title)…") { service.openSettings() }
                Button(service.configuration.locked ? "Unlock widgets" : "Lock widgets") { service.toggleLocked() }
                Divider()
                Button("Hide \(kind.title)") { service.hide(kind) }
            }
    }

    @ViewBuilder private func content(_ widget: DesktopWidget, theme: DesktopWidgetTheme) -> some View {
        switch kind {
        case .clock: DesktopClockWidget(options: widget.clock, theme: theme)
        case .stats: DesktopStatsWidget(options: widget.stats, theme: theme)
        case .nowPlaying: DesktopNowPlayingWidget(options: widget.nowPlaying, theme: theme)
        case .calendar: DesktopCalendarWidget(options: widget.calendar, theme: theme)
        case .weather: DesktopWeatherWidget(options: widget.weather, theme: theme)
        }
    }
}

// MARK: - Clock

struct DesktopClockWidget: View {
    let options: DesktopClockOptions
    let theme: DesktopWidgetTheme

    private var timeZone: TimeZone {
        options.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: options.showSeconds || options.face == .analog ? 1 : 15)) { context in
            switch options.face {
            case .digital: digital(context.date)
            case .analog: analog(context.date)
            case .stacked: stacked(context.date)
            }
        }
    }

    private func format(_ pattern: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(pattern)
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.dateFormat = (options.use24Hour ? "HH:mm" : "h:mm") + (options.showSeconds ? ":ss" : "")
        return formatter.string(from: date)
    }

    private func meridiem(_ date: Date) -> String? {
        guard !options.use24Hour else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    private func digital(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: theme.s(2)) {
            if !options.label.isEmpty {
                Text(options.label.uppercased())
                    .font(theme.font(11, .semibold)).kerning(theme.s(1.2))
                    .foregroundStyle(theme.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: theme.s(6)) {
                Text(timeText(date))
                    .font(theme.font(52, .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let meridiem = meridiem(date) {
                    Text(meridiem).font(theme.font(16, .medium)).foregroundStyle(theme.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.5)
            if options.showDate {
                Text(format("EEEEMMMMd", date))
                    .font(theme.font(14, .medium))
                    .foregroundStyle(theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, theme.s(20))
    }

    private func stacked(_ date: Date) -> some View {
        let calendar = { var c = Calendar.current; c.timeZone = timeZone; return c }()
        var hour = calendar.component(.hour, from: date)
        if !options.use24Hour { hour = hour % 12 == 0 ? 12 : hour % 12 }
        let minute = calendar.component(.minute, from: date)
        return VStack(spacing: theme.s(-10)) {
            Text(String(format: "%02d", hour)).font(theme.font(68, .bold))
            Text(String(format: "%02d", minute)).font(theme.font(68, .bold)).foregroundStyle(theme.accent)
            if options.showDate || !options.label.isEmpty {
                Text(options.label.isEmpty ? format("EEEd", date) : options.label)
                    .font(theme.font(12, .semibold))
                    .foregroundStyle(theme.secondary)
                    .padding(.top, theme.s(14))
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func analog(_ date: Date) -> some View {
        let calendar = { var c = Calendar.current; c.timeZone = timeZone; return c }()
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double(parts.second ?? 0)
        let minutes = Double(parts.minute ?? 0) + seconds / 60
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
        return VStack(spacing: theme.s(6)) {
            ZStack {
                ForEach(0..<12, id: \.self) { tick in
                    Capsule()
                        .fill(tick % 3 == 0 ? theme.text : theme.tertiary)
                        .frame(width: theme.s(tick % 3 == 0 ? 3 : 2), height: theme.s(tick % 3 == 0 ? 10 : 6))
                        .offset(y: -theme.s(62))
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                hand(width: 5, length: 34, angle: hours * 30, color: theme.text)
                hand(width: 3, length: 52, angle: minutes * 6, color: theme.text)
                if options.showSeconds {
                    hand(width: 1.5, length: 58, angle: seconds * 6, color: theme.accent)
                }
                Circle().fill(theme.accent).frame(width: theme.s(8), height: theme.s(8))
            }
            .frame(width: theme.s(140), height: theme.s(140))
            if options.showDate || !options.label.isEmpty {
                Text(options.label.isEmpty ? format("EEEMMMd", date) : options.label)
                    .font(theme.font(12, .semibold))
                    .foregroundStyle(theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hand(width: CGFloat, length: CGFloat, angle: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: theme.s(width), height: theme.s(length))
            .offset(y: -theme.s(length) / 2)
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Stats

struct DesktopStatsWidget: View {
    let options: DesktopStatsOptions
    let theme: DesktopWidgetTheme
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some View {
        let snapshot = monitor.snapshot
        VStack(alignment: .leading, spacing: theme.s(10)) {
            if options.showCPU {
                row("CPU", symbol: "cpu", fraction: snapshot.cpuUsage,
                    detail: snapshot.cpuUsage.map { percent($0) } ?? "—",
                    history: snapshot.cpuHistory)
            }
            if options.showMemory {
                let fraction: Double? = {
                    guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { return nil }
                    return Double(used) / Double(total)
                }()
                row("Memory", symbol: "memorychip", fraction: fraction,
                    detail: snapshot.memoryUsed.map { MetricFormat.bytes($0) } ?? "—",
                    history: snapshot.memoryHistory)
            }
            if options.showTemperature, let temperature = snapshot.cpuTemperature {
                row("CPU temp", symbol: "thermometer.medium", fraction: min(max((temperature - 30) / 70, 0), 1),
                    detail: String(format: "%.0f°", temperature), history: [])
            }
            if options.showBattery, let power = snapshot.power, power.hasBattery, let charge = power.chargePercent {
                row(power.isCharging ? "Charging" : "Battery",
                    symbol: power.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                    fraction: Double(charge) / 100, detail: "\(charge)%", history: [])
            }
            if options.showNetwork {
                HStack(spacing: theme.s(14)) {
                    Label(snapshot.netDownBytesPerSec.map { MetricFormat.networkRateCompact($0) } ?? "—",
                          systemImage: "arrow.down")
                    Label(snapshot.netUpBytesPerSec.map { MetricFormat.networkRateCompact($0) } ?? "—",
                          systemImage: "arrow.up")
                }
                .font(theme.font(12, .medium))
                .monospacedDigit()
                .foregroundStyle(theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, theme.s(18))
        .padding(.vertical, theme.s(14))
    }

    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }

    private func row(_ title: String, symbol: String, fraction: Double?, detail: String, history: [Double]) -> some View {
        VStack(alignment: .leading, spacing: theme.s(4)) {
            HStack {
                Label(title, systemImage: symbol).font(theme.font(12, .semibold))
                Spacer()
                Text(detail).font(theme.font(12, .medium)).monospacedDigit().foregroundStyle(theme.secondary)
            }
            if options.showGraphs, history.count > 1 {
                DesktopSparkline(values: Array(history.suffix(40)), color: theme.accent)
                    .frame(height: theme.s(16))
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.text.opacity(0.14))
                        Capsule().fill(theme.accent)
                            .frame(width: geometry.size.width * min(max(fraction ?? 0, 0), 1))
                    }
                }
                .frame(height: theme.s(5))
            }
        }
    }
}

private struct DesktopSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let peak = max(values.max() ?? 1, 0.0001)
            let step = geometry.size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * step,
                        y: geometry.size.height * (1 - CGFloat(min(value / max(peak, 1), 1))))
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Now playing

struct DesktopNowPlayingWidget: View {
    let options: DesktopNowPlayingOptions
    let theme: DesktopWidgetTheme
    @ObservedObject private var music = NotchMusicService.shared

    var body: some View {
        let playback = music.playback
        let glow = music.artworkTint.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) } ?? theme.accent
        HStack(spacing: theme.s(14)) {
            if options.showArtwork {
                artwork
                    .frame(width: theme.s(76), height: theme.s(76))
                    .clipShape(RoundedRectangle(cornerRadius: theme.s(12), style: .continuous))
                    .shadow(color: options.artworkGlow && playback?.isPlaying == true ? glow.opacity(0.75) : .clear,
                            radius: theme.s(18))
            }
            VStack(alignment: .leading, spacing: theme.s(3)) {
                Text(playback?.track.title ?? "Nothing playing")
                    .font(theme.font(16, .semibold)).lineLimit(1)
                Text(playback?.track.artist ?? "Play something to see it here")
                    .font(theme.font(13)).foregroundStyle(theme.secondary).lineLimit(1)
                if options.showControls {
                    HStack(spacing: theme.s(22)) {
                        control("backward.fill", .previous, enabled: playback?.canSkipPrevious != false)
                        control(playback?.isPlaying == true ? "pause.fill" : "play.fill", .toggle, enabled: true,
                                size: 22)
                        control("forward.fill", .next, enabled: playback?.canSkipNext != false)
                    }
                    .padding(.top, theme.s(8))
                    .disabled(playback == nil)
                    .opacity(playback == nil ? 0.4 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, theme.s(16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if options.artworkGlow, playback?.isPlaying == true {
                RadialGradient(colors: [glow.opacity(0.35), .clear], center: .leading,
                               startRadius: 0, endRadius: theme.s(240))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: playback?.track.title)
    }

    @ViewBuilder private var artwork: some View {
        if let image = music.artwork {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                theme.text.opacity(0.12)
                Image(systemName: "music.note").font(.system(size: theme.s(28))).foregroundStyle(theme.tertiary)
            }
        }
    }

    private func control(_ symbol: String, _ command: NotchPlaybackCommand, enabled: Bool,
                         size: CGFloat = 16) -> some View {
        Button {
            music.send(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: theme.s(size), weight: .semibold))
                .frame(width: theme.s(28), height: theme.s(24))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Calendar

struct DesktopCalendarWidget: View {
    let options: DesktopCalendarOptions
    let theme: DesktopWidgetTheme
    @ObservedObject private var feed = DesktopCalendarFeed.shared

    var body: some View {
        VStack(alignment: .leading, spacing: theme.s(8)) {
            HStack(alignment: .firstTextBaseline) {
                Text(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(theme.font(11, .bold)).kerning(theme.s(1)).foregroundStyle(theme.accent)
                Spacer()
                Text(Date.now.formatted(.dateTime.day()))
                    .font(theme.font(26, .semibold))
            }
            if feed.access != .fullAccess {
                Spacer()
                Text("Understory needs calendar access to show your events.")
                    .font(theme.font(12)).foregroundStyle(theme.secondary)
                Button(feed.access == .notDetermined ? "Allow access" : "Open Privacy settings") {
                    feed.requestAccess()
                }
                .font(theme.font(12, .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                Spacer()
            } else if feed.events.isEmpty {
                Spacer()
                Text(options.daysAhead == 1 ? "Nothing else today" : "Nothing coming up")
                    .font(theme.font(14, .medium)).foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: theme.s(7)) {
                    ForEach(Array(feed.events.prefix(options.maxEvents))) { event in
                        eventRow(event)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, theme.s(18))
        .padding(.vertical, theme.s(14))
    }

    private func eventRow(_ event: DesktopCalendarEvent) -> some View {
        HStack(spacing: theme.s(9)) {
            RoundedRectangle(cornerRadius: theme.s(2))
                .fill(options.showCalendarColors
                      ? Color(.sRGB, red: event.red, green: event.green, blue: event.blue)
                      : theme.accent)
                .frame(width: theme.s(3.5), height: theme.s(28))
            VStack(alignment: .leading, spacing: theme.s(1)) {
                Text(event.title).font(theme.font(13, .semibold)).lineLimit(1)
                Text(when(event)).font(theme.font(11)).foregroundStyle(theme.secondary).lineLimit(1)
            }
        }
    }

    private func when(_ event: DesktopCalendarEvent) -> String {
        let calendar = Calendar.current
        let day: String = calendar.isDateInToday(event.start) || event.start < .now ? "Today"
            : calendar.isDateInTomorrow(event.start) ? "Tomorrow"
            : event.start.formatted(.dateTime.weekday(.wide))
        if event.allDay { return "\(day) · All day" }
        if event.start <= .now { return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))" }
        let minutes = Int(event.start.timeIntervalSinceNow / 60)
        if minutes < 60 { return "In \(max(minutes, 1)) min" }
        return "\(day) · \(event.start.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Weather

struct DesktopWeatherWidget: View {
    let options: DesktopWeatherOptions
    let theme: DesktopWidgetTheme
    @ObservedObject private var feed = DesktopWeatherFeed.shared

    var body: some View {
        Group {
            switch feed.state {
            case .needsPlace:
                message("Pick a city", detail: "Right-click → Customize to set one")
            case .loading:
                ProgressView().controlSize(.small)
            case .failed(let text):
                message(text, detail: "Retrying in a while")
            case .ready(let report):
                ready(report)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, theme.s(18))
        .padding(.vertical, theme.s(14))
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: theme.s(4)) {
            Image(systemName: "cloud.sun").font(.system(size: theme.s(26))).foregroundStyle(theme.accent)
            Text(title).font(theme.font(14, .semibold))
            Text(detail).font(theme.font(11)).foregroundStyle(theme.secondary)
        }
    }

    private func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    private func ready(_ report: DesktopWeatherReport) -> some View {
        VStack(alignment: .leading, spacing: theme.s(10)) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: theme.s(1)) {
                    Text(options.placeName ?? options.city)
                        .font(theme.font(13, .semibold)).lineLimit(1)
                    Text(degrees(report.temperature)).font(theme.font(44, .medium))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: theme.s(3)) {
                    Image(systemName: DesktopWeatherCode.symbol(report.code, isDay: report.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: theme.s(30)))
                    Text(DesktopWeatherCode.text(report.code)).font(theme.font(12, .medium))
                    Text("Feels \(degrees(report.feelsLike))").font(theme.font(11)).foregroundStyle(theme.secondary)
                }
            }
            if options.showForecast, !report.days.isEmpty {
                HStack {
                    ForEach(report.days.prefix(5)) { day in
                        VStack(spacing: theme.s(3)) {
                            Text(Calendar.current.isDateInToday(day.date) ? "Today"
                                 : day.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(theme.font(10, .semibold)).foregroundStyle(theme.secondary)
                            Image(systemName: DesktopWeatherCode.symbol(day.code))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: theme.s(15)))
                            Text("\(degrees(day.high)) \(degrees(day.low))")
                                .font(theme.font(10, .medium)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
