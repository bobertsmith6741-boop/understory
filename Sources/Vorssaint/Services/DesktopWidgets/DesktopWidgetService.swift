// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import AppKit
import Combine
import SwiftUI

/// A borderless panel that lives on the desktop: above the wallpaper and the
/// desktop icons, below every app window, on every Space, and never in the
/// window cycle. It takes clicks (for the music controls) without ever
/// activating Understory or stealing focus.
final class DesktopWidgetPanel: NSPanel {
    let kind: DesktopWidgetKind

    init(kind: DesktopWidgetKind, frame: NSRect) {
        self.kind = kind
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DesktopWidgetService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DesktopWidgetService()

    /// Settings edit this directly; every change is saved and applied.
    @Published var configuration: DesktopWidgetConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            if !applyingMove { save() }
            apply()
        }
    }

    private var panels: [DesktopWidgetKind: DesktopWidgetPanel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var musicSubscription: AnyCancellable?
    /// A drag writes its own position back; that save must not re-place
    /// the panel that is still being dragged.
    private var applyingMove = false
    private var active = false

    private override init() {
        configuration = DesktopWidgetConfiguration.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.desktopWidgetsConfiguration))
        super.init()
    }

    var isAvailable: Bool { AppFeature.desktopWidgets.isAvailable }

    // MARK: Lifecycle

    func syncWithPreferences() {
        guard isAvailable else { tearDown(); return }
        configuration = DesktopWidgetConfiguration.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.desktopWidgetsConfiguration))
        if !active {
            active = true
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                queue: .main) { [weak self] _ in self?.keepOnScreen() }
        }
        apply()
    }

    private func tearDown() {
        guard active else { return }
        active = false
        panels.values.forEach { $0.orderOut(nil); $0.delegate = nil }
        panels.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        musicSubscription = nil
        syncFeeds(for: DesktopWidgetConfiguration(widgets: []))
    }

    private func save() {
        UserDefaults.standard.set(configuration.encoded, forKey: DefaultsKey.desktopWidgetsConfiguration)
    }

    // MARK: Applying the configuration

    private func apply() {
        guard active else { return }
        syncFeeds(for: configuration)
        var placedThisPass: [NSRect] = []
        var firstPlacements: [DesktopWidgetKind: CGPoint] = [:]
        for widget in configuration.widgets {
            guard widget.enabled else {
                if let panel = panels.removeValue(forKey: widget.kind) {
                    panel.orderOut(nil)
                    panel.delegate = nil
                }
                continue
            }
            let panel = panels[widget.kind] ?? makePanel(widget)
            panel.isMovableByWindowBackground = !configuration.locked
            let size = widget.size
            if !applyingMove {
                let origin = widget.origin ?? defaultOrigin(for: size, avoiding: placedThisPass + placedFrames(except: widget.kind))
                let frame = NSRect(origin: origin, size: size)
                if panel.frame != frame { panel.setFrame(frame, display: true) }
                if widget.origin == nil { firstPlacements[widget.kind] = origin }
            } else if panel.frame.size != size {
                panel.setContentSize(size)
            }
            placedThisPass.append(panel.frame)
            updateVisibility(panel, widget: widget)
        }
        if !firstPlacements.isEmpty { remember(firstPlacements) }
    }

    private func makePanel(_ widget: DesktopWidget) -> DesktopWidgetPanel {
        let panel = DesktopWidgetPanel(kind: widget.kind, frame: NSRect(origin: .zero, size: widget.size))
        let host = NSHostingView(rootView: DesktopWidgetRoot(kind: widget.kind))
        host.frame = NSRect(origin: .zero, size: widget.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.delegate = self
        panels[widget.kind] = panel
        return panel
    }

    /// Now playing can hide itself while nothing plays.
    private func updateVisibility(_ panel: DesktopWidgetPanel, widget: DesktopWidget) {
        let hidden = widget.kind == .nowPlaying && widget.nowPlaying.hideWhenIdle
            && NotchMusicService.shared.playback == nil
        if hidden {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func placedFrames(except kind: DesktopWidgetKind) -> [NSRect] {
        panels.filter { $0.key != kind && $0.value.isVisible }.map(\.value.frame)
    }

    /// New widgets line up down the right edge of the main display, starting
    /// under the menu bar, skipping anything already there.
    private func defaultOrigin(for size: CGSize, avoiding taken: [NSRect]) -> CGPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 24
        var x = visible.maxX - size.width - margin
        var top = visible.maxY - margin
        while true {
            let candidate = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
            if !taken.contains(where: { $0.insetBy(dx: -8, dy: -8).intersects(candidate) }) {
                if candidate.minY >= visible.minY { return candidate.origin }
            }
            top -= 40
            if top - size.height < visible.minY {
                // Column full: start another one to the left.
                x -= size.width + margin
                top = visible.maxY - margin
                if x < visible.minX { return CGPoint(x: visible.midX - size.width / 2, y: visible.midY) }
            }
        }
    }

    /// Positions come from the panels themselves, so writing them back must
    /// not move anything: the apply this triggers only resizes.
    private func remember(_ origins: [DesktopWidgetKind: CGPoint]) {
        var updated = configuration
        for (kind, origin) in origins {
            updated[kind].originX = origin.x
            updated[kind].originY = origin.y
        }
        applyingMove = true
        configuration = updated
        applyingMove = false
        save()
    }

    /// A display that went away must not strand a widget off screen.
    private func keepOnScreen() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        for (kind, panel) in panels where !screens.contains(where: { $0.intersects(panel.frame) }) {
            var widget = configuration[kind]
            widget.originX = nil
            widget.originY = nil
            configuration[kind] = widget
        }
    }

    // MARK: Feeds

    private func syncFeeds(for configuration: DesktopWidgetConfiguration) {
        let stats = configuration[.stats]
        if stats.enabled {
            var needs = SystemMonitorPanelNeeds()
            needs.cpu = stats.stats.showCPU
            needs.memory = stats.stats.showMemory
            needs.network = stats.stats.showNetwork
            needs.battery = stats.stats.showBattery && PowerSampler.hasInternalBattery
            needs.power = needs.battery
            needs.cpuTemperature = stats.stats.showTemperature
            SystemMonitor.shared.setWidgetNeeds(needs)
        } else {
            SystemMonitor.shared.setWidgetNeeds(.none)
        }

        let music = configuration[.nowPlaying]
        let visualizer = configuration[.visualizer].enabled
        // Lyrics and the visualizer follow the same player as Now playing.
        NotchMusicService.shared.setHeldByWidgets(music.enabled || configuration[.lyrics].enabled || visualizer)
        NotchAudioLevelService.shared.setHeldByWidgets(visualizer)

        if configuration.widgets.contains(where: { $0.enabled && $0.style.matchWallpaper }) {
            DesktopWallpaperPalette.shared.start()
        } else {
            DesktopWallpaperPalette.shared.stop()
        }
        if music.enabled && music.nowPlaying.hideWhenIdle {
            if musicSubscription == nil {
                musicSubscription = NotchMusicService.shared.$playback
                    .map { $0 != nil }
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.refreshNowPlayingVisibility() }
            }
        } else {
            musicSubscription = nil
        }

        let calendar = configuration[.calendar]
        if calendar.enabled { DesktopCalendarFeed.shared.start(calendar.calendar) }
        else { DesktopCalendarFeed.shared.stop() }

        let weather = configuration[.weather]
        if weather.enabled { DesktopWeatherFeed.shared.start(weather.weather) }
        else { DesktopWeatherFeed.shared.stop() }
    }

    private func refreshNowPlayingVisibility() {
        guard let panel = panels[.nowPlaying] else { return }
        updateVisibility(panel, widget: configuration[.nowPlaying])
    }

    /// Where a widget sits on screen right now, for colors read from the
    /// wallpaper behind it.
    func frame(for kind: DesktopWidgetKind) -> NSRect? { panels[kind]?.frame }

    // MARK: Actions from the widgets

    func toggleLocked() { configuration.locked.toggle() }

    func hide(_ kind: DesktopWidgetKind) {
        var widget = configuration[kind]
        widget.enabled = false
        configuration[kind] = widget
    }

    func resetPositions() {
        for kind in DesktopWidgetKind.allCases {
            var widget = configuration[kind]
            widget.originX = nil
            widget.originY = nil
            configuration[kind] = widget
        }
    }

    func openSettings() {
        SettingsRouter.shared.request(AppFeature.desktopWidgets.settingsDestination)
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWidgetPanel, panels[panel.kind] === panel else { return }
        let origin = panel.frame.origin
        let saved = configuration[panel.kind].origin
        guard saved != origin else { return }
        remember([panel.kind: origin])
    }
}
