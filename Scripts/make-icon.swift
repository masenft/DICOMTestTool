// Renders the app icon (1024×1024 PNG): a scanner gantry ring with an echo/pulse line
// connecting two network nodes. Usage: swift Scripts/make-icon.swift <out.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background squircle (macOS icon grid: 824 pt body, 100 pt margin)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(color(0x0B2545)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [color(0x16697A), color(0x0B2545)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// soft highlight
let hl = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(hl, startCenter: CGPoint(x: 380, y: 800), startRadius: 0, endCenter: CGPoint(x: 380, y: 800), endRadius: 520, options: [])

let center = CGPoint(x: 512, y: 512)

// Gantry: inner dark bore + thick white ring with a gap at the bottom
ctx.setFillColor(color(0x061A30, 0.55))
ctx.fillEllipse(in: CGRect(x: center.x - 230, y: center.y - 230, width: 460, height: 460))
ctx.setLineCap(.round)
ctx.setLineWidth(64)
ctx.setStrokeColor(color(0xF1F5F9))
ctx.addArc(center: center, radius: 262, startAngle: -.pi / 2 + 0.42, endAngle: 3 * .pi / 2 - 0.42, clockwise: false)
ctx.strokePath()
// thin accent ring
ctx.setLineWidth(10)
ctx.setStrokeColor(color(0x5EEAD4, 0.8))
ctx.addArc(center: center, radius: 206, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
ctx.strokePath()

// Echo pulse line between two nodes
let y = center.y
let pts: [CGPoint] = [
    CGPoint(x: 250, y: y), CGPoint(x: 390, y: y), CGPoint(x: 425, y: y + 40), CGPoint(x: 460, y: y),
    CGPoint(x: 490, y: y), CGPoint(x: 530, y: y + 190), CGPoint(x: 580, y: y - 170), CGPoint(x: 618, y: y + 30),
    CGPoint(x: 645, y: y), CGPoint(x: 774, y: y),
]
let pulse = CGMutablePath()
pulse.addLines(between: pts)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: color(0x5EEAD4, 0.9))
ctx.addPath(pulse)
ctx.setLineWidth(34)
ctx.setLineJoin(.round)
ctx.setStrokeColor(color(0x99F6E4))
ctx.strokePath()
ctx.restoreGState()

// Nodes
for p in [pts.first!, pts.last!] {
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: p.x - 46, y: p.y - 46, width: 92, height: 92))
    ctx.setFillColor(color(0x16697A))
    ctx.fillEllipse(in: CGRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48))
}
ctx.restoreGState()

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("Icon geschrieben: \(out)")
