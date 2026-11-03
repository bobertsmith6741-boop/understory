// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors
// Regenerate brand art: swift Tools/MakeBrandArt.swift Resources/Brand
// Draws Understory's sakura brand art.
//   AppIcon-Default.png  1024² macOS app icon: deep plum squircle, pink five-petal blossom
//   logo.png             1024² black blossom glyph on transparent (menu bar template + brand mark)
import AppKit

let outDir = CommandLine.arguments[1]
let rgb = CGColorSpaceCreateDeviceRGB()

func canvas(_ draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// One sakura petal pointing up (+y) from the origin, `length` long, with the
/// signature notch at its tip.
func petal(length l: CGFloat, width w: CGFloat) -> CGPath {
    // Obovate like a real sakura petal: narrow at the heart, full and round
    // at the top, with only a small notch in the middle of the rim.
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: l * 0.05))
    p.addCurve(to: CGPoint(x: -w * 0.5, y: l * 0.72),
               control1: CGPoint(x: -w * 0.30, y: l * 0.22), control2: CGPoint(x: -w * 0.56, y: l * 0.48))
    p.addCurve(to: CGPoint(x: -w * 0.10, y: l * 0.99),
               control1: CGPoint(x: -w * 0.46, y: l * 0.92), control2: CGPoint(x: -w * 0.24, y: l * 1.0))
    p.addLine(to: CGPoint(x: 0, y: l * 0.91))                       // the small notch
    p.addLine(to: CGPoint(x: w * 0.10, y: l * 0.99))
    p.addCurve(to: CGPoint(x: w * 0.5, y: l * 0.72),
               control1: CGPoint(x: w * 0.24, y: l * 1.0), control2: CGPoint(x: w * 0.46, y: l * 0.92))
    p.addCurve(to: CGPoint(x: 0, y: l * 0.05),
               control1: CGPoint(x: w * 0.56, y: l * 0.48), control2: CGPoint(x: w * 0.30, y: l * 0.22))
    p.closeSubpath()
    return p
}

func blossom(center c: CGPoint, length: CGFloat, width: CGFloat, rotation: CGFloat,
             gap: CGFloat = 0) -> [CGPath] {
    (0..<5).map { i in
        var t = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: rotation + CGFloat(i) * 2 * .pi / 5)
            .translatedBy(x: 0, y: gap)
        return petal(length: length, width: width).copy(using: &t)!
    }
}

// App icon
let icon = canvas { ctx in
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(squircle); ctx.setFillColor(color(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: rgb, colors: [color(0x1E0F24), color(0x4A1F45)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // A faint pink bloom of light behind the flower.
    let halo = CGGradient(colorsSpace: rgb, colors: [color(0xFF8FB1, 0.35), color(0xFF8FB1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: 400, options: [])

    let center = CGPoint(x: 512, y: 506)
    let petals = blossom(center: center, length: 300, width: 250, rotation: 0)
    let petalGrad = CGGradient(colorsSpace: rgb, colors: [color(0xFF7FA6), color(0xFFC4D6), color(0xFFF0F5)] as CFArray,
                               locations: [0, 0.55, 1])!
    for path in petals {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x2A0A22, 0.45))
        ctx.addPath(path); ctx.setFillColor(color(0xFFC4D6)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawRadialGradient(petalGrad, startCenter: center, startRadius: 20,
                               endCenter: center, endRadius: 310, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        ctx.addPath(path); ctx.setStrokeColor(color(0xFFFFFF, 0.35)); ctx.setLineWidth(3); ctx.strokePath()
    }

    // Heart of the flower and its stamens.
    ctx.setLineCap(.round)
    for i in 0..<10 {
        let a = CGFloat(i) * 2 * .pi / 10 + .pi / 10
        let end = CGPoint(x: center.x + sin(a) * 92, y: center.y + cos(a) * 92)
        ctx.setStrokeColor(color(0xE0457B)); ctx.setLineWidth(7)
        ctx.move(to: center); ctx.addLine(to: end); ctx.strokePath()
        ctx.setFillColor(color(0xFFD86B))
        ctx.fillEllipse(in: CGRect(x: end.x - 13, y: end.y - 13, width: 26, height: 26))
    }
    let heart = CGGradient(colorsSpace: rgb, colors: [color(0xC2185B), color(0xFF6F9C)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92)); ctx.clip()
    ctx.drawRadialGradient(heart, startCenter: center, startRadius: 0, endCenter: center, endRadius: 46, options: [])
    ctx.restoreGState()
    ctx.restoreGState()
}

// Template glyph: an outlined blossom with stamens, which reads as a flower
// even at menu bar size (a filled silhouette looked like a clover).
let glyph = canvas { ctx in
    let center = CGPoint(x: 512, y: 500)
    ctx.setStrokeColor(color(0x000000)); ctx.setFillColor(color(0x000000))
    ctx.setLineWidth(52); ctx.setLineJoin(.round); ctx.setLineCap(.round)
    for path in blossom(center: center, length: 330, width: 330, rotation: 0, gap: 120) {
        ctx.addPath(path); ctx.strokePath()
    }
    // Stamens in the open heart: short lines with round tips.
    ctx.setLineWidth(26)
    for i in 0..<5 {
        let a = CGFloat(i) * 2 * .pi / 5 + .pi / 5
        let end = CGPoint(x: center.x + sin(a) * 118, y: center.y + cos(a) * 118)
        ctx.move(to: center); ctx.addLine(to: end); ctx.strokePath()
        ctx.fillEllipse(in: CGRect(x: end.x - 30, y: end.y - 30, width: 60, height: 60))
    }
    ctx.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
}

try! icon.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-Default.png"))
try! glyph.write(to: URL(fileURLWithPath: "\(outDir)/logo.png"))
print("sakura art written")
