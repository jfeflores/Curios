import AppKit

// Original icon drawn from primitives; no Things artwork is used.
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let rect = NSRect(x: 76, y: 76, width: 872, height: 872)
let card = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)
NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.61, blue: 0.98, alpha: 1), ending: NSColor(srgbRed: 0.24, green: 0.34, blue: 0.83, alpha: 1))!.draw(in: card, angle: -90)
NSColor.white.withAlphaComponent(0.15).setFill()
NSBezierPath(roundedRect: NSRect(x: 208, y: 220, width: 608, height: 584), xRadius: 58, yRadius: 58).fill()
let check = NSBezierPath(); check.move(to: NSPoint(x: 300, y: 510)); check.line(to: NSPoint(x: 445, y: 368)); check.line(to: NSPoint(x: 733, y: 667)); check.lineWidth = 68; check.lineCapStyle = .round; check.lineJoinStyle = .round
NSColor.white.setStroke(); check.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
