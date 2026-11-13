// make_icons.swift: the icons, drawn in code (MANTRA_MANIFEST swift-apps.md rule 4). usage: make_icons <ableton|davinci> <out.iconset>
// A dark panel, the amber ring the Teacher lights on a target, a pointer arrow gliding to it, and the taught app's
// own mark: Ableton Live = a grid of clip squares, DaVinci Resolve = three colour discs.
import AppKit

let kind = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ableton"
let outDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "out.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func draw(_ s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = s / 1024
    let bg = NSBezierPath(roundedRect: NSRect(x: 40 * k, y: 40 * k, width: 944 * k, height: 944 * k), xRadius: 210 * k, yRadius: 210 * k)
    NSColor(srgbRed: 0.059, green: 0.071, blue: 0.09, alpha: 1).setFill()
    bg.fill()
    NSColor(srgbRed: 0.16, green: 0.2, blue: 0.25, alpha: 1).setStroke()
    bg.lineWidth = 8 * k
    bg.stroke()

    if kind == "davinci" {
        let cols: [NSColor] = [NSColor(srgbRed: 0.93, green: 0.25, blue: 0.25, alpha: 0.9),
                               NSColor(srgbRed: 0.25, green: 0.8, blue: 0.4, alpha: 0.9),
                               NSColor(srgbRed: 0.3, green: 0.5, blue: 0.95, alpha: 0.9)]
        let pts: [(CGFloat, CGFloat)] = [(380, 700), (600, 700), (490, 520)]
        for (i, c) in cols.enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: (pts[i].0 - 150) * k, y: (pts[i].1 - 150) * k, width: 300 * k, height: 300 * k)).fill()
        }
    } else {
        for r in 0..<3 {
            for c in 0..<4 {
                let on = (r + c) % 3 == 0
                let col = on ? NSColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 1) : NSColor(srgbRed: 0.28, green: 0.33, blue: 0.4, alpha: 1)
                col.setFill()
                NSBezierPath(roundedRect: NSRect(x: (190 + CGFloat(c) * 160) * k, y: (560 + CGFloat(r) * 120) * k, width: 140 * k, height: 100 * k),
                             xRadius: 18 * k, yRadius: 18 * k).fill()
            }
        }
    }
    NSColor(srgbRed: 1, green: 0.75, blue: 0.2, alpha: 0.95).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 560 * k, y: 170 * k, width: 260 * k, height: 260 * k))
    ring.lineWidth = 26 * k
    ring.stroke()
    let a = NSBezierPath()
    a.move(to: NSPoint(x: 600 * k, y: 330 * k))
    a.line(to: NSPoint(x: 420 * k, y: 140 * k))
    a.line(to: NSPoint(x: 500 * k, y: 160 * k))
    a.line(to: NSPoint(x: 470 * k, y: 60 * k))
    a.line(to: NSPoint(x: 530 * k, y: 50 * k))
    a.line(to: NSPoint(x: 560 * k, y: 150 * k))
    a.line(to: NSPoint(x: 620 * k, y: 120 * k))
    a.close()
    NSColor.white.setFill()
    a.fill()
    NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1).setStroke()
    a.lineWidth = 8 * k
    a.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, CGFloat)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                                  ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                                  ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
for (name, px) in sizes {
    if let d = draw(px).representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: outDir + "/" + name + ".png"))
    }
}
