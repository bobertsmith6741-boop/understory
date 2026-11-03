// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import SwiftUI

/// The Desktop widgets sections of the Quick Tools page: which widgets are
/// out, then one section per widget that is on, with its look and options.
struct DesktopWidgetSettingsSections: View {
    @ObservedObject private var service = DesktopWidgetService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Section {
            ForEach(DesktopWidgetKind.allCases) { kind in
                Toggle(isOn: binding(kind, \.enabled)) {
                    Label(kind.title, systemImage: kind.symbolName)
                }
            }
            Toggle("Lock widget positions", isOn: $service.configuration.locked)
            Button {
                service.resetPositions()
            } label: {
                Label("Line widgets up again", systemImage: "rectangle.3.group")
            }
            Text("Drag a widget to move it. Right-click one to customize, lock or hide it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(FeatureStrings.desktopWidgets(l10n.language).pageTitle)
        }
        .settingsFormSectionAnchor(.desktopWidgets)

        ForEach(DesktopWidgetKind.allCases.filter { service.configuration[$0].enabled }) { kind in
            Section {
                DisclosureGroup("Options") { options(kind) }
                DisclosureGroup("Look") { style(kind) }
            } header: {
                Label(kind.title, systemImage: kind.symbolName)
            }
        }
    }

    private func binding<Value>(_ kind: DesktopWidgetKind,
                                _ path: WritableKeyPath<DesktopWidget, Value>) -> Binding<Value> {
        Binding(get: { service.configuration[kind][keyPath: path] },
                set: { service.configuration[kind][keyPath: path] = $0 })
    }

    private func color(_ kind: DesktopWidgetKind, _ path: WritableKeyPath<DesktopWidget, String>) -> Binding<Color> {
        Binding(get: { Color(widgetHex: service.configuration[kind][keyPath: path]) },
                set: { service.configuration[kind][keyPath: path] = $0.widgetHex })
    }

    // MARK: Look, shared by every widget

    @ViewBuilder private func style(_ kind: DesktopWidgetKind) -> some View {
        Picker("Background", selection: binding(kind, \.style.background)) {
            ForEach(DesktopWidgetBackground.allCases) { Text($0.title).tag($0) }
        }
        if service.configuration[kind].style.background != .none {
            LabeledContent("Background strength") {
                Slider(value: binding(kind, \.style.backgroundOpacity), in: 0.1...1)
            }
        }
        if [.tinted, .solid].contains(service.configuration[kind].style.background) {
            ColorPicker("Background color", selection: color(kind, \.style.tintHex), supportsOpacity: false)
        }
        LabeledContent("Size") {
            Slider(value: binding(kind, \.style.scale), in: DesktopWidgetStyle.scaleRange, step: 0.05)
        }
        LabeledContent("Corner radius") {
            Slider(value: binding(kind, \.style.cornerRadius), in: DesktopWidgetStyle.cornerRadiusRange, step: 1)
        }
        Picker("Font", selection: binding(kind, \.style.font)) {
            ForEach(DesktopWidgetFont.allCases) { Text($0.title).tag($0) }
        }
        ColorPicker("Text color", selection: color(kind, \.style.textHex), supportsOpacity: false)
        ColorPicker("Accent color", selection: color(kind, \.style.accentHex), supportsOpacity: false)
        Toggle("Shadow", isOn: binding(kind, \.style.shadow))
        Toggle("Match wallpaper colors", isOn: binding(kind, \.style.matchWallpaper))
        if service.configuration[kind].style.matchWallpaper {
            Text("Text and accent follow the wallpaper behind the widget, so the colors above are set aside.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Button("Reset look") { service.configuration[kind].style = DesktopWidgetStyle() }
    }

    // MARK: Options per widget

    @ViewBuilder private func options(_ kind: DesktopWidgetKind) -> some View {
        switch kind {
        case .clock: clockOptions
        case .stats: statsOptions
        case .nowPlaying: nowPlayingOptions
        case .calendar: calendarOptions
        case .weather: DesktopWeatherPlaceRow(service: service)
        case .lyrics: lyricsOptions
        case .visualizer: visualizerOptions
        case .claudeUsage: claudeOptions
        }
    }

    @ViewBuilder private var clockOptions: some View {
        Picker("Face", selection: binding(.clock, \.clock.face)) {
            ForEach(DesktopClockFace.allCases) { Text($0.title).tag($0) }
        }
        Toggle("24-hour time", isOn: binding(.clock, \.clock.use24Hour))
        Toggle("Show seconds", isOn: binding(.clock, \.clock.showSeconds))
        Toggle("Show date", isOn: binding(.clock, \.clock.showDate))
        TextField("Label", text: binding(.clock, \.clock.label), prompt: Text("Optional, e.g. Tokyo"))
        Picker("Time zone", selection: binding(.clock, \.clock.timeZoneID)) {
            Text("This Mac").tag(String?.none)
            ForEach(Self.timeZones, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag(String?.some($0)) }
        }
    }

    private static let timeZones = TimeZone.knownTimeZoneIdentifiers.sorted()

    @ViewBuilder private var statsOptions: some View {
        Toggle("CPU", isOn: binding(.stats, \.stats.showCPU))
        Toggle("Memory", isOn: binding(.stats, \.stats.showMemory))
        Toggle("CPU temperature", isOn: binding(.stats, \.stats.showTemperature))
        if PowerSampler.hasInternalBattery {
            Toggle("Battery", isOn: binding(.stats, \.stats.showBattery))
        }
        Toggle("Network", isOn: binding(.stats, \.stats.showNetwork))
        Toggle("Graphs instead of bars", isOn: binding(.stats, \.stats.showGraphs))
    }

    @ViewBuilder private var nowPlayingOptions: some View {
        Toggle("Album art", isOn: binding(.nowPlaying, \.nowPlaying.showArtwork))
        Toggle("Album glow", isOn: binding(.nowPlaying, \.nowPlaying.artworkGlow))
        Toggle("Playback controls", isOn: binding(.nowPlaying, \.nowPlaying.showControls))
        Toggle("Hide when nothing plays", isOn: binding(.nowPlaying, \.nowPlaying.hideWhenIdle))
    }

    @ViewBuilder private var lyricsOptions: some View {
        Stepper("Lines around the current one: \(service.configuration[.lyrics].lyrics.contextLines)",
                value: binding(.lyrics, \.lyrics.contextLines), in: DesktopLyricsOptions.contextRange)
        Picker("Alignment", selection: binding(.lyrics, \.lyrics.alignment)) {
            ForEach(DesktopLyricsAlignment.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Light up in the album color", isOn: binding(.lyrics, \.lyrics.albumColor))
        Toggle("Song and artist", isOn: binding(.lyrics, \.lyrics.showTrack))
        Text("Uses the Dynamic Island's lyrics, so Show lyrics needs to be on there.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var visualizerOptions: some View {
        Picker("Style", selection: binding(.visualizer, \.visualizer.style)) {
            ForEach(DesktopVisualizerStyle.allCases) { Text($0.title).tag($0) }
        }
        LabeledContent("Bars: \(service.configuration[.visualizer].visualizer.barCount)") {
            Slider(value: Binding(
                get: { Double(service.configuration[.visualizer].visualizer.barCount) },
                set: { service.configuration[.visualizer].visualizer.barCount = Int($0.rounded()) }),
                   in: Double(DesktopVisualizerOptions.barRange.lowerBound)...Double(DesktopVisualizerOptions.barRange.upperBound),
                   step: 1)
        }
        Toggle("Album color", isOn: binding(.visualizer, \.visualizer.albumColor))
        Toggle("Glow", isOn: binding(.visualizer, \.visualizer.glow))
        Text("Listens only to the music player's own output, never stores or sends audio. macOS asks for permission the first time.")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var claudeOptions: some View {
        Toggle("Usage limits", isOn: binding(.claudeUsage, \.claudeUsage.showLimits))
        Toggle("Today's tokens", isOn: binding(.claudeUsage, \.claudeUsage.showToday))
        Toggle("Working status", isOn: binding(.claudeUsage, \.claudeUsage.showWorking))
    }

    @ViewBuilder private var calendarOptions: some View {
        Stepper("Days ahead: \(service.configuration[.calendar].calendar.daysAhead)",
                value: binding(.calendar, \.calendar.daysAhead), in: DesktopCalendarOptions.daysAheadRange)
        Stepper("Events shown: \(service.configuration[.calendar].calendar.maxEvents)",
                value: binding(.calendar, \.calendar.maxEvents), in: DesktopCalendarOptions.maxEventsRange)
        Toggle("All-day events", isOn: binding(.calendar, \.calendar.showAllDay))
        Toggle("Calendar colors", isOn: binding(.calendar, \.calendar.showCalendarColors))
    }
}

/// Typing a city resolves it once; only the found place is used afterwards.
private struct DesktopWeatherPlaceRow: View {
    @ObservedObject var service: DesktopWidgetService
    @ObservedObject private var feed = DesktopWeatherFeed.shared
    @State private var city = ""

    var body: some View {
        let weather = service.configuration[.weather].weather
        HStack {
            TextField("City", text: $city, prompt: Text("e.g. Amsterdam"))
                .onSubmit(search)
            Button("Set", action: search)
                .disabled(city.trimmingCharacters(in: .whitespaces).isEmpty || feed.searching)
        }
        .onAppear { city = weather.city }
        if feed.searching {
            ProgressView().controlSize(.small)
        } else if let error = feed.searchError {
            Text(error).font(.caption).foregroundStyle(.orange)
        } else if let place = weather.placeName {
            Text("Showing \(place)").font(.caption).foregroundStyle(.secondary)
        }
        Toggle("Fahrenheit", isOn: Binding(
            get: { service.configuration[.weather].weather.fahrenheit },
            set: { service.configuration[.weather].weather.fahrenheit = $0 }))
        Toggle("5-day forecast", isOn: Binding(
            get: { service.configuration[.weather].weather.showForecast },
            set: { service.configuration[.weather].weather.showForecast = $0 }))
        Text("Weather comes from Open-Meteo. Only the place's coordinates are sent.")
            .font(.caption).foregroundStyle(.tertiary)
    }

    private func search() {
        let typed = city
        feed.search(typed) { name, latitude, longitude in
            var weather = service.configuration[.weather].weather
            weather.city = typed
            weather.placeName = name
            weather.latitude = latitude
            weather.longitude = longitude
            service.configuration[.weather].weather = weather
        }
    }
}
