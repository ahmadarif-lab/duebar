import AppKit

// Draws Resources/AppIcon.png: a blue→indigo squircle with a white card and a coral "due" dot.
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let rect = NSRect(x: 64, y: 64, width: size - 128, height: size - 128)
let path = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
NSGradient(colors: [NSColor(red: 0.20, green: 0.52, blue: 1.0, alpha: 1), NSColor(red: 0.36, green: 0.25, blue: 0.86, alpha: 1)])!
    .draw(in: path, angle: -60)

let card = NSBezierPath(roundedRect: NSRect(x: 214, y: 330, width: 596, height: 392), xRadius: 56, yRadius: 56)
NSColor.white.setFill(); card.fill()
NSColor(red: 0.20, green: 0.30, blue: 0.70, alpha: 0.18).setFill()
NSBezierPath(rect: NSRect(x: 214, y: 560, width: 596, height: 82)).fill()
NSColor(red: 0.20, green: 0.30, blue: 0.70, alpha: 0.35).setFill()
NSBezierPath(roundedRect: NSRect(x: 262, y: 394, width: 180, height: 34), xRadius: 17, yRadius: 17).fill()
NSBezierPath(roundedRect: NSRect(x: 262, y: 452, width: 120, height: 28), xRadius: 14, yRadius: 14).fill()

let dot = NSBezierPath(ovalIn: NSRect(x: 668, y: 628, width: 190, height: 190))
NSColor(red: 0.07, green: 0.09, blue: 0.30, alpha: 0.25).setFill()
NSBezierPath(ovalIn: NSRect(x: 668, y: 618, width: 190, height: 190)).fill()
NSColor(red: 1.0, green: 0.36, blue: 0.36, alpha: 1).setFill(); dot.fill()
let bang = NSAttributedString(string: "!", attributes: [.font: NSFont.systemFont(ofSize: 130, weight: .heavy), .foregroundColor: NSColor.white])
bang.draw(at: NSPoint(x: 733, y: 650))
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
