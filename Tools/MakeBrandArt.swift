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
/// signature notch at its tip. Every edge is a curve, the notch included, so
/// the petal reads smooth at any size.
func petal(length l: CGFloat, width w: CGFloat, notch: CGFloat = 0.11) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: l * 0.03))
    p.addCurve(to: CGPoint(x: -w * 0.5, y: l * 0.64),
               control1: CGPoint(x: -w * 0.16, y: l * 0.16), control2: CGPoint(x: -w * 0.52, y: l * 0.38))
    p.addCurve(to: CGPoint(x: -w * 0.17, y: l * 0.985),
               control1: CGPoint(x: -w * 0.48, y: l * 0.86), control2: CGPoint(x: -w * 0.33, y: l * 0.995))
    p.addQuadCurve(to: CGPoint(x: 0, y: l * (1 - notch)), control: CGPoint(x: -w * 0.05, y: l * 0.975))
    p.addQuadCurve(to: CGPoint(x: w * 0.17, y: l * 0.985), control: CGPoint(x: w * 0.05, y: l * 0.975))
    p.addCurve(to: CGPoint(x: w * 0.5, y: l * 0.64),
               control1: CGPoint(x: w * 0.33, y: l * 0.995), control2: CGPoint(x: w * 0.48, y: l * 0.86))
    p.addCurve(to: CGPoint(x: 0, y: l * 0.03),
               control1: CGPoint(x: w * 0.52, y: l * 0.38), control2: CGPoint(x: w * 0.16, y: l * 0.16))
    p.closeSubpath()
    return p
}

func blossom(center c: CGPoint, length: CGFloat, width: CGFloat, rotation: CGFloat,
             gap: CGFloat = 0, notch: CGFloat = 0.11) -> [CGPath] {
    (0..<5).map { i in
        var t = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: rotation + CGFloat(i) * 2 * .pi / 5)
            .translatedBy(x: 0, y: gap)
        return petal(length: length, width: width, notch: notch).copy(using: &t)!
    }
}

// App icon: a soft plum-to-rose squircle with a single, gently shaded blossom.
let icon = canvas { ctx in
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 184, cornerHeight: 184, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.3))
    ctx.addPath(squircle); ctx.setFillColor(color(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    // Deep plum at the foot rising to dusky rose at the top.
    let bg = CGGradient(colorsSpace: rgb, colors: [color(0x24102C), color(0x4B1B45), color(0x8A3A6C)] as CFArray,
                        locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // A soft glow behind the flower, and a sheen along the top edge.
    let halo = CGGradient(colorsSpace: rgb, colors: [color(0xFFB3CC, 0.32), color(0xFFB3CC, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: CGPoint(x: 512, y: 520), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 520), endRadius: 420, options: [])
    let sheen = CGGradient(colorsSpace: rgb, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 700), options: [])

    let center = CGPoint(x: 512, y: 508)
    // Turned a little, so the blossom feels caught rather than placed.
    let petals = blossom(center: center, length: 318, width: 262, rotation: -0.12, gap: 6, notch: 0.1)
    let petalGrad = CGGradient(colorsSpace: rgb,
                               colors: [color(0xEC5C8E), color(0xF9A9C4), color(0xFFE3EC), color(0xFFF8FA)] as CFArray,
                               locations: [0, 0.32, 0.72, 1])!
    for path in petals {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x2A0A22, 0.4))
        ctx.addPath(path); ctx.setFillColor(color(0xF9A9C4)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawRadialGradient(petalGrad, startCenter: center, startRadius: 30,
                               endCenter: center, endRadius: 330, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        // A hairline of light along each petal's rim.
        ctx.addPath(path); ctx.setStrokeColor(color(0xFFFFFF, 0.5)); ctx.setLineWidth(2); ctx.strokePath()
    }

    // A small, delicate heart: fine stamens with gold tips around a deep pink eye.
    ctx.setLineCap(.round)
    for i in 0..<5 {
        let a = CGFloat(i) * 2 * .pi / 5 + .pi / 5 - 0.12
        let end = CGPoint(x: center.x + sin(a) * 70, y: center.y + cos(a) * 70)
        ctx.setStrokeColor(color(0xD9467A, 0.9)); ctx.setLineWidth(5)
        ctx.move(to: center); ctx.addLine(to: end); ctx.strokePath()
        ctx.setFillColor(color(0xFFD27A))
        ctx.fillEllipse(in: CGRect(x: end.x - 11, y: end.y - 11, width: 22, height: 22))
    }
    let heart = CGGradient(colorsSpace: rgb, colors: [color(0xB0164F), color(0xF0628F)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60)); ctx.clip()
    ctx.drawRadialGradient(heart, startCenter: center, startRadius: 0, endCenter: center, endRadius: 30, options: [])
    ctx.restoreGState()
    ctx.restoreGState()
}

// Template glyph: five solid petals with deep notches and a small gap
// between them, around an open eye: the sakura crest, clear at menu bar size.
let glyph = canvas { ctx in
    let center = CGPoint(x: 512, y: 500)
    let petals = blossom(center: center, length: 410, width: 380, rotation: 0, gap: 50, notch: 0.16)
    ctx.setFillColor(color(0x000000))
    for path in petals { ctx.addPath(path); ctx.fillPath() }
    // A thin cut along every petal's edge keeps them apart where they touch.
    ctx.setBlendMode(.clear)
    ctx.setLineWidth(30); ctx.setLineJoin(.round)
    for path in petals { ctx.addPath(path); ctx.strokePath() }
    ctx.fillEllipse(in: CGRect(x: center.x - 92, y: center.y - 92, width: 184, height: 184))
    ctx.setBlendMode(.normal)
    ctx.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
}

try! icon.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-Default.png"))
try! glyph.write(to: URL(fileURLWithPath: "\(outDir)/logo.png"))
print("sakura art written")
