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
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: l * 0.06))
    p.addCurve(to: CGPoint(x: -w * 0.5, y: l * 0.93),
               control1: CGPoint(x: -w * 0.62, y: l * 0.28), control2: CGPoint(x: -w * 0.70, y: l * 0.78))
    p.addQuadCurve(to: CGPoint(x: 0, y: l * 0.80), control: CGPoint(x: -w * 0.16, y: l * 1.02))   // into the notch
    p.addQuadCurve(to: CGPoint(x: w * 0.5, y: l * 0.93), control: CGPoint(x: w * 0.16, y: l * 1.02))
    p.addCurve(to: CGPoint(x: 0, y: l * 0.06),
               control1: CGPoint(x: w * 0.70, y: l * 0.78), control2: CGPoint(x: w * 0.62, y: l * 0.28))
    p.closeSubpath()
    return p
}

func blossom(center c: CGPoint, length: CGFloat, width: CGFloat, rotation: CGFloat) -> [CGPath] {
    (0..<5).map { i in
        var t = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: rotation + CGFloat(i) * 2 * .pi / 5)
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

// Template glyph: black blossom, heart knocked out.
let glyph = canvas { ctx in
    let center = CGPoint(x: 512, y: 500)
    ctx.setFillColor(color(0x000000))
    let petals = blossom(center: center, length: 480, width: 330, rotation: 0)
    for path in petals { ctx.addPath(path); ctx.fillPath() }
    // Thin gaps between the petals so the bloom reads at menu bar size.
    ctx.setBlendMode(.clear)
    ctx.setLineWidth(34); ctx.setLineJoin(.round)
    for path in petals { ctx.addPath(path); ctx.strokePath() }
    ctx.fillEllipse(in: CGRect(x: center.x - 78, y: center.y - 78, width: 156, height: 156))
    ctx.setBlendMode(.normal)
    ctx.fillEllipse(in: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68))
}

try! icon.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-Default.png"))
try! glyph.write(to: URL(fileURLWithPath: "\(outDir)/logo.png"))
print("sakura art written")
