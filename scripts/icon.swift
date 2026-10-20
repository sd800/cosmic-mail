import AppKit
import Foundation

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
  NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
func draw(_ pixels: Int) throws {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
    bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
  (transform as NSAffineTransform).concat()
  let tile = NSBezierPath(
    roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 208, yRadius: 208)
  NSGradient(starting: color(82, 156, 202), ending: color(43, 94, 142))!.draw(in: tile, angle: -80)
  let sheet = NSBezierPath(
    roundedRect: NSRect(x: 294, y: 333, width: 436, height: 427), xRadius: 30, yRadius: 30)
  color(235, 243, 248).setFill()
  sheet.fill()
  let line = NSBezierPath()
  line.move(to: NSPoint(x: 366, y: 676))
  line.line(to: NSPoint(x: 658, y: 676))
  line.move(to: NSPoint(x: 366, y: 614))
  line.line(to: NSPoint(x: 610, y: 614))
  line.lineWidth = 18
  line.lineCapStyle = .round
  color(125, 164, 189).setStroke()
  line.stroke()
  let envelope = NSBezierPath(
    roundedRect: NSRect(x: 222, y: 268, width: 580, height: 353), xRadius: 42, yRadius: 42)
  color(246, 249, 250).setFill()
  envelope.fill()
  let fold = NSBezierPath()
  fold.move(to: NSPoint(x: 230, y: 587))
  fold.line(to: NSPoint(x: 489, y: 408))
  fold.curve(
    to: NSPoint(x: 535, y: 408), controlPoint1: NSPoint(x: 504, y: 397),
    controlPoint2: NSPoint(x: 520, y: 397))
  fold.line(to: NSPoint(x: 794, y: 587))
  fold.lineWidth = 21
  fold.lineCapStyle = .round
  fold.lineJoinStyle = .round
  color(65, 121, 162).setStroke()
  fold.stroke()
  NSGraphicsContext.restoreGraphicsState()
  let size = pixels == 1024 ? "icon_512x512@2x.png" : "icon_\(pixels)x\(pixels).png"
  try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: destination).appendingPathComponent(size))
}
for size in [16, 32, 64, 128, 256, 512, 1024] { try draw(size) }
for size in [16, 32, 128, 256] {
  let from = destination + "/icon_\(size*2)x\(size*2).png"
  let to = destination + "/icon_\(size)x\(size)@2x.png"
  if FileManager.default.fileExists(atPath: to) { try FileManager.default.removeItem(atPath: to) }
  try FileManager.default.copyItem(atPath: from, toPath: to)
}
try FileManager.default.removeItem(atPath: destination + "/icon_64x64.png")
