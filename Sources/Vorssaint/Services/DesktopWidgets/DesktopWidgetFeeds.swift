// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import AppKit
import Combine
import EventKit

// MARK: - Calendar

struct DesktopCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let red: Double
    let green: Double
    let blue: Double
}

/// EventKit objects stay on this actor; only plain values reach the widget.
private actor DesktopCalendarReader {
    private lazy var store = EKEventStore()

    func read(days: Int, includeAllDay: Bool) -> [DesktopCalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: startOfToday) else { return [] }
        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { event in
                event.status != .canceled
                    && (includeAllDay || !event.isAllDay)
                    && event.endDate > now
                    && event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true
            }
            // By day, all-day events first within a day, then by start.
            .sorted { first, second in
                let firstDay = calendar.startOfDay(for: first.startDate)
                let secondDay = calendar.startOfDay(for: second.startDate)
                if firstDay != secondDay { return firstDay < secondDay }
                if first.isAllDay != second.isAllDay { return first.isAllDay }
                return first.startDate < second.startDate
            }
            .map { event in
                let color = event.calendar.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
                return DesktopCalendarEvent(
                    id: (event.eventIdentifier ?? UUID().uuidString) + ":" + String(event.startDate.timeIntervalSinceReferenceDate),
                    title: event.title ?? "",
                    start: event.startDate, end: event.endDate, allDay: event.isAllDay,
                    red: Double(color?.redComponent ?? 0.6),
                    green: Double(color?.greenComponent ?? 0.6),
                    blue: Double(color?.blueComponent ?? 0.6))
            }
    }
}

final class DesktopCalendarFeed: ObservableObject {
    static let shared = DesktopCalendarFeed()

    @Published private(set) var events: [DesktopCalendarEvent] = []
    @Published private(set) var access = EKEventStore.authorizationStatus(for: .event)

    private let reader = DesktopCalendarReader()
    private var timer: Timer?
    private var storeObserver: NSObjectProtocol?
    private var dayObserver: NSObjectProtocol?
    private var permissionSubscription: AnyCancellable?
    private var task: Task<Void, Never>?
    private var options = DesktopCalendarOptions()
    private(set) var running = false

    private init() {}

    func start(_ options: DesktopCalendarOptions) {
        let changed = options != self.options
        self.options = options
        guard !running else { if changed { refresh() }; return }
        running = true
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        // Past events drop off and "in 5 min" stays current.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 10
        permissionSubscription = Permissions.shared.$calendarAccess
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        task?.cancel(); task = nil
        timer?.invalidate(); timer = nil
        [storeObserver, dayObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
        storeObserver = nil; dayObserver = nil
        permissionSubscription = nil
        events = []
    }

    func requestAccess() {
        if access == .notDetermined {
            Permissions.shared.requestCalendar()
        } else {
            Permissions.shared.openCalendarSettings()
        }
    }

    func refresh() {
        access = EKEventStore.authorizationStatus(for: .event)
        guard running else { return }
        let days = options.daysAhead, allDay = options.showAllDay
        task?.cancel()
        task = Task { @MainActor [weak self, reader] in
            let events = await reader.read(days: days, includeAllDay: allDay)
            guard !Task.isCancelled, let self, self.running else { return }
            if self.events != events { self.events = events }
        }
    }
}

// MARK: - Weather

struct DesktopWeatherDay: Identifiable, Equatable {
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    var id: Date { date }
}

struct DesktopWeatherReport: Equatable {
    let temperature: Double
    let feelsLike: Double
    let code: Int
    let isDay: Bool
    let windSpeed: Double
    let days: [DesktopWeatherDay]
    let fetchedAt: Date
}

/// Open-Meteo: free, no account or key, and only coordinates leave the Mac.
final class DesktopWeatherFeed: ObservableObject {
    static let shared = DesktopWeatherFeed()

    enum State: Equatable {
        case needsPlace
        case loading
        case ready(DesktopWeatherReport)
        case failed(String)
    }

    @Published private(set) var state: State = .needsPlace
    @Published private(set) var searching = false
    @Published private(set) var searchError: String?

    private var options = DesktopWeatherOptions()
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private(set) var running = false
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private init() {}

    func start(_ options: DesktopWeatherOptions) {
        let changed = options.latitude != self.options.latitude || options.longitude != self.options.longitude
            || options.fahrenheit != self.options.fahrenheit
        self.options = options
        guard !running else { if changed { refresh() }; return }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 60
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        task?.cancel(); task = nil
        timer?.invalidate(); timer = nil
    }

    func refresh() {
        guard running else { return }
        guard let latitude = options.latitude, let longitude = options.longitude else {
            state = .needsPlace
            return
        }
        if case .ready = state {} else { state = .loading }
        let fahrenheit = options.fahrenheit
        task?.cancel()
        task = Task { @MainActor [weak self, session] in
            let result = await Self.fetch(latitude: latitude, longitude: longitude,
                                          fahrenheit: fahrenheit, session: session)
            guard !Task.isCancelled, let self, self.running else { return }
            switch result {
            case .success(let report): self.state = .ready(report)
            case .failure:
                // Keep showing the last reading through a short outage.
                if case .ready = self.state { return }
                self.state = .failed("Couldn’t load the weather")
            }
        }
    }

    /// Resolves a typed city into coordinates, then hands the place back for
    /// the widget's settings to keep.
    func search(_ city: String, completion: @escaping (_ name: String, _ latitude: Double, _ longitude: Double) -> Void) {
        let query = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searching = true
        searchError = nil
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query),
                                 URLQueryItem(name: "count", value: "1"),
                                 URLQueryItem(name: "language", value: "en"),
                                 URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { searching = false; return }
        Task { @MainActor [weak self, session] in
            let place: (String, Double, Double)? = await {
                guard let (data, _) = try? await session.data(from: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let first = (json["results"] as? [[String: Any]])?.first,
                      let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double
                else { return nil }
                let name = [first["name"] as? String, first["admin1"] as? String ?? first["country"] as? String]
                    .compactMap { $0 }.joined(separator: ", ")
                return (name, lat, lon)
            }()
            guard let self else { return }
            self.searching = false
            if let place {
                completion(place.0, place.1, place.2)
            } else {
                self.searchError = "No place found for “\(query)”"
            }
        }
    }

    private static func fetch(latitude: Double, longitude: Double, fahrenheit: Bool,
                              session: URLSession) async -> Result<DesktopWeatherReport, Error> {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
        ]
        do {
            let (data, _) = try await session.data(from: components.url!)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
                  let code = (current["weather_code"] as? NSNumber)?.intValue
            else { throw URLError(.cannotParseResponse) }
            var days: [DesktopWeatherDay] = []
            if let daily = json["daily"] as? [String: Any],
               let times = daily["time"] as? [String],
               let codes = daily["weather_code"] as? [NSNumber],
               let highs = daily["temperature_2m_max"] as? [NSNumber],
               let lows = daily["temperature_2m_min"] as? [NSNumber] {
                let parser = DateFormatter()
                parser.dateFormat = "yyyy-MM-dd"
                parser.locale = Locale(identifier: "en_US_POSIX")
                for index in times.indices where index < codes.count && index < highs.count && index < lows.count {
                    guard let date = parser.date(from: times[index]) else { continue }
                    days.append(DesktopWeatherDay(date: date, code: codes[index].intValue,
                                                  high: highs[index].doubleValue, low: lows[index].doubleValue))
                }
            }
            return .success(DesktopWeatherReport(
                temperature: temperature,
                feelsLike: (current["apparent_temperature"] as? NSNumber)?.doubleValue ?? temperature,
                code: code,
                isDay: (current["is_day"] as? NSNumber)?.intValue != 0,
                windSpeed: (current["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0,
                days: days, fetchedAt: Date()))
        } catch {
            return .failure(error)
        }
    }
}

/// WMO weather codes, as Open-Meteo reports them.
enum DesktopWeatherCode {
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return "cloud.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 80, 81: return "Rain"
        case 65, 82: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 85: return "Snow"
        case 75, 86: return "Heavy snow"
        case 77: return "Snow grains"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm, hail"
        default: return "—"
        }
    }
}
