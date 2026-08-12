#!/usr/bin/env swift
//
// Genera ClawdPet/AppIcon.icns a partir del MISMO sprite que dibuja la app.
//
//   swift Scripts/make-icon.swift
//
// La grilla está duplicada acá a propósito: este script corre suelto, sin el target
// de la app, así que no puede importar `ClawdSprite`. Si tocás el sprite, tocá esto.

import AppKit

let bodyRows = [
    "................",
    "................",
    "....########....",
    "...##########...",
    "..############..",
    "..############..",
    "..############..",
    "AA##EE####EE##AA",
    "AA##EE####EE##AA",
    "AA############AA",
    "..############..",
    "..############..",
    "..############..",
    "..############.."
]
let legColumns = [(2, 2), (5, 2), (9, 2), (12, 2)]
let grid = 16.0

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let body = hex(0xD9714F)
let light = hex(0xE8906F)
let dark = hex(0xB05336)
let eye = hex(0x1A1A1A)

/// Dibuja el ícono en un lienzo cuadrado de `size` puntos.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return true }

        // Fondo: squircle cálido con un degradé suave, como el resto de los íconos de macOS.
        let inset = size * 0.06
        let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let path = CGPath(roundedRect: rect,
                          cornerWidth: rect.width * 0.2237,   // proporción del squircle de Apple
                          cornerHeight: rect.height * 0.2237, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = [hex(0xFDF3EE).cgColor, hex(0xF2D9CB).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.minX, y: rect.minY),
                                   end: CGPoint(x: rect.maxX, y: rect.maxY),
                                   options: [])
        }
        ctx.restoreGState()

        // El sprite, centrado y con aire alrededor.
        let spriteSide = rect.width * 0.62
        let cell = spriteSide / grid
        let originX = rect.midX - spriteSide / 2
        let originY = rect.midY - spriteSide / 2 + cell * 0.5

        func fill(_ col: Int, _ row: Int, _ w: Int, _ h: Int, _ color: NSColor) {
            color.setFill()
            NSRect(x: originX + CGFloat(col) * cell,
                   y: originY + CGFloat(row) * cell,
                   width: CGFloat(w) * cell, height: CGFloat(h) * cell).fill()
        }

        for (rowIndex, row) in bodyRows.enumerated() {
            var col = 0
            let chars = Array(row)
            while col < chars.count {
                let ch = chars[col]
                guard ch != "." else { col += 1; continue }
                var run = 1
                while col + run < chars.count && chars[col + run] == ch { run += 1 }
                let color: NSColor = ch == "E" ? eye
                    : ch == "A" ? dark
                    : rowIndex <= 3 ? light
                    : rowIndex >= 13 ? dark
                    : body
                fill(col, rowIndex, run, 1, color)
                col += run
            }
        }
        for leg in legColumns {
            fill(leg.0, bodyRows.count, leg.1, 2, dark)
        }
        return true
    }
    return image
}

// MARK: - Escribir el .iconset y convertirlo

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (tamaño lógico, sufijo) — cada uno se escribe en 1x y 2x.
let sizes: [Int] = [16, 32, 128, 256, 512]
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = drawIcon(size: CGFloat(pixels))
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { continue }
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let output = root.appendingPathComponent("ClawdPet/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil falló\n".utf8))
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)
print("✔ \(output.path)")
