import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    try writeIcon(size: size, scale: 1, directory: output)
    try writeIcon(size: size, scale: 2, directory: output)
}

func writeIcon(size: Int, scale: Int, directory: URL) throws {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let background = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 196, yRadius: 196)
    NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.34, alpha: 1).setFill()
    background.fill()

    let trackpad = NSBezierPath(roundedRect: NSRect(x: 232, y: 260, width: 560, height: 476), xRadius: 60, yRadius: 60)
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    trackpad.fill()

    NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.34, alpha: 1).setFill()
    for x in [372, 480, 588] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 428, width: 64, height: 140), xRadius: 32, yRadius: 32).fill()
    }

    NSColor(calibratedWhite: 0.8, alpha: 1).setStroke()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 270, y: 360))
    line.line(to: NSPoint(x: 754, y: 360))
    line.lineWidth = 8
    line.stroke()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let suffix = scale == 2 ? "@2x" : ""
    try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
}
