#!/usr/bin/env swift
//
// 生成 zWGestures 的应用图标。
//
// 为什么用脚本而不是塞一张图片：图标要能改（颜色、笔画形状、粗细），而且必须有单一来源。
// 脚本用 CoreGraphics 把图标画出来，再交给 `iconutil` 打成 .icns —— 任何一步都能重来。
//
//   swift scripts/make-app-icon.swift
//
// 产出：
//   zWGestures/Resources/AppIcon.icns      随应用打包
//   docs/icon/appicon-1024.png             母版图（供评审/预览，不进 bundle）
//
// 设计：macOS 图标网格（1024 画布上 824×824 的圆角方块，圆角半径 185）+ 一条手势轨迹。
// 轨迹是应用自己每天在屏幕上画的东西：起笔空心圆、末端实心点，用的是「已识别」轨迹色
// （#20D697，取自 prefs.json 的 PathColorRecognized），形状取「下→右」——
// 用户配置里就有这条（Close），而且它在 16pt 下依然辨认得出来。

import AppKit
import CoreGraphics
import Foundation

// MARK: - 参数

/// 画布边长。所有坐标都按 1024 设计，再按目标尺寸整体缩放。
let canvas: CGFloat = 1024
/// macOS 图标网格：圆角方块占 824×824，居中，圆角半径 185。
let tile: CGFloat = 824
let tileCornerRadius: CGFloat = 185
/// 背景上下两端（深板岩色，和轨迹面板的观感一致）。
let backgroundTop = CGColor(red: 0.145, green: 0.173, blue: 0.227, alpha: 1)
let backgroundBottom = CGColor(red: 0.086, green: 0.102, blue: 0.137, alpha: 1)
/// 已识别轨迹的绿色，与 prefs.json 里的 PathColorRecognized 一致。
let trailColor = CGColor(red: 0.125, green: 0.839, blue: 0.592, alpha: 1)

// MARK: - 变体

/// 图标里的主体笔画。
///
/// 三个候选都不是随便画的：`corner` 与 `loop` 是用户配置里真实存在的手势形状
/// （「Close」= 下→右、「Web Search」= 闭环），`swoosh` 是一条斜向的顺手弧线，
/// 视觉重心最稳、在 16pt 下也最清楚。选哪个是审美问题，所以留给用户定。
enum Variant: String {
    case corner
    case swoosh
    case loop

    var localizedName: String {
        switch self {
        case .corner: "折线（下→右，对应配置里的 Close）"
        case .swoosh: "斜向弧线（视觉最稳）"
        case .loop: "闭环（对应配置里的 Web Search）"
        }
    }
}

let requestedVariant = CommandLine.arguments.dropFirst().first
    .flatMap(Variant.init(rawValue:)) ?? .corner

// MARK: - 绘制

/// 按 `size` 像素渲染一张图标。
///
/// 坐标是 CoreGraphics 默认的「原点在左下、y 向上」；所以轨迹里「向下」是 y 变小。
func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        fatalError("无法创建 \(pixels)×\(pixels) 的位图上下文")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 整体缩放到 1024 设计空间。
    let scale = size / canvas
    context.scaleBy(x: scale, y: scale)

    drawTile(in: context)
    drawTrail(in: context)

    context.flush()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// 圆角方块 + 渐变底 + 顶部一道很淡的高光。
func drawTile(in context: CGContext) {
    let inset = (canvas - tile) / 2
    let rect = CGRect(x: inset, y: inset, width: tile, height: tile)
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: tileCornerRadius,
        cornerHeight: tileCornerRadius,
        transform: nil
    )

    context.saveGState()
    context.addPath(path)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [backgroundTop, backgroundBottom] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }
    // 顶部高光：让方块看起来不是平的。
    if let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            highlight,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.maxY - tile * 0.45),
            options: []
        )
    }
    context.restoreGState()
}

/// 手势轨迹。设计空间 y 向上（「向下」即 y 变小）。
func drawTrail(in context: CGContext) {
    var start = CGPoint(x: 348, y: 667)
    var end = CGPoint(x: 757, y: 327)
    let lineWidth: CGFloat = 68
    let trail = CGMutablePath()

    switch requestedVariant {
    case .corner:
        let corner = CGPoint(x: 348, y: 327)
        trail.move(to: start)
        trail.addLine(to: corner)
        trail.addLine(to: end)

    case .swoosh:
        // 从左下划到右上，微微下凹 —— 像随手甩出的一道笔画。
        start = CGPoint(x: 330, y: 300)
        end = CGPoint(x: 712, y: 716)
        trail.move(to: start)
        trail.addQuadCurve(to: end, control: CGPoint(x: 620, y: 330))

    case .loop:
        // 闭环：从左侧起笔向上、向右、向下、再回到起点附近。
        start = CGPoint(x: 370, y: 512)
        end = CGPoint(x: 372, y: 512)
        trail.move(to: start)
        trail.addCurve(
            to: end,
            control1: CGPoint(x: 370, y: 790),
            control2: CGPoint(x: 690, y: 760)
        )
    }

    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // 柔光：由粗到细叠几层低透明度，代替真正的模糊（图标尺寸小，足够）。
    for (width, alpha) in [(lineWidth * 2.2, 0.10), (lineWidth * 1.6, 0.14)] {
        context.setStrokeColor(trailColor.copy(alpha: alpha)!)
        context.setLineWidth(width)
        context.addPath(trail)
        context.strokePath()
    }

    // 轨迹本体。
    context.setStrokeColor(trailColor)
    context.setLineWidth(lineWidth)
    context.addPath(trail)
    context.strokePath()

    // 起笔：空心圆（内部露出底色，和外挂轨迹面板里的起笔标记一致）。
    let ringRadius: CGFloat = lineWidth * 0.78
    context.setStrokeColor(trailColor)
    context.setLineWidth(lineWidth * 0.42)
    context.strokeEllipse(in: CGRect(
        x: start.x - ringRadius,
        y: start.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))

    // 末端：实心点。
    let dotRadius = lineWidth * 0.62
    context.setFillColor(trailColor)
    context.fillEllipse(in: CGRect(
        x: end.x - dotRadius,
        y: end.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    ))

    context.restoreGState()
}

// MARK: - 输出

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-app-icon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "PNG 编码失败：\(url.lastPathComponent)",
        ])
    }
    try data.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("zWGestures/Resources", isDirectory: true)
let docsIcon = root.appendingPathComponent("docs/icon", isDirectory: true)
// iconset 落在 build/ 里（已 gitignore）：系统临时目录在受限 shell 下不可写，
// 而构建目录总是可写的。
let iconset = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: docsIcon, withIntermediateDirectories: true)

// iconutil 要求的全套尺寸（含 @2x）。
let iconsetFiles: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for file in iconsetFiles {
    try writePNG(renderIcon(size: file.pixels), to: iconset.appendingPathComponent(file.name))
}

// 母版图，便于评审与后续微调。
let master = renderIcon(size: 1024)
try writePNG(master, to: docsIcon.appendingPathComponent("appicon-1024.png"))

// 打包成 .icns。
let icnsURL = resources.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil 失败（退出码 \(iconutil.terminationStatus)）\n".utf8))
    exit(1)
}

let size = (try? FileManager.default.attributesOfItem(atPath: icnsURL.path)[.size] as? Int) ?? 0
print("已生成 \(icnsURL.path)（\(size) 字节）")
print("母版图 \(docsIcon.appendingPathComponent("appicon-1024.png").path)")
