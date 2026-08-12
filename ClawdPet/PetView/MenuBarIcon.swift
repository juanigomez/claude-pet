import AppKit

/// Ícono de la barra de menú: la misma silueta del sprite, dibujada como
/// *template image* para que macOS la tiña según el modo claro/oscuro.
enum MenuBarIcon {

    static func image() -> NSImage {
        let side: CGFloat = 16
        let cell: CGFloat = side / CGFloat(ClawdSprite.gridSize)

        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current else { return true }

            NSColor.black.setFill()
            for (rowIndex, row) in ClawdSprite.bodyRows.enumerated() {
                for (colIndex, char) in row.enumerated() where char != "." {
                    let rect = NSRect(x: CGFloat(colIndex) * cell,
                                      y: CGFloat(rowIndex) * cell,
                                      width: cell, height: cell)
                    rect.fill()
                }
            }
            // Patas (frame de reposo).
            for leg in ClawdSprite.legColumns {
                let rect = NSRect(x: CGFloat(leg.x) * cell,
                                  y: CGFloat(ClawdSprite.bodyRows.count) * cell,
                                  width: CGFloat(leg.width) * cell,
                                  height: cell * 2)
                rect.fill()
            }
            // Ojos calados, para que se lean como ojos en cualquier tinte.
            context.compositingOperation = .clear
            for row in ClawdSprite.eyeRows {
                let chars = Array(ClawdSprite.bodyRows[row])
                for (colIndex, char) in chars.enumerated() where char == "E" {
                    NSRect(x: CGFloat(colIndex) * cell,
                           y: CGFloat(row) * cell,
                           width: cell, height: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
