#!/usr/bin/env swift
// 生成应用图标 Resources/AppIcon.icns：鼠尾草绿圆角方底 + 白色茶杯。
// 用法：swift scripts/make-icon.swift   （需要 iconutil，macOS 自带）
// 图形全部用路径绘制（SF Symbols 的许可不允许用于应用图标）。
import AppKit

func drawIcon(in ctx: CGContext, size: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // 底板：macOS 图标网格 824pt 主体，留出阴影空间。
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let plate = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.addPath(plate)
    ctx.setFillColor(NSColor(srgbRed: 0.15, green: 0.43, blue: 0.36, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        NSColor(srgbRed: 0.36, green: 0.66, blue: 0.57, alpha: 1).cgColor,  // 顶部浅一点
        NSColor(srgbRed: 0.15, green: 0.43, blue: 0.36, alpha: 1).cgColor,  // #266D5D
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let white = NSColor.white.cgColor  // 不透明，否则先画的杯把会透出杯身
    ctx.setLineCap(.round)

    // 热气
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.55).cgColor)
    ctx.setLineWidth(24)
    for x in [440.0, 540.0] {
        let steam = CGMutablePath()
        steam.move(to: CGPoint(x: x, y: 690))
        steam.addCurve(to: CGPoint(x: x, y: 800), control1: CGPoint(x: x + 34, y: 725), control2: CGPoint(x: x - 34, y: 765))
        ctx.addPath(steam)
        ctx.strokePath()
    }

    // 杯把
    ctx.setStrokeColor(white)
    ctx.setLineWidth(36)
    ctx.addEllipse(in: CGRect(x: 600, y: 495, width: 120, height: 120))
    ctx.strokePath()

    // 杯身
    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: 322, y: 650))
    cup.addLine(to: CGPoint(x: 658, y: 650))
    cup.addCurve(to: CGPoint(x: 568, y: 418), control1: CGPoint(x: 658, y: 520), control2: CGPoint(x: 630, y: 430))
    cup.addLine(to: CGPoint(x: 412, y: 418))
    cup.addCurve(to: CGPoint(x: 322, y: 650), control1: CGPoint(x: 350, y: 430), control2: CGPoint(x: 322, y: 520))
    cup.closeSubpath()
    ctx.addPath(cup)
    ctx.setFillColor(white)
    ctx.fillPath()

    // 杯碟
    ctx.addPath(CGPath(roundedRect: CGRect(x: 282, y: 352, width: 416, height: 40), cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.fillPath()

    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    drawIcon(in: context.cgContext, size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try png(size: 256).write(to: root.appendingPathComponent("docs/icon.png"))
print(task.terminationStatus == 0 ? "已生成 \(output.path)" : "iconutil 失败")
