// Renders the DMG window background (660×400 pt): title, hint and an arrow from the app icon
// (left) to the Applications folder (right). Usage: swift Scripts/make-dmg-background.swift <out.png> <scale>
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "dmg-background.png"
let scale = args.count > 2 ? CGFloat(Double(args[2]) ?? 1) : 1
let size = CGSize(width: 660, height: 400)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background: same navy → teal as the app icon
let bg = NSGradient(colors: [color(0x16697A), color(0x0B2545)])!
bg.draw(in: NSRect(origin: .zero, size: size), angle: -90)

func draw(_ text: String, font: NSFont, color c: NSColor, centerY: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: c, .paragraphStyle: p])
    let h = s.size().height
    s.draw(in: NSRect(x: 0, y: centerY - h / 2, width: size.width, height: h))
}

// AppKit coordinates: y grows upwards. Finder icon centres are at y = 200 from the top → 200 from the bottom.
draw("DICOM Test Tool", font: .systemFont(ofSize: 26, weight: .bold), color: .white, centerY: 352)
draw("Zum Installieren das Programm-Symbol auf den Ordner „Programme“ ziehen",
     font: .systemFont(ofSize: 14, weight: .medium), color: color(0xFFFFFF, 0.85), centerY: 318)

// Arrow between the icons (app at x = 170, Applications at x = 490)
ctx.setStrokeColor(color(0x99F6E4).cgColor)
ctx.setFillColor(color(0x99F6E4).cgColor)
ctx.setLineWidth(6)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [2, 14])
ctx.move(to: CGPoint(x: 262, y: 200)); ctx.addLine(to: CGPoint(x: 382, y: 200)); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.move(to: CGPoint(x: 406, y: 200)); ctx.addLine(to: CGPoint(x: 380, y: 216)); ctx.addLine(to: CGPoint(x: 380, y: 184)); ctx.closePath()
ctx.fillPath()

draw("Beim ersten Start blockiert macOS die App einmalig:",
     font: .systemFont(ofSize: 12), color: color(0xFFFFFF, 0.7), centerY: 62)
draw("Systemeinstellungen › Datenschutz & Sicherheit › „Dennoch öffnen“",
     font: .systemFont(ofSize: 12, weight: .semibold), color: color(0xFFFFFF, 0.85), centerY: 42)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("DMG-Hintergrund geschrieben: \(out)")
