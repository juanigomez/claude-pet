import SwiftUI

/// Reporta hacia AppKit el rectángulo "clickeable" (mascota + burbuja) para poder
/// activar/desactivar `ignoresMouseEvents` según dónde esté el cursor.
private struct HitRectKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = value.union(nextValue())
    }
}

/// Mide el frame de la vista y lo aporta al rectángulo clickeable.
private struct HitRectReporter: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(key: HitRectKey.self,
                                       value: proxy.frame(in: .named("petStrip")))
            }
        }
    }
}

private extension View {
    func reportsHitRect() -> some View { modifier(HitRectReporter()) }
}

/// Contenido de la ventana flotante: una franja transparente del ancho de la pantalla
/// pegada al borde inferior, con la mascota moviéndose adentro.
struct PetRootView: View {
    @ObservedObject var controller: PetController
    /// Rect en coordenadas SwiftUI de la ventana (origen arriba-izquierda).
    var onHitRectChange: (CGRect) -> Void

    private var layout: PetLayout { controller.layout }
    private var scale: CGFloat { CGFloat(layout.scale) }
    private var tint: ClawdTint { controller.tint }

    /// Separación entre la cabeza y la burbuja de "pensando".
    private var headGap: CGFloat { max(6, scale * 1.6) }

    var body: some View {
        GeometryReader { geo in
            let side = CGFloat(layout.spriteSide)
            let centerY = geo.size.height
                - CGFloat(layout.floorY)
                - side / 2
                + CGFloat(controller.frame.bounceY)

            // El sprite espejado (mirar para la izquierda) va en un ZStack, no en
            // `.overlay()`: con `.overlay(alignment:)` sobre una vista con
            // `.scaleEffect(x: -1)`, SwiftUI resuelve el `alignmentGuide` de la
            // burbuja como si el volteo también corriera su eje vertical, y la
            // burbuja terminaba pegada a la cabeza sólo cuando la mascota miraba
            // para la izquierda. El `ZStack` no tiene ese acoplamiento: cada hijo
            // se transforma por separado antes de alinearse.
            ZStack(alignment: .top) {
                ClawdSpriteView(scale: scale,
                                walkFrame: controller.frame.walkFrame,
                                blinking: controller.frame.blinking,
                                tint: tint)
                    .scaleEffect(x: controller.frame.facing.scaleX, y: 1, anchor: .center)
                overhead
            }
            .contentShape(Rectangle())
            .reportsHitRect()
            // Redondeamos a punto entero: el pixel-art se ve sucio si cae en
            // coordenadas fraccionarias (bordes antialiaseados entre colores).
            .position(x: CGFloat(controller.frame.x).rounded(), y: centerY.rounded())
            .onTapGesture { controller.handleClick() }
        }
        .coordinateSpace(name: "petStrip")
        .onPreferenceChange(HitRectKey.self) { rect in
            onHitRectChange(rect.isNull ? .zero : rect)
        }
        .ignoresSafeArea()
    }

    /// Lo único que aparece sobre la cabeza: la burbuja de "pensando". Nada de
    /// contenido en `needsAction` — ese aviso es la mascota yendo hasta la app.
    @ViewBuilder
    private var overhead: some View {
        if controller.state == .thinking {
            SpeechBubbleView(time: controller.frame.time, scale: scale, tint: tint)
                .fixedSize()
                .reportsHitRect()
                // Redefinimos la guía `.top` de la burbuja para que su borde inferior
                // quede `headGap` por encima de la cabeza. Sin esto se superpone
                // con el sprite.
                .alignmentGuide(VerticalAlignment.top) { d in d[.bottom] + headGap }
        }
    }
}
