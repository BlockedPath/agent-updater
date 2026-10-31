// Renders the app icon: swift make-icon.swift OUT.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tile = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

NSShadow().apply {
    $0.shadowColor = NSColor.black.withAlphaComponent(0.35)
    $0.shadowBlurRadius = 28
    $0.shadowOffset = NSSize(width: 0, height: -12)
}
NSColor.black.setFill()
tile.fill()
NSShadow().set()

NSGradient(colors: [
    NSColor(calibratedRed: 0.62, green: 0.47, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.33, green: 0.62, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.86, alpha: 1),
])!.draw(in: tile, angle: -60)

// Soft highlight across the top.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 180, yRadius: 180), angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.down.circle.dotted", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) { configure(self); set() }
}
