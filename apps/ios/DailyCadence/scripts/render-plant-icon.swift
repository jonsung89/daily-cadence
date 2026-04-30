#!/usr/bin/env swift

// Renders the Sage-Plant home-screen icon at 1024×1024 to a PNG file
// for use as `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`.
//
// The output is the same artwork as the existing `PlantSage` alternate
// (bundle-root `PlantSage@2x.png` / `@3x.png`) — same `PlantSprout`
// path, same sage tile, same warm-off-white stroke at 55% opacity and
// 1.9% relative line width. Mirrors `AppIconPickerScreen.ThemeIconPreview`
// with `choice = .plantSage`.
//
// Usage:
//   swift apps/ios/DailyCadence/scripts/render-plant-icon.swift [out-path]
//
// Defaults to writing to /tmp/PlantSage-1024.png if no path is given.
//
// Re-runnable; deterministic. If iconography ever changes, edit the
// path coordinates here in lock-step with `JournalShapes.swift`'s
// `PlantSprout` and re-run to regenerate.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Parameters (mirror PlantSage in ThemeIconPreview)

let canvasSize: CGFloat = 1024

// Tile color — sage primary from primary-palettes.json (light mode).
let tileColor = CGColor(
    red: 0x5A / 255.0,
    green: 0x7B / 255.0,
    blue: 0x6D / 255.0,
    alpha: 1.0
)

// Glyph stroke — warm off-white at 55% opacity (default plant glyph
// rule: not blush, not taupe, so we use the "default" branch).
let strokeColor = CGColor(
    red: 0xEA / 255.0,
    green: 0xE6 / 255.0,
    blue: 0xE1 / 255.0,
    alpha: 0.55
)

let strokeWidth = canvasSize * 0.019      // ~19.46pt at 1024
let plantWidth = canvasSize * 0.458       // ~469pt
let plantHeight = canvasSize * 0.625      // 640pt

// MARK: - Build context

guard let context = CGContext(
    data: nil,
    width: Int(canvasSize),
    height: Int(canvasSize),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("Failed to create CGContext\n".data(using: .utf8)!)
    exit(1)
}

// CGContext y-axis is bottom-up; flip to top-down so the path math
// from `PlantSprout.path(in:)` (SwiftUI's top-down system) renders
// the right way up.
context.translateBy(x: 0, y: canvasSize)
context.scaleBy(x: 1, y: -1)

// MARK: - Fill tile

context.setFillColor(tileColor)
context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

// MARK: - Draw plant

// Translate so the plant frame's origin is at the canvas-centered slot.
let plantOrigin = CGPoint(
    x: (canvasSize - plantWidth) / 2,
    y: (canvasSize - plantHeight) / 2
)
context.saveGState()
context.translateBy(x: plantOrigin.x, y: plantOrigin.y)

// `rect` is the plant's local frame. All control points below use
// `rect.midX / maxX / maxY` exactly like `PlantSprout.path(in:)`.
let rect = CGRect(x: 0, y: 0, width: plantWidth, height: plantHeight)

let plantPath = CGMutablePath()

// Stem: bottom-center curve up to a point near the top, with a
// rightward control bias that gives the sprout its hand-drawn lean.
let stemBottom = CGPoint(x: rect.midX, y: rect.maxY)
let stemTop = CGPoint(x: rect.midX + rect.width * 0.06, y: rect.minY + rect.height * 0.12)
let stemCtrl = CGPoint(x: rect.midX + rect.width * 0.20, y: rect.midY)
plantPath.move(to: stemBottom)
plantPath.addQuadCurve(to: stemTop, control: stemCtrl)

// Leaf 1 — lower-left teardrop. `addLeaf` in PlantSprout draws an
// outer arc (base→tip via outerCtrl) and an inner arc (tip→base via
// innerCtrl), forming a closed leaf shape.
do {
    let base = CGPoint(x: rect.midX, y: rect.maxY * 0.62)
    let tip = CGPoint(x: rect.midX - rect.width * 0.34, y: rect.maxY * 0.48)
    let outerCtrl = CGPoint(x: rect.midX - rect.width * 0.20, y: rect.maxY * 0.42)
    let innerCtrl = CGPoint(x: rect.midX - rect.width * 0.10, y: rect.maxY * 0.62)
    plantPath.move(to: base)
    plantPath.addQuadCurve(to: tip, control: outerCtrl)
    plantPath.addQuadCurve(to: base, control: innerCtrl)
}

// Leaf 2 — upper-right teardrop, mirror of leaf 1 above the stem.
do {
    let base = CGPoint(x: rect.midX + rect.width * 0.05, y: rect.maxY * 0.36)
    let tip = CGPoint(x: rect.midX + rect.width * 0.32, y: rect.maxY * 0.22)
    let outerCtrl = CGPoint(x: rect.midX + rect.width * 0.24, y: rect.maxY * 0.18)
    let innerCtrl = CGPoint(x: rect.midX + rect.width * 0.16, y: rect.maxY * 0.36)
    plantPath.move(to: base)
    plantPath.addQuadCurve(to: tip, control: outerCtrl)
    plantPath.addQuadCurve(to: base, control: innerCtrl)
}

context.setStrokeColor(strokeColor)
context.setLineWidth(strokeWidth)
context.setLineCap(.round)
context.setLineJoin(.round)
context.addPath(plantPath)
context.strokePath()

context.restoreGState()

// MARK: - Save PNG

guard let cgImage = context.makeImage() else {
    FileHandle.standardError.write("Failed to materialize CGImage\n".data(using: .utf8)!)
    exit(1)
}

let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/PlantSage-1024.png"
let outputURL = URL(fileURLWithPath: outputPath)
do {
    try pngData.write(to: outputURL)
    print("Wrote \(outputPath) (\(pngData.count) bytes)")
} catch {
    FileHandle.standardError.write("Failed to write \(outputPath): \(error)\n".data(using: .utf8)!)
    exit(1)
}
