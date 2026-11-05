// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// What the lock screen may show, settled when it appears: preferences cannot
/// change while the Mac is locked, so the views never read them again.
final class NotchLockScreenModel: ObservableObject {
    struct Gates: Equatable {
        var music = false
        var timer = false
        var agents = false
        var downloads = false
        var countdown = false
        var timeLeft = false
    }

    @Published var gates = Gates()
    /// Kept for the whole time the Mac stays locked, across the display
    /// sleeping and waking, and cleared once it unlocks.
    @Published var playedWhileLocked = false
    @Published var padlockOpen = false

    func showsMusic(_ playback: NotchPlayback?) -> Bool {
        gates.music && playback.map {
            NotchLockScreenSupport.showsMusic(isPlaying: $0.isPlaying, playedWhileLocked: playedWhileLocked)
        } == true
    }
}

/// The island at rest with a padlock beside the camera, and the music's bars
/// on the other side while a song plays. The padlock closes as the Mac locks
/// and opens as it unlocks, before the island returns underneath.
struct NotchLockScreenIsland: View {
    @ObservedObject var model: NotchLockScreenModel
    let size: CGSize
    let cameraWidth: CGFloat
    /// The music strip's own geometry: the padlock takes the cover's place and
    /// the bars keep theirs, so locking changes what shows, not where.
    let geometry: NotchGeometry
    /// The window on whole points around the island, and the island's top
    /// left corner inside it; the rest of the window stays clear.
    var window: CGSize? = nil
    var origin: CGPoint = .zero
    @ObservedObject private var music = NotchMusicService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let wing = max(0, (size.width - cameraWidth) / 2)
        let padlockSide = min(geometry.compactMusicArtworkSide, wing)
        let playing = model.showsMusic(music.playback) && music.playback?.isPlaying == true
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: size.height))
            .fill(.black)
            .overlay {
                HStack(spacing: 0) {
                    Image(systemName: model.padlockOpen ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: min(13, size.height * 0.42), weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, options: .speed(1.4), value: reduceMotion ? false : model.padlockOpen)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.padlockOpen)
                        .frame(width: padlockSide, height: padlockSide)
                        .padding(.leading, max(0, min(geometry.compactMusicArtworkInset, wing - padlockSide)))
                        .frame(width: wing, height: size.height, alignment: .leading)
                    Spacer(minLength: 0)
                    NotchEqualizerBars(isPlaying: playing, bars: NotchLayout.compactMusicBarCount,
                                       barWidth: NotchLayout.compactMusicBarWidth, height: geometry.compactMusicBarHeight,
                                       tint: music.artworkTint?.color ?? .white)
                        .opacity(playing ? 1 : 0)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: playing)
                        .padding(.trailing, max(0, min(geometry.compactMusicBarsInset, wing - NotchLayout.compactMusicBarsWidth)))
                        .frame(width: wing, height: size.height, alignment: .trailing)
                }
            }
            .frame(width: size.width, height: size.height)
            .padding(.leading, origin.x)
            .padding(.top, origin.y)
            .frame(width: window?.width ?? size.width, height: window?.height ?? size.height, alignment: .topLeading)
            .accessibilityHidden(true)
    }
}

/// The player's own Liquid Glass, clear so the wallpaper still reads through
/// it and bends at its edges, and smoked just enough for white type over any
/// photo: the glass the island itself takes when it is set to glass. Before
/// macOS 26 the frosted panel of the app's floating surfaces stands in, and
/// Reduce Transparency makes it solid.
private struct NotchLockScreenGlass: ViewModifier {
    let cornerRadius: CGFloat
    /// Understory: the cover's colour, washed through the glass so the pane
    /// takes on the album it plays.
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    ZStack {
                        shape.fill(Color(white: 0.12))
                        if let tint { shape.fill(tint.opacity(0.28)) }
                    }
                } else {
                    ZStack {
                        glass(shape)
                        shape.fill(.black.opacity(contrast == .increased ? 0.5 : 0.28))
                        if let tint {
                            shape.fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.08), .clear],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                }
            }
            .animation(.smooth(duration: 0.8), value: tint)
            // Understory: the cover's glow and the colours stay inside the
            // pane instead of spilling onto the wallpaper around it.
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(contrast == .increased ? 0.45 : 0), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder private func glass(_ shape: RoundedRectangle) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.clear, in: shape)
                .environment(\.appearsActive, true)
                .materialActiveAppearance(.active)
        } else {
            NotchLockScreenMaterial(cornerRadius: cornerRadius)
        }
#else
        NotchLockScreenMaterial(cornerRadius: cornerRadius)
#endif
    }
}

/// The frosted material has to round its own layer: SwiftUI clips what it
/// draws, not a material blurring what lies behind the window.
private struct NotchLockScreenMaterial: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

/// The song in the middle of the lock screen, on one pane of Liquid Glass:
/// the cover, its title, a timeline that seeks and the player's own buttons.
/// A smaller display takes a smaller cover, then lays it beside the title.
struct NotchLockScreenPlayer: View {
    @ObservedObject var model: NotchLockScreenModel
    let size: CGSize
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What a tap on play or pause asked for, shown at once as the island's
    /// own player shows it, until the player says so.
    @State private var requestedPlaying: Bool?
    /// Understory: the lyrics opened over the cover, to read back through.
    @State private var lyricsExpanded = false
    @ObservedObject private var wallpaper = DesktopWallpaperPalette.shared
    @ObservedObject private var lyrics = NotchLyricsService.shared
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    /// The cover's colour, or the wallpaper's for a cover without one.
    private var tint: Color? {
        if let cover = music.artworkTint?.color { return cover }
        _ = wallpaper.revision
        return wallpaper.mainAccent.map(Color.init(nsColor:))
    }
    private var accent: Color { tint ?? .white }
    private var hasTimedLyrics: Bool {
        guard lyricsEnabled, let lyrics = lyrics.lyrics else { return false }
        return !lyrics.instrumental && !lyrics.lines.isEmpty
    }

    var body: some View {
        let shown = model.showsMusic(music.playback)
        ZStack {
            if shown, let playback = music.playback {
                ViewThatFits(in: .vertical) {
                    hero(playback)
                    wide(playback)
                    player(playback, artwork: 112)
                    player(playback, artwork: 84)
                    compact(playback)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: shown)
        // A second tap before the player answers asks for the state after it,
        // so only the player reaching what was asked ends the early word.
        .onChange(of: music.playback?.isPlaying) {
            if music.playback?.isPlaying == requestedPlaying { requestedPlaying = nil }
        }
        .onChange(of: music.playback?.track) {
            requestedPlaying = nil
            lyricsExpanded = false
            loadExtras()
        }
        .onChange(of: hasTimedLyrics) { if !hasTimedLyrics { lyricsExpanded = false } }
        .onAppear(perform: loadExtras)
        // A player that never answers leaves the button as it was.
        .task(id: requestedPlaying) {
            guard requestedPlaying != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { requestedPlaying = nil }
        }
    }

    /// Understory: the lyrics follow the song here too, from the same
    /// lyrics, source and offset as the island's Lyrics page.
    /// The upcoming song comes from the island's own queue, when it is on.
    private func loadExtras() {
        guard let playback = music.playback else { return }
        if lyricsEnabled { NotchLyricsService.shared.update(playback: playback, visible: true) }
        music.setQueueVisible(true)
    }

    private func toggleLyrics() {
        guard hasTimedLyrics else { return }
        if reduceMotion { lyricsExpanded.toggle() } else { withAnimation(.smooth(duration: 0.4)) { lyricsExpanded.toggle() } }
    }

    /// Understory: the next song in the player's queue, one quiet line.
    @ViewBuilder private func upNext() -> some View {
        if let item = music.upcoming?.items.first {
            HStack(spacing: 9) {
                NotchArtwork(image: music.upcomingArtwork[item.id], size: 24)
                Text(FeatureStrings.notchMusicExtras(l10n.language).queue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(item.artist.isEmpty ? item.title : "\(item.title) · \(item.artist)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    private var lyricsEnabled: Bool { NotchLyricsSupport.isEnabled() }

    /// Understory: a tall display stacks a large cover over the title and lyrics.
    private func hero(_ playback: NotchPlayback) -> some View {
        VStack(spacing: 0) {
            Group {
                if lyricsExpanded {
                    NotchLockScreenFullLyrics(playback: playback, tint: accent, alignment: .center)
                        .frame(height: 196)
                        .onTapGesture(perform: toggleLyrics)
                } else {
                    cover(size: 196, playback: playback)
                }
            }
            .padding(.bottom, 18)
            Text(playback.track.title ?? text.mediaNowPlaying)
                .font(.system(size: 21, weight: .bold))
                .lineLimit(1)
            if let artist = playback.track.artist ?? playback.track.album {
                Text(artist)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            if lyricsEnabled, !lyricsExpanded {
                NotchLockScreenLyrics(playback: playback, tint: accent, alignment: .center)
                    .onTapGesture(perform: toggleLyrics)
                    .padding(.top, 14)
            }
            NotchMusicTimeline(playback: playback, service: music, tint: accent)
                .padding(.top, 14)
            transport(playback)
            upNext()
        }
        .pane(width: NotchLockScreenLayout.paneWidth + 40, tint: tint)
    }

    /// Understory: most displays lay the large cover beside the title and lyrics.
    private func wide(_ playback: NotchPlayback) -> some View {
        VStack(spacing: 0) {
            if lyricsExpanded {
                NotchLockScreenFullLyrics(playback: playback, tint: accent, alignment: .leading)
                    .frame(height: 184)
                    .onTapGesture(perform: toggleLyrics)
            } else {
            HStack(alignment: .center, spacing: 24) {
                cover(size: 184, playback: playback)
                VStack(alignment: .leading, spacing: 0) {
                    Text(playback.track.title ?? text.mediaNowPlaying)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(2)
                    if let artist = playback.track.artist ?? playback.track.album {
                        Text(artist)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .padding(.top, 3)
                    }
                    if lyricsEnabled {
                        NotchLockScreenLyrics(playback: playback, tint: accent, alignment: .leading)
                            .onTapGesture(perform: toggleLyrics)
                            .padding(.top, 14)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
            NotchMusicTimeline(playback: playback, service: music, tint: accent)
                .padding(.top, 18)
            transport(playback)
            upNext()
        }
        .pane(width: NotchLockScreenLayout.widePaneWidth, tint: tint)
    }

    private func player(_ playback: NotchPlayback, artwork: CGFloat) -> some View {
        VStack(spacing: 0) {
            cover(size: artwork, playback: playback)
                .padding(.bottom, 14)
            Text(playback.track.title ?? text.mediaNowPlaying)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
            if let artist = playback.track.artist ?? playback.track.album {
                Text(artist)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            NotchMusicTimeline(playback: playback, service: music, tint: accent)
                .padding(.top, 16)
            transport(playback)
        }
        .pane(tint: tint)
    }

    /// A short display lays the cover beside the title, as the island's own
    /// player does.
    private func compact(_ playback: NotchPlayback) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                cover(size: 52, playback: playback)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.track.title ?? text.mediaNowPlaying)
                        .font(.system(size: 16, weight: .bold))
                    if let artist = playback.track.artist ?? playback.track.album {
                        Text(artist).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            NotchMusicTimeline(playback: playback, service: music, tint: accent)
                .padding(.top, 12)
            transport(playback)
        }
        .pane(tint: tint)
    }

    private func cover(size: CGFloat, playback: NotchPlayback) -> some View {
        NotchArtwork(image: music.artwork, size: size, source: playback.track)
            // Understory: a halo of the cover itself, blurred out behind it.
            .background {
                if music.artwork != nil {
                    NotchArtwork(image: music.artwork, size: size, source: playback.track)
                        .blur(radius: size * 0.12)
                        .scaleEffect(1.04)
                        .opacity(0.55)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.04)
            .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.92)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: playback.isPlaying)
    }

    /// The player's own buttons, never a permission prompt: a request made
    /// here would open behind the lock screen, where no one can answer it.
    private func transport(_ playback: NotchPlayback) -> some View {
        HStack(spacing: 46) {
            if !music.lacksTrackSkipping(.previous) {
                button("backward.fill", size: 22, title: text.mediaPrevious, command: .previous, playback: playback)
            }
            button((requestedPlaying ?? playback.isPlaying) ? "pause.fill" : "play.fill", size: 30,
                   title: text.mediaPlayPause, command: .toggle, playback: playback)
            if !music.lacksTrackSkipping(.next) {
                button("forward.fill", size: 22, title: text.mediaNext, command: .next, playback: playback)
            }
        }
        .frame(height: 46)
    }

    private func button(_ symbol: String, size: CGFloat, title: String, command: NotchMusicService.Command,
                        playback: NotchPlayback) -> some View {
        Button {
            let playing = requestedPlaying ?? playback.isPlaying
            // Only a player the island writes to directly answers fast enough
            // to show its word early. A slower path waits for the player.
            if music.send(command, context: playback.commandContext), command == .toggle,
               playback.canSendCommandsDirectly { requestedPlaying = !playing }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: symbol)
                .frame(width: 48, height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
        .disabled(!music.canPerform(command))
        .accessibilityLabel(title)
    }
}

private extension View {
    /// The player's pane, as wide as the timeline needs and no wider.
    func pane(width: CGFloat = NotchLockScreenLayout.paneWidth, tint: Color? = nil) -> some View {
        foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .frame(width: width)
            .modifier(NotchLockScreenGlass(cornerRadius: 34, tint: tint))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Understory: the lyric being sung, bright, between the line before it and
/// the one coming, both dimmed. It keeps its height so the pane never jumps,
/// and shows nothing for a song without timed lyrics.
private struct NotchLockScreenLyrics: View {
    let playback: NotchPlayback
    let tint: Color
    let alignment: HorizontalAlignment
    @ObservedObject private var service = NotchLyricsService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let height: CGFloat = 76

    var body: some View {
        if let lyrics = service.lyrics, !lyrics.instrumental, !lyrics.lines.isEmpty, playback.hasPosition {
            TimelineView(.explicit(lyrics.changeDates(for: playback, offset: service.offset, from: .now))) { context in
                let index = lyrics.activeIndex(at: playback.position(at: context.date), offset: service.offset)
                VStack(alignment: alignment, spacing: 5) {
                    line(lyrics, index.map { $0 - 1 }, current: false)
                    line(lyrics, index, current: true)
                    line(lyrics, index.map { $0 + 1 } ?? 0, current: false)
                }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                .frame(height: Self.height)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: index)
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func line(_ lyrics: NotchLyrics, _ index: Int?, current: Bool) -> some View {
        let text = index.flatMap { lyrics.lines.indices.contains($0) ? lyrics.lines[$0].text : nil } ?? ""
        Text(text.isEmpty && current ? "♪" : text.isEmpty ? " " : text)
            .font(.system(size: current ? 17 : 13, weight: current ? .bold : .medium, design: .rounded))
            .foregroundStyle(current ? tint.opacity(0.98) : .white.opacity(0.45))
            .lineLimit(1)
            .truncationMode(.tail)
            .id("\(current)-\(index ?? -1)")
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
    }
}

/// Understory: every line of the song, opened over the cover with a tap on
/// the lyrics, the one being sung lit and kept in view. Another tap closes it.
private struct NotchLockScreenFullLyrics: View {
    let playback: NotchPlayback
    let tint: Color
    let alignment: HorizontalAlignment
    @ObservedObject private var service = NotchLyricsService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let lyrics = service.lyrics, !lyrics.lines.isEmpty {
            TimelineView(.explicit(lyrics.changeDates(for: playback, offset: service.offset, from: .now))) { context in
                let index = lyrics.activeIndex(at: playback.position(at: context.date), offset: service.offset)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: alignment, spacing: 10) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { offset, line in
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: offset == index ? 19 : 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(offset == index ? tint : .white.opacity(offset < (index ?? 0) ? 0.35 : 0.55))
                                    .multilineTextAlignment(alignment == .leading ? .leading : .center)
                                    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                                    .id(offset)
                            }
                        }
                        .padding(.vertical, 70)
                    }
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                                 .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onAppear { proxy.scrollTo(index ?? 0, anchor: .center) }
                    .onChange(of: index) {
                        if reduceMotion { proxy.scrollTo(index ?? 0, anchor: .center) }
                        else { withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(index ?? 0, anchor: .center) } }
                    }
                }
            }
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
    }
}

/// The activities as one line under the clock, where a phone keeps the
/// widgets of its lock screen: a mark and a reading each, with no card. A
/// line too long for the display gives up its last activities first.
struct NotchLockScreenActivities: View {
    @ObservedObject var model: NotchLockScreenModel
    let size: CGSize
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var display = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var focus = NotchAgentLimitFocus.mostUsed.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let items = available(at: context.date)
            ViewThatFits(in: .horizontal) {
                line(items, at: context.date)
                line(Array(items.prefix(3)), at: context.date)
                line(Array(items.prefix(2)), at: context.date)
                line(Array(items.prefix(1)), at: context.date)
            }
            .frame(width: size.width, height: size.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: items)
        }
        .allowsHitTesting(false)
    }

    private func available(at date: Date) -> [NotchLockScreenActivity] {
        let gates = model.gates
        return NotchLockScreenSupport.activities(
            timer: gates.timer && timer.session.hasSession,
            calendar: calendar.countdown.map {
                ($0.ongoing ? gates.timeLeft : gates.countdown || calendar.isChosen($0.event)) && $0.isShown(at: date, leadTime: calendar.countdownLeadTime)
            } == true,
            agents: gates.agents && !usage.snapshot.live.isEmpty,
            downloads: gates.downloads && downloads.items.contains { $0.active && !$0.completed })
    }

    private func line(_ items: [NotchLockScreenActivity], at date: Date) -> some View {
        HStack(spacing: 26) {
            ForEach(items) { item in
                entry(item, at: date)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.92))
        .lineLimit(1)
        .fixedSize()
        .legibleOnWallpaper()
    }

    @ViewBuilder private func entry(_ item: NotchLockScreenActivity, at date: Date) -> some View {
        switch item {
        case .timer:
            let session = timer.session
            let now = timer.now
            let finished = NotchLockScreenSupport.timerFinished(session, at: now)
            let text = FeatureStrings.notchActivities(l10n.language)
            let clock = finished ? text.finished : NotchTimerSupport.clockText(for: session, at: now)
            HStack(spacing: 7) {
                Image(systemName: finished ? "checkmark.circle.fill" : session.isPaused ? "pause.circle.fill"
                      : session.countsUp ? "stopwatch.fill" : "timer")
                    .foregroundStyle(.orange)
                Text(session.mode == .pomodoro && !finished ? text.phase(session.phase) + " " + clock : clock)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text.phase(session.phase))
            .accessibilityValue(clock)
        case .calendar:
            if let countdown = calendar.countdown {
                let text = FeatureStrings.notchCalendar(l10n.language)
                HStack(spacing: 7) {
                    Image(systemName: "calendar").foregroundStyle(countdown.event.color.color)
                    Text(NotchCalendarStrip.displayTitle(countdown.event, untitled: text.untitled))
                        .frame(maxWidth: 240, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(NotchCalendarSupport.countdownText(until: countdown.target, now: date))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(countdown.ongoing ? text.ongoing : text.next)
            }
        case .agents:
            let working = AgentProvider.allCases.filter { provider in usage.snapshot.live.contains { $0.provider == provider } }
            let reading = NotchAgentSupport.stripReading(usage.snapshot, readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                                         display: NotchAgentLimitDisplay(rawValue: display) ?? .remaining,
                                                         focus: NotchAgentLimitFocus(rawValue: focus) ?? .mostUsed, now: date)
            // The agents and their reading only: a project's name stays off
            // a screen anyone can walk up to.
            HStack(spacing: 7) {
                HStack(spacing: 1) {
                    ForEach(working) { NotchAgentGlyph(provider: $0, size: 13) }
                }
                Text(working.map(\.displayName).joined(separator: " · ") + " " + reading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(working.map(\.displayName).joined(separator: ", ") + ", "
                                + FeatureStrings.notchLockScreen(l10n.language).working)
            .accessibilityValue(reading)
        case .downloads:
            // Progress without the file's name, which stays off the lock screen.
            let fraction = downloads.items.first(where: { $0.active && !$0.completed })?.fraction
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                if let fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                } else {
                    Text(FeatureStrings.notchFiles(l10n.language).inProgress)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private extension View {
    /// White type over any wallpaper, the way the lock screen's own clock
    /// stays readable over a bright photo.
    func legibleOnWallpaper() -> some View {
        shadow(color: .black.opacity(0.3), radius: 8, y: 1)
    }
}
