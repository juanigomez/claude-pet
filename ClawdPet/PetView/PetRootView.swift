import SwiftUI

/// Reporta hacia AppKit el rectángulo "clickeable" (mascota + burbuja + campo de texto)
/// para poder activar/desactivar `ignoresMouseEvents` según dónde esté el cursor.
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
    /// Alto real de lo que hay sobre la cabeza (burbuja o campo de texto), para que la
    /// ventana-franja reserve suficiente lugar y una respuesta larga no quede cortada
    /// contra el borde de la ventana ni termine tapando a la mascota.
    var onOverheadHeightChange: (CGFloat) -> Void
    /// Rect en coordenadas SwiftUI de la ventana (origen arriba-izquierda).
    var onHitRectChange: (CGRect) -> Void

    @State private var promptText = ""
    @FocusState private var promptFocused: Bool
    /// Ancho medido de lo que hay sobre la cabeza, para poder mantenerlo en pantalla.
    @State private var overheadWidth: CGFloat = 0

    private var layout: PetLayout { controller.layout }
    private var scale: CGFloat { CGFloat(layout.scale) }
    private var tint: ClawdTint { controller.tint }

    /// Separación entre la cabeza y lo que sea que esté arriba (burbuja o input).
    private var headGap: CGFloat { max(6, scale * 1.6) }
    /// Aire mínimo contra los bordes de la pantalla.
    private var edgeInset: CGFloat { 10 }

    /// Cuánto hay que correr la burbuja para que no se salga de la pantalla.
    ///
    /// La burbuja va centrada en la mascota, pero es mucho más ancha que ella: con la
    /// mascota cerca de un borde, media respuesta quedaba cortada fuera de pantalla.
    /// La corremos hacia adentro y la colita compensa para seguir apuntándole.
    private var overheadShift: CGFloat {
        guard overheadWidth > 0 else { return 0 }
        let petX = CGFloat(controller.frame.x)
        let half = overheadWidth / 2
        let width = CGFloat(layout.width)
        if petX - half < edgeInset { return edgeInset - (petX - half) }
        if petX + half > width - edgeInset { return (width - edgeInset) - (petX + half) }
        return 0
    }

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
        .onChange(of: controller.isPrompting) { _, prompting in
            if prompting {
                promptText = ""
                // Un tick de delay: el campo tiene que existir antes de enfocarlo.
                DispatchQueue.main.async { promptFocused = true }
            } else {
                promptFocused = false
            }
        }
        .ignoresSafeArea()
    }

    /// Lo que aparece sobre la cabeza: el campo de texto tiene prioridad sobre la burbuja.
    @ViewBuilder
    private var overhead: some View {
        Group {
            if controller.isPrompting {
                promptField
            } else if let bubble = controller.bubble {
                SpeechBubbleView(content: bubble,
                                 time: controller.frame.time,
                                 scale: scale,
                                 tint: tint,
                                 tailOffset: -overheadShift)
            }
        }
        .fixedSize()
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        overheadWidth = proxy.size.width
                        onOverheadHeightChange(proxy.size.height)
                    }
                    .onChange(of: proxy.size) { _, new in
                        overheadWidth = new.width
                        onOverheadHeightChange(new.height)
                    }
            }
        }
        .offset(x: overheadShift)
        .reportsHitRect()
        // Redefinimos la guía `.top` de lo que va arriba para que su borde inferior
        // quede `headGap` por encima de la cabeza. Sin esto la burbuja se superpone
        // con el sprite.
        .alignmentGuide(VerticalAlignment.top) { d in d[.bottom] + headGap }
        .animation(.easeOut(duration: 0.15), value: controller.isPrompting)
    }

    private var promptField: some View {
        HStack(spacing: 6) {
            TextField("Preguntale a Claude…", text: $promptText)
                .textFieldStyle(.plain)
                .font(.system(size: max(11, scale * 2.6), design: .rounded))
                .foregroundStyle(tint.bubbleText)
                .focused($promptFocused)
                .frame(width: max(180, scale * 52))
                .onSubmit { controller.submitPrompt(promptText) }

            Button {
                controller.submitPrompt(promptText)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: max(13, scale * 3.2)))
                    .foregroundStyle(tint.bubbleText.opacity(promptText.isEmpty ? 0.25 : 0.75))
            }
            .buttonStyle(.plain)
            .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, max(8, scale * 2.2))
        .padding(.vertical, max(6, scale * 1.6))
        .padding(.bottom, max(5, scale * 1.3))
        .background {
            let shape = BubbleShape(corner: max(8, scale * 2.2),
                                    tailWidth: max(12, scale * 3.4),
                                    tailHeight: max(5, scale * 1.1),
                                    tailOffset: -overheadShift)
            shape
                .fill(tint.bubbleFill)
                .overlay { shape.stroke(tint.bubbleStroke, lineWidth: 1) }
                .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
        }
        .onExitCommand { controller.closePrompt() }   // Escape cierra
    }
}
