// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import SwiftUI

/// Understory: the current lyric, one line under the camera while the island
/// is closed and music plays (Canopy-style). Uses the same lyrics, source and
/// offset as the Lyrics page; it only adds a row to the hanging music strip.
enum NotchCompactLyrics {
    static let rowHeight: CGFloat = 22

    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.notchLyricsUnderNotch) && NotchLyricsSupport.isEnabled()
    }

    /// True when there is a timed line to follow for what is playing.
    static func shows(playback: NotchPlayback?) -> Bool {
        guard enabled, let playback, playback.isPlaying, playback.hasPosition,
              let lyrics = NotchLyricsService.shared.lyrics,
              !lyrics.instrumental, !lyrics.lines.isEmpty
        else { return false }
        return true
    }
}

struct NotchCompactLyricLine: View {
    let width: CGFloat
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var service = NotchLyricsService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let playback = music.playback, let lyrics = service.lyrics, !lyrics.lines.isEmpty {
            TimelineView(.explicit(lyrics.changeDates(for: playback, offset: service.offset, from: .now))) { context in
                let index = lyrics.activeIndex(at: playback.position(at: context.date), offset: service.offset)
                let line = index.map { lyrics.lines[$0].text } ?? ""
                Text(line.isEmpty ? "♪" : line)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle((music.artworkTint?.color ?? .white).opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 16)
                    .frame(width: width, height: NotchCompactLyrics.rowHeight, alignment: .center)
                    .id(index ?? -1)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: index)
            }
            .accessibilityHidden(true)
        }
    }
}

/// Keeps lyrics loading for the closed strip and tells the island to grow or
/// shrink when the row comes and goes.
struct NotchCompactLyricsLoader: View {
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var lyrics = NotchLyricsService.shared
    @AppStorage(DefaultsKey.notchLyricsUnderNotch) private var underNotch = true
    @AppStorage(DefaultsKey.notchLyricsOnline) private var online = false
    @State private var shown = false

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear(perform: sync)
            .onChange(of: music.playback?.track.title) { sync() }
            .onChange(of: music.playback?.isPlaying) { relayoutIfNeeded() }
            .onChange(of: lyrics.state) { relayoutIfNeeded() }
            .onChange(of: lyrics.lyrics) { relayoutIfNeeded() }
            .onChange(of: underNotch) { sync() }
            .onChange(of: online) { sync() }
    }

    private func sync() {
        if underNotch, NotchLyricsSupport.isEnabled(), let playback = music.playback {
            lyrics.update(playback: playback, visible: true)
        }
        relayoutIfNeeded()
    }

    private func relayoutIfNeeded() {
        let now = NotchCompactLyrics.shows(playback: music.playback)
        guard now != shown else { return }
        shown = now
        DispatchQueue.main.async { NotchService.shared.refreshPresentation() }
    }
}

/// Understory's own strings. English everywhere until translated.
enum UnderstoryStrings {
    struct QuickSettings {
        let title, lockScreen, lockScreenHint, lyricsUnderNotch, lyricsUnderNotchHint,
            lyricsOnline, lyricsOnlineHint, glow, glowHint, glass, glassHint: String
    }

    static func quickSettings(_ language: AppLanguage) -> QuickSettings {
        switch language {
        case .ptBR: return QuickSettings(
            title: "Ajustes rápidos",
            lockScreen: "Música na tela bloqueada", lockScreenHint: "Mostra o que está tocando quando o Mac está bloqueado.",
            lyricsUnderNotch: "Letra sob o notch", lyricsUnderNotchHint: "A linha atual da letra aparece abaixo da câmera.",
            lyricsOnline: "Buscar letras online", lyricsOnlineHint: "Envia título e artista da música para lrclib.net.",
            glow: "Brilho do álbum", glowHint: "Um brilho suave na cor da capa atrás do player.",
            glass: "Visual de vidro", glassHint: "A ilha aberta usa o vidro transparente do macOS.")
        case .es: return QuickSettings(
            title: "Ajustes rápidos",
            lockScreen: "Música en la pantalla bloqueada", lockScreenHint: "Muestra lo que suena cuando el Mac está bloqueado.",
            lyricsUnderNotch: "Letra bajo el notch", lyricsUnderNotchHint: "La línea actual de la letra aparece bajo la cámara.",
            lyricsOnline: "Buscar letras en línea", lyricsOnlineHint: "Envía el título y el artista a lrclib.net.",
            glow: "Brillo del álbum", glowHint: "Un brillo suave del color de la portada detrás del reproductor.",
            glass: "Aspecto de cristal", glassHint: "La isla abierta usa el cristal transparente de macOS.")
        default: return QuickSettings(
            title: "Quick settings",
            lockScreen: "Music on the lock screen", lockScreenHint: "Show what's playing while your Mac is locked.",
            lyricsUnderNotch: "Lyrics under the notch", lyricsUnderNotchHint: "The current lyric line shows below the camera while music plays.",
            lyricsOnline: "Find lyrics online", lyricsOnlineHint: "Sends the song title and artist to lrclib.net to look up lyrics.",
            glow: "Album glow", glowHint: "A soft glow in the cover's color behind the player.",
            glass: "Glass look", glassHint: "The open island uses macOS's see-through glass.")
        }
    }

    static func simplePreset(_ language: AppLanguage) -> (name: String, description: String) {
        switch language {
        case .ptBR: return ("Simples", "Só a Dynamic Island: música, letras, tela de bloqueio, AirPods e calendário. Busca letras online.")
        case .es: return ("Simple", "Solo la Dynamic Island: música, letras, pantalla bloqueada, AirPods y calendario. Busca letras en línea.")
        default: return ("Simple", "Just the Dynamic Island: music, lyrics, lock screen, AirPods and calendar. Finds lyrics online.")
        }
    }

    static func ambientGlow(_ language: AppLanguage) -> (title: String, caption: String) {
        switch language {
        case .ptBR: return ("Brilho do álbum", "Um brilho suave na cor da capa atrás do player.")
        case .es: return ("Brillo del álbum", "Un brillo suave del color de la portada detrás del reproductor.")
        default: return ("Album glow", "A soft glow in the cover's color behind the player.")
        }
    }

    static func lyricsUnderNotch(_ language: AppLanguage) -> (title: String, caption: String) {
        switch language {
        case .ptBR: return ("Letra sob o notch", "Mostra a linha atual da letra abaixo da câmera enquanto a música toca.")
        case .es: return ("Letra bajo el notch", "Muestra la línea actual de la letra bajo la cámara mientras suena la música.")
        default: return ("Lyrics under the notch", "Show the current lyric line below the camera while music plays, even with the island closed.")
        }
    }
}
