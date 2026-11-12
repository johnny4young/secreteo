import AppKit
// Renders packaging/AppIcon.svg into the asset catalog: scripts/render-app-icon.swift
let svg = NSImage(contentsOfFile: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "packaging/AppIcon.svg")!
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Apps/Secreteo/Assets.xcassets/AppIcon.appiconset"
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    svg.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(size).png"))
}
