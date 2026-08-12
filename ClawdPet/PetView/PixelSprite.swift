import SwiftUI

private func hex(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255,
          green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255)
}

/// Todo el color de la mascota vive acá. Cambiar de tema o de estado es cambiar
/// qué `ClawdTint` se usa: el sprite no sabe nada de temas.
struct ClawdTint: Equatable {
    /// Color principal del cuerpo.
    var body: Color
    /// Fila de arriba (brillo).
    var light: Color
    /// Patas, brazos y fila de abajo (sombra).
    var dark: Color
    /// Ojos.
    var eye: Color
    /// Relleno y borde de la burbuja, y color del texto.
    var bubbleFill: Color
    var bubbleStroke: Color
    var bubbleText: Color

    static func tint(state: PetState) -> ClawdTint {
        let alerting = (state == .needsAction)
        return ClawdTint(body: alerting ? hex(0xE25D33) : hex(0xD9714F),
                         light: alerting ? hex(0xF08355) : hex(0xE8906F),
                         dark: alerting ? hex(0xB84222) : hex(0xB05336),
                         eye: hex(0x1A1A1A),
                         bubbleFill: .white,
                         bubbleStroke: Color.black.opacity(0.10),
                         bubbleText: hex(0x1A1A1A))
    }
}

/// El sprite en sí: una grilla 16x16 declarada como texto.
///
/// - `#` cuerpo
/// - `A` "orejas/brazos" laterales (mismo cuerpo, tono más oscuro)
/// - `E` ojo
/// - `.` transparente
///
/// Las patas NO están en la grilla: se dibujan por código para poder animarlas
/// frame a frame sin duplicar la grilla entera.
enum ClawdSprite {
    static let gridSize = 16
    /// Filas 0...13 del grid. Las filas 14 y 15 quedan para las patas.
    static let bodyRows: [String] = [
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

    /// Columnas (inicio, ancho) de cada pata, de izquierda a derecha.
    static let legColumns: [(x: Int, width: Int)] = [(2, 2), (5, 2), (9, 2), (12, 2)]

    /// Alto de cada pata, en píxeles de grid, para cada frame.
    /// Las patas nacen en `baseRow + bob` y el "piso" está siempre en la fila 16:
    /// una pata de alto 2 con bob 0 toca el piso; una de alto 1 con bob 0 queda
    /// levantada (deja un hueco abajo).
    static let walkFrames: [[Int]] = [
        [2, 1, 2, 1],   // 0 · paso: apoyan 1ª y 3ª
        [1, 1, 1, 1],   // 1 · cuerpo abajo, las cuatro apoyadas
        [1, 2, 1, 2],   // 2 · paso: apoyan 2ª y 4ª
        [1, 1, 1, 1],   // 3 · cuerpo abajo
        [2, 2, 2, 2]    // 4 · quieta (no forma parte del ciclo)
    ]

    /// Rebote del cuerpo por frame. **Entero a propósito**: si el sprite se dibuja en
    /// una `y` fraccionaria, cada fila se antialiasea contra la de al lado y aparecen
    /// costuras horizontales en el cuerpo.
    static let walkBob: [Int] = [0, 1, 0, 1, 0]

    /// Cuántos frames tiene el ciclo de caminata (el último es la pose quieta).
    static let walkCycleCount = 4
    static let standFrame = 4

    /// Filas de los ojos y su alto normal.
    static let eyeRows = 7...8
}

/// Dibuja a Claw'd con `Canvas` + rectángulos sólidos (nada de interpolación ni bitmaps).
///
/// El espejado para mirar a la izquierda se hace ACÁ, corriendo cada rect a su columna
/// simétrica dentro de la grilla, en vez de con `.scaleEffect(x: -1)` en la vista: un
/// `scaleEffect` en un ancestro de la burbuja (ver `PetRootView`) confundía a SwiftUI al
/// resolver su `alignmentGuide`, y la dejaba pegada a la cabeza. Espejando el dibujo
/// adentro del `Canvas`, la vista nunca lleva una transformación — no hay nada que
/// pueda interferir con la burbuja.
struct ClawdSpriteView: View {
    var scale: CGFloat
    var walkFrame: Int
    var blinking: Bool
    var tint: ClawdTint
    var facing: Facing = .right

    private var side: CGFloat { CGFloat(ClawdSprite.gridSize) * scale }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            let s = scale
            let frame = min(max(walkFrame, 0), ClawdSprite.walkFrames.count - 1)
            let bob = ClawdSprite.walkBob[frame]
            let gridSize = ClawdSprite.gridSize
            let mirrored = facing == .left

            func fill(_ col: Int, _ row: Int, _ w: Int, _ h: Int, _ color: Color) {
                let x = mirrored ? gridSize - col - w : col
                let rect = CGRect(x: CGFloat(x) * s,
                                  y: CGFloat(row) * s,
                                  width: CGFloat(w) * s,
                                  height: CGFloat(h) * s)
                context.fill(Path(rect), with: .color(color))
            }

            // --- Cuerpo ---
            for (rowIndex, row) in ClawdSprite.bodyRows.enumerated() {
                let y = rowIndex + bob
                var col = 0
                let chars = Array(row)
                while col < chars.count {
                    let ch = chars[col]
                    guard ch != "." else { col += 1; continue }
                    // Agrupamos celdas contiguas del mismo tipo en un solo rect.
                    var run = 1
                    while col + run < chars.count && chars[col + run] == ch { run += 1 }

                    let isEye = (ch == "E")
                    let isArm = (ch == "A")
                    let color: Color
                    if isEye {
                        color = tint.eye
                    } else if isArm {
                        color = tint.dark
                    } else if rowIndex <= 3 {
                        color = tint.light          // brillo arriba
                    } else if rowIndex >= 13 {
                        color = tint.dark           // sombra abajo
                    } else {
                        color = tint.body
                    }

                    if isEye && blinking {
                        // Parpadeo: el ojo se achica a 1 px, centrado en la fila baja.
                        if rowIndex == ClawdSprite.eyeRows.upperBound {
                            fill(col, y, run, 1, tint.eye)
                        } else {
                            fill(col, y, run, 1, tint.body)
                        }
                    } else {
                        fill(col, y, run, 1, color)
                    }
                    col += run
                }
            }

            // --- Patas ---
            let legHeights = ClawdSprite.walkFrames[frame]
            let baseRow = ClawdSprite.bodyRows.count // 14
            for (index, leg) in ClawdSprite.legColumns.enumerated() {
                fill(leg.x, baseRow + bob, leg.width, legHeights[index], tint.dark)
            }
        }
        .frame(width: side, height: side)
        // Sombrita en el piso para que no parezca flotar.
        .background(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: side * 0.72, height: scale * 1.2)
                .offset(y: scale * 0.4)
                .blur(radius: scale * 0.35)
        }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 24) {
        ForEach(0..<ClawdSprite.walkFrames.count, id: \.self) { frame in
            ClawdSpriteView(scale: 6, walkFrame: frame, blinking: false,
                            tint: .tint(state: .idle))
        }
        ClawdSpriteView(scale: 6, walkFrame: 1, blinking: true, tint: .tint(state: .needsAction))
    }
    .padding(40)
    .background(Color.gray.opacity(0.25))
}
#endif
