import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    try writeIcon(size: size, scale: 1, directory: output)
    try writeIcon(size: size, scale: 2, directory: output)
}
try writeMenuBarIcon(directory: output.deletingLastPathComponent())

func writeIcon(size: Int, scale: Int, directory: URL) throws {
    let pixels = size * scale
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let colors = [NSColor(srgbRed: 238.0 / 255, green: 189.0 / 255, blue: 137.0 / 255, alpha: 1).cgColor,
                  NSColor(srgbRed: 209.0 / 255, green: 58.0 / 255, blue: 189.0 / 255, alpha: 1).cgColor]
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                    colors: colors as CFArray, locations: nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.saveGState()
    context.addPath(CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864),
                           cornerWidth: 196, cornerHeight: 196, transform: nil))
    context.clip()
    context.drawLinearGradient(gradient, start: CGPoint(x: 80, y: 944), end: CGPoint(x: 944, y: 80), options: [])
    context.restoreGState()

    drawTrackpad(in: context, lineWidth: max(24, 1280 / CGFloat(pixels)))

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let suffix = scale == 2 ? "@2x" : ""
    try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
}

func writeMenuBarIcon(directory: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let context = graphics.cgContext
    context.scaleBy(x: 40.0 / 640, y: 40.0 / 640)
    context.translateBy(x: -192, y: -192)
    drawTrackpad(in: context, lineWidth: 44)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: directory.appendingPathComponent("MenuBarIcon.png"))
}

func drawTrackpad(in context: CGContext, lineWidth: CGFloat) {
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(CGPath(roundedRect: CGRect(x: 236, y: 292, width: 552, height: 440),
                           cornerWidth: 64, cornerHeight: 64, transform: nil))
    context.move(to: CGPoint(x: 236, y: 448))
    context.addLine(to: CGPoint(x: 788, y: 448))
    context.move(to: CGPoint(x: 512, y: 292))
    context.addLine(to: CGPoint(x: 512, y: 448))
    context.strokePath()
}
