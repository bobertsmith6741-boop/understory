// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import AppKit
import Combine

/// Colors read from each display's wallpaper, for widgets set to match it.
/// The wallpaper is shrunk to a small grid once per change, so asking for
/// the colors behind a widget costs a few dozen pixel reads.
final class DesktopWallpaperPalette: ObservableObject {
    static let shared = DesktopWallpaperPalette()

    struct Sample: Equatable {
        /// Text that stays readable on the part of the wallpaper behind it.
        let text: NSColor
        /// The wallpaper's most vivid color, brightened to work as an accent.
        let accent: NSColor
    }

    private struct Grid {
        let url: URL
        let screenFrame: NSRect
        let width: Int
        let height: Int
        /// RGB triples, row 0 at the top.
        let pixels: [UInt8]
        let accent: NSColor
    }

    /// Bumped whenever any display's wallpaper is read again.
    @Published private(set) var revision = 0

    private var grids: [CGDirectDisplayID: Grid] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var running = false

    private init() {}

    /// Understory: the widgets and the lock screen each hold the palette, and
    /// it reads the wallpaper while either still does.
    private var holders = Set<String>()

    func setHeld(_ holder: String, _ held: Bool) {
        if held { holders.insert(holder) } else { holders.remove(holder) }
        if holders.isEmpty { stop() } else { start() }
    }

    /// The most vivid colour of the main display's wallpaper.
    var mainAccent: NSColor? {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return nil }
        return grids[screen.displayID]?.accent
    }

    func start() {
        guard !running else { return }
        running = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in self?.reload() })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil,
            queue: .main) { [weak self] _ in self?.reload(force: true) })
        // macOS posts nothing public when the wallpaper changes; a cheap URL
        // check every so often catches it.
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.reload() }
        timer?.tolerance = 5
        reload(force: true)
    }

    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate(); timer = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        grids.removeAll()
    }

    /// The colors for a widget covering `frame`, in global screen coordinates.
    func sample(for frame: NSRect) -> Sample? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main,
              let grid = grids[screen.displayID] else { return nil }
        let bounds = grid.screenFrame
        // Columns and rows of the grid under the frame; the grid's row 0 is the
        // top of the screen, AppKit's y grows upwards.
        func column(_ x: CGFloat) -> Int { Int(((x - bounds.minX) / bounds.width * CGFloat(grid.width)).rounded(.down)) }
        func row(_ y: CGFloat) -> Int { Int(((bounds.maxY - y) / bounds.height * CGFloat(grid.height)).rounded(.down)) }
        let columns = max(0, column(frame.minX))...min(grid.width - 1, max(0, column(frame.maxX)))
        let rows = max(0, row(frame.maxY))...min(grid.height - 1, max(0, row(frame.minY)))
        var luminance = 0.0, count = 0.0
        for y in rows {
            for x in columns {
                let index = (y * grid.width + x) * 3
                let r = Double(grid.pixels[index]) / 255
                let g = Double(grid.pixels[index + 1]) / 255
                let b = Double(grid.pixels[index + 2]) / 255
                luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        let bright = count > 0 && luminance / count > 0.6
        let text = bright ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 1, alpha: 1)
        // A pale accent on a bright area would vanish; deepen it there.
        let accent = bright ? grid.accent.adjusted(brightness: 0.55) : grid.accent
        return Sample(text: text, accent: accent)
    }

    private func reload(force: Bool = false) {
        guard running else { return }
        var changed = false
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = screen.displayID
            seen.insert(id)
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
            if !force, let grid = grids[id], grid.url == url, grid.screenFrame == screen.frame { continue }
            guard let grid = Self.read(url, screenFrame: screen.frame) else { continue }
            grids[id] = grid
            changed = true
        }
        for id in grids.keys where !seen.contains(id) {
            grids.removeValue(forKey: id)
            changed = true
        }
        if changed { revision += 1 }
    }

    /// Draws the wallpaper filling the screen's shape, the way the desktop
    /// shows it, into a grid about 64 cells wide.
    private static func read(_ url: URL, screenFrame: NSRect) -> Grid? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = 64
        let height = max(1, Int((CGFloat(width) * screenFrame.height / max(screenFrame.width, 1)).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            let imageAspect = CGFloat(cgImage.width) / CGFloat(max(cgImage.height, 1))
            let gridAspect = CGFloat(width) / CGFloat(height)
            var rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            if imageAspect > gridAspect {
                rect.size.width = CGFloat(height) * imageAspect
                rect.origin.x = (CGFloat(width) - rect.width) / 2
            } else {
                rect.size.height = CGFloat(width) / imageAspect
                rect.origin.y = (CGFloat(height) - rect.height) / 2
            }
            context.draw(cgImage, in: rect)
            return true
        }
        guard drawn else { return nil }
        // CGContext memory starts at the top row, which is what the grid wants.
        var rgb = [UInt8]()
        rgb.reserveCapacity(width * height * 3)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            rgb.append(pixels[index]); rgb.append(pixels[index + 1]); rgb.append(pixels[index + 2])
        }
        return Grid(url: url, screenFrame: screenFrame, width: width, height: height, pixels: rgb,
                    accent: vividColor(rgb))
    }

    /// The hue with the most vivid pixels behind it, averaged and lifted so
    /// it reads as an accent over glass.
    private static func vividColor(_ rgb: [UInt8]) -> NSColor {
        let buckets = 18
        var weight = [Double](repeating: 0, count: buckets)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: buckets)
        for index in stride(from: 0, to: rgb.count, by: 3) {
            let color = NSColor(srgbRed: CGFloat(rgb[index]) / 255, green: CGFloat(rgb[index + 1]) / 255,
                                blue: CGFloat(rgb[index + 2]) / 255, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            // Grays and near-blacks say nothing about the picture's color.
            guard saturation > 0.2, brightness > 0.2 else { continue }
            let score = Double(saturation * saturation) * Double(min(brightness, 0.9))
            let bucket = min(buckets - 1, Int(hue * CGFloat(buckets)))
            weight[bucket] += score
            sums[bucket].0 += Double(rgb[index]) * score
            sums[bucket].1 += Double(rgb[index + 1]) * score
            sums[bucket].2 += Double(rgb[index + 2]) * score
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else {
            return NSColor(srgbRed: 1, green: 0.56, blue: 0.69, alpha: 1)
        }
        let total = weight[best] * 255
        let average = NSColor(srgbRed: sums[best].0 / total, green: sums[best].1 / total,
                              blue: sums[best].2 / total, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(max(saturation, 0.5), 0.85), brightness: 0.95, alpha: 1)
    }
}

private extension NSColor {
    func adjusted(brightness newBrightness: CGFloat) -> NSColor {
        guard let color = usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha)
    }
}
