// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import CoreGraphics
import Foundation

/// The widgets Understory can put on the desktop. The raw value is persisted,
/// so cases can be added but never renamed.
enum DesktopWidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, stats, nowPlaying, calendar, weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .stats: return "System stats"
        case .nowPlaying: return "Now playing"
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        }
    }

    var symbolName: String {
        switch self {
        case .clock: return "clock"
        case .stats: return "cpu"
        case .nowPlaying: return "music.note"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun"
        }
    }
}

enum DesktopWidgetBackground: String, Codable, CaseIterable, Identifiable {
    case glass, tinted, solid, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: return "Glass"
        case .tinted: return "Tinted glass"
        case .solid: return "Solid"
        case .none: return "None"
        }
    }
}

enum DesktopWidgetFont: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, serif, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Default"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        }
    }
}

enum DesktopClockFace: String, Codable, CaseIterable, Identifiable {
    case digital, analog, stacked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .digital: return "Digital"
        case .analog: return "Analog"
        case .stacked: return "Stacked"
        }
    }
}

/// Decoding is forgiving on purpose: a field missing from an older save
/// keeps its default instead of throwing the whole layout away.
private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

struct DesktopWidgetStyle: Codable, Equatable {
    static let scaleRange: ClosedRange<Double> = 0.6...2.0
    static let cornerRadiusRange: ClosedRange<Double> = 0...40

    var scale: Double = 1
    /// How strong the background is; text keeps full strength.
    var backgroundOpacity: Double = 1
    var cornerRadius: Double = 22
    var background: DesktopWidgetBackground = .glass
    /// Sakura pink, matching the app icon.
    var accentHex: String = "#FF8FB1"
    var textHex: String = "#FFFFFF"
    var tintHex: String = "#2A1A24"
    var font: DesktopWidgetFont = .rounded
    var shadow: Bool = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case scale, backgroundOpacity, cornerRadius, background, accentHex, textHex, tintHex, font, shadow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DesktopWidgetStyle()
        scale = min(max(c.value(.scale, d.scale), Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        backgroundOpacity = min(max(c.value(.backgroundOpacity, d.backgroundOpacity), 0), 1)
        cornerRadius = min(max(c.value(.cornerRadius, d.cornerRadius), Self.cornerRadiusRange.lowerBound),
                           Self.cornerRadiusRange.upperBound)
        background = c.value(.background, d.background)
        accentHex = c.value(.accentHex, d.accentHex)
        textHex = c.value(.textHex, d.textHex)
        tintHex = c.value(.tintHex, d.tintHex)
        font = c.value(.font, d.font)
        shadow = c.value(.shadow, d.shadow)
    }
}

struct DesktopClockOptions: Codable, Equatable {
    var face: DesktopClockFace = .digital
    var use24Hour = false
    var showSeconds = false
    var showDate = true
    /// Nil follows the Mac's own time zone.
    var timeZoneID: String?
    /// Shown above the time, e.g. a city name for a second clock.
    var label = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case face, use24Hour, showSeconds, showDate, timeZoneID, label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DesktopClockOptions()
        face = c.value(.face, d.face)
        use24Hour = c.value(.use24Hour, d.use24Hour)
        showSeconds = c.value(.showSeconds, d.showSeconds)
        showDate = c.value(.showDate, d.showDate)
        timeZoneID = c.value(.timeZoneID, d.timeZoneID)
        label = c.value(.label, d.label)
    }
}

struct DesktopStatsOptions: Codable, Equatable {
    var showCPU = true
    var showMemory = true
    var showNetwork = true
    var showBattery = true
    var showTemperature = false
    var showGraphs = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case showCPU, showMemory, showNetwork, showBattery, showTemperature, showGraphs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DesktopStatsOptions()
        showCPU = c.value(.showCPU, d.showCPU)
        showMemory = c.value(.showMemory, d.showMemory)
        showNetwork = c.value(.showNetwork, d.showNetwork)
        showBattery = c.value(.showBattery, d.showBattery)
        showTemperature = c.value(.showTemperature, d.showTemperature)
        showGraphs = c.value(.showGraphs, d.showGraphs)
    }
}

struct DesktopNowPlayingOptions: Codable, Equatable {
    var showArtwork = true
    var artworkGlow = true
    var showControls = true
    var hideWhenIdle = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case showArtwork, artworkGlow, showControls, hideWhenIdle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DesktopNowPlayingOptions()
        showArtwork = c.value(.showArtwork, d.showArtwork)
        artworkGlow = c.value(.artworkGlow, d.artworkGlow)
        showControls = c.value(.showControls, d.showControls)
        hideWhenIdle = c.value(.hideWhenIdle, d.hideWhenIdle)
    }
}

struct DesktopCalendarOptions: Codable, Equatable {
    static let daysAheadRange = 1...14
    static let maxEventsRange = 1...8

    var daysAhead = 3
    var maxEvents = 4
    var showCalendarColors = true
    var showAllDay = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case daysAhead, maxEvents, showCalendarColors, showAllDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DesktopCalendarOptions()
        daysAhead = min(max(c.value(.daysAhead, d.daysAhead), Self.daysAheadRange.lowerBound),
                        Self.daysAheadRange.upperBound)
        maxEvents = min(max(c.value(.maxEvents, d.maxEvents), Self.maxEventsRange.lowerBound),
                        Self.maxEventsRange.upperBound)
        showCalendarColors = c.value(.showCalendarColors, d.showCalendarColors)
        showAllDay = c.value(.showAllDay, d.showAllDay)
    }
}

struct DesktopWeatherOptions: Codable, Equatable {
    /// What was typed; the resolved place below is what is actually read.
    var city = ""
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
    var fahrenheit = Locale.current.measurementSystem == .us
    var showForecast = true

    init() {}

    var hasPlace: Bool { latitude != nil && longitude != nil }

    private enum CodingKeys: String, CodingKey {
        case city, placeName, latitude, longitude, fahrenheit, showForecast
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DesktopWeatherOptions()
        city = c.value(.city, d.city)
        placeName = c.value(.placeName, d.placeName)
        latitude = c.value(.latitude, d.latitude)
        longitude = c.value(.longitude, d.longitude)
        fahrenheit = c.value(.fahrenheit, d.fahrenheit)
        showForecast = c.value(.showForecast, d.showForecast)
    }
}

struct DesktopWidget: Codable, Equatable, Identifiable {
    var kind: DesktopWidgetKind
    var enabled: Bool
    /// The window's bottom-left corner in global screen coordinates; nil
    /// until placed, so a first show lines it up with the others.
    var originX: Double?
    var originY: Double?
    var style = DesktopWidgetStyle()
    var clock = DesktopClockOptions()
    var stats = DesktopStatsOptions()
    var nowPlaying = DesktopNowPlayingOptions()
    var calendar = DesktopCalendarOptions()
    var weather = DesktopWeatherOptions()

    var id: DesktopWidgetKind { kind }

    var origin: CGPoint? {
        guard let originX, let originY else { return nil }
        return CGPoint(x: originX, y: originY)
    }

    init(kind: DesktopWidgetKind, enabled: Bool) {
        self.kind = kind
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case kind, enabled, originX, originY, style, clock, stats, nowPlaying, calendar, weather
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(DesktopWidgetKind.self, forKey: .kind)
        enabled = c.value(.enabled, false)
        originX = c.value(.originX, nil as Double?)
        originY = c.value(.originY, nil as Double?)
        style = c.value(.style, DesktopWidgetStyle())
        clock = c.value(.clock, DesktopClockOptions())
        stats = c.value(.stats, DesktopStatsOptions())
        nowPlaying = c.value(.nowPlaying, DesktopNowPlayingOptions())
        calendar = c.value(.calendar, DesktopCalendarOptions())
        weather = c.value(.weather, DesktopWeatherOptions())
    }

    /// The size the widget draws at, before any scale. Every view lays out
    /// inside exactly this box, so the window never has to chase its content.
    var baseSize: CGSize {
        switch kind {
        case .clock:
            switch clock.face {
            case .analog: return CGSize(width: 180, height: clock.showDate || !clock.label.isEmpty ? 214 : 180)
            case .stacked: return CGSize(width: 200, height: 200)
            case .digital: return CGSize(width: 280, height: 130)
            }
        case .stats: return CGSize(width: 270, height: 190)
        case .nowPlaying: return CGSize(width: 340, height: nowPlaying.showControls ? 140 : 108)
        case .calendar: return CGSize(width: 290, height: 236)
        case .weather: return CGSize(width: 320, height: weather.showForecast ? 190 : 120)
        }
    }

    var size: CGSize {
        CGSize(width: (baseSize.width * style.scale).rounded(), height: (baseSize.height * style.scale).rounded())
    }
}

/// Every widget, in a fixed order, plus the settings they share.
struct DesktopWidgetConfiguration: Codable, Equatable {
    var widgets: [DesktopWidget]
    /// Locked widgets ignore drags, so a stray click on the desktop never
    /// moves one.
    var locked = false

    static let `default` = DesktopWidgetConfiguration(
        widgets: DesktopWidgetKind.allCases.map { DesktopWidget(kind: $0, enabled: $0 == .clock) })

    init(widgets: [DesktopWidget], locked: Bool = false) {
        self.widgets = widgets
        self.locked = locked
    }

    private enum CodingKeys: String, CodingKey { case widgets, locked }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let saved = c.value(.widgets, [DesktopWidget]())
        // One entry per kind, in catalog order, whatever the save held.
        widgets = DesktopWidgetKind.allCases.map { kind in
            saved.first { $0.kind == kind } ?? DesktopWidget(kind: kind, enabled: false)
        }
        locked = c.value(.locked, false)
    }

    static func decode(_ data: Data?) -> DesktopWidgetConfiguration {
        guard let data, let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return .default }
        return decoded
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }

    func isEnabled(_ kind: DesktopWidgetKind) -> Bool {
        widgets.first { $0.kind == kind }?.enabled == true
    }

    subscript(kind: DesktopWidgetKind) -> DesktopWidget {
        get { widgets.first { $0.kind == kind } ?? DesktopWidget(kind: kind, enabled: false) }
        set {
            if let index = widgets.firstIndex(where: { $0.kind == kind }) {
                widgets[index] = newValue
            } else {
                widgets.append(newValue)
            }
        }
    }
}
