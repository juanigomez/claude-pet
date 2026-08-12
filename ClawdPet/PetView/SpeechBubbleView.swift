import SwiftUI

/// Globo de diálogo con colita hacia abajo.
///
/// El contorno es **un solo trazo continuo**: el globo redondeado y la colita salen del
/// mismo `Path`, recorriendo el borde inferior y desviándose hacia la punta al llegar al
/// centro. Antes la colita era un subpath aparte agregado al rounded rect, y aunque el
/// relleno se veía bien, el `stroke` dibujaba también la arista interna donde se tocaban
/// — esa rayita cruzando la base del piquito era lo que quedaba feo.
///
/// La colita tiene los lados rectos y sólo la punta redondeada, y es ancha y baja
/// (≈2,5:1). Con los lados curvados parecía una gota colgando, y angosta y larga,
/// un pincho.
struct BubbleShape: Shape {
    var corner: CGFloat
    var tailWidth: CGFloat
    var tailHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let bottom = rect.maxY - tailHeight              // borde inferior del globo
        let radius = min(corner, min(rect.width, bottom - rect.minY) / 2)
        let cx = rect.midX
        let half = min(tailWidth, rect.width - radius * 2) / 2

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        // Arriba y esquina superior derecha.
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
        // Lado derecho y esquina inferior derecha.
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom - radius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom),
                    tangent2End: CGPoint(x: rect.maxX - radius, y: bottom), radius: radius)
        // Borde inferior hasta la base derecha de la colita.
        path.addLine(to: CGPoint(x: cx + half, y: bottom))

        // La colita: dos lados RECTOS que convergen, y sólo la punta redondeada.
        // Curvar los lados enteros la hacía parecer una gota colgando en vez de un
        // piquito; el ojo lee "globo de diálogo" cuando los lados son rectos.
        let tip = CGPoint(x: cx, y: rect.maxY)
        let edgeLength = (half * half + tailHeight * tailHeight).squareRoot()
        let tipRadius = min(tailHeight * 0.4, half * 0.5)
        // Punto sobre cada lado, a `tipRadius` de la punta: ahí arranca el redondeo.
        let dx = half / edgeLength * tipRadius
        let dy = tailHeight / edgeLength * tipRadius
        path.addLine(to: CGPoint(x: tip.x + dx, y: tip.y - dy))
        path.addQuadCurve(to: CGPoint(x: tip.x - dx, y: tip.y - dy), control: tip)
        path.addLine(to: CGPoint(x: cx - half, y: bottom))
        // Resto del borde inferior y esquina inferior izquierda.
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bottom))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom),
                    tangent2End: CGPoint(x: rect.minX, y: bottom - radius), radius: radius)
        // Lado izquierdo y esquina superior izquierda.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}

/// Los tres puntitos que suben y bajan desfasados, en loop continuo.
struct ThinkingDotsView: View {
    /// Reloj compartido (segundos). Se pasa desde el controlador para que todo
    /// use el mismo tick de 60 Hz y no haya animaciones desincronizadas.
    var time: Double
    var dotSize: CGFloat
    var color: Color

    private let period: Double = 1.1
    private let phaseStep: Double = 0.18
    private var amplitude: CGFloat { dotSize * 0.5 }

    var body: some View {
        HStack(spacing: dotSize * 0.65) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color.opacity(0.7))
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: offset(for: index))
            }
        }
        .frame(height: dotSize + amplitude)
    }

    private func offset(for index: Int) -> CGFloat {
        let phase = (time / period) - Double(index) * phaseStep
        // Media onda seno recortada: el punto "descansa" abajo y salta arriba por turno.
        let wave = sin(phase * 2 * .pi)
        return -amplitude * CGFloat(max(0, wave))
    }
}

enum BubbleContent: Equatable {
    case dots
    case text(String)
    /// Estado "necesita tu acción": mostramos **qué app** te está reclamando, que es
    /// la información accionable, y el mensaje opcional debajo.
    case attention(app: String?, message: String?)
}

struct SpeechBubbleView: View {
    var content: BubbleContent
    var time: Double
    var scale: CGFloat
    var tint: ClawdTint

    /// Medidas derivadas de la escala del sprite, para que la burbuja acompañe
    /// el tamaño de la mascota sin taparla.
    // Ancha y baja (≈2,5:1). Angosta y larga parece una gota colgando.
    private var tailHeight: CGFloat { max(5, scale * 1.1) }
    private var tailWidth: CGFloat { max(12, scale * 3.4) }
    private var corner: CGFloat { max(6, scale * 2.0) }
    private var padH: CGFloat { max(7, scale * 1.9) }
    private var padV: CGFloat { max(5, scale * 1.4) }

    var body: some View {
        Group {
            switch content {
            case .dots:
                ThinkingDotsView(time: time, dotSize: max(4, scale * 1.15), color: tint.bubbleText)
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)
            case .text(let string):
                Text(string)
                    .font(.system(size: max(10, scale * 2.4), weight: .medium, design: .rounded))
                    .foregroundStyle(tint.bubbleText)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // Tope de ancho para que un mensaje largo no se coma la pantalla.
                    .frame(maxWidth: max(180, scale * 52))
                    .padding(.horizontal, padH)
                    .padding(.vertical, padV)

            case .attention(let app, let message):
                VStack(spacing: max(2, scale * 0.5)) {
                    if let app {
                        HStack(spacing: max(3, scale * 0.8)) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: max(9, scale * 2.1)))
                            Text(app)
                                .font(.system(size: max(11, scale * 2.6),
                                              weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(tint.bubbleText)
                    }
                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: max(9, scale * 2.1), design: .rounded))
                            .foregroundStyle(tint.bubbleText.opacity(0.7))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: max(180, scale * 52))
                .padding(.horizontal, padH)
                .padding(.vertical, padV)
            }
        }
        .padding(.bottom, tailHeight)   // el espacio de la colita
        .background {
            let shape = BubbleShape(corner: corner,
                                    tailWidth: tailWidth,
                                    tailHeight: tailHeight)
            shape
                .fill(tint.bubbleFill)
                .overlay { shape.stroke(tint.bubbleStroke, lineWidth: 1) }
                .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        SpeechBubbleView(content: .dots, time: 0.3, scale: 5,
                         tint: .tint(theme: .orange, state: .thinking))
        SpeechBubbleView(content: .text("Necesito tu OK"), time: 0, scale: 5,
                         tint: .tint(theme: .orange, state: .needsAction))
        SpeechBubbleView(content: .text("Necesito tu OK"), time: 0, scale: 5,
                         tint: .tint(theme: .dark, state: .needsAction))
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
#endif
