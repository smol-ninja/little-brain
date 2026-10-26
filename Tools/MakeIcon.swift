import AppKit
let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let plate = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 220, yRadius: 220)
NSGradient(colors: [NSColor(calibratedRed: 0.08, green: 0.23, blue: 0.31, alpha: 1), NSColor(calibratedRed: 0.13, green: 0.48, blue: 0.51, alpha: 1)])!.draw(in: plate, angle: 65)
NSColor.white.withAlphaComponent(0.18).setStroke()
let rim = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 212, yRadius: 212)
rim.lineWidth = 5; rim.stroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 232, y: 232, width: 560, height: 560))
NSColor.white.withAlphaComponent(0.18).setStroke(); ring.lineWidth = 42; ring.stroke()
let arc = NSBezierPath(); arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 280, startAngle: 90, endAngle: -175, clockwise: true)
NSColor(calibratedRed: 0.6, green: 1, blue: 0.85, alpha: 1).setStroke(); arc.lineWidth = 42; arc.lineCapStyle = .round; arc.stroke()
let check = NSBezierPath(); check.move(to: NSPoint(x: 405, y: 508)); check.line(to: NSPoint(x: 484, y: 432)); check.line(to: NSPoint(x: 628, y: 592))
NSColor.white.setStroke(); check.lineWidth = 44; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
