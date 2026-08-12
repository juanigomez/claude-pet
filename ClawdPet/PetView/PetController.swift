import SwiftUI
import AppKit
import Combine

/// Geometría de la franja donde vive la mascota (la calcula `PetWindowController`).
struct PetLayout: Equatable {
    /// Ancho útil de la ventana-franja (= ancho de la pantalla).
    var width: Double = 1440
    /// Alto total de la ventana-franja.
    var height: Double = 200
    /// Altura del "piso" (borde superior del Dock) medida desde abajo de la ventana.
    var floorY: Double = 70
    /// Escala del pixel-art.
    var scale: Double = 4

    var spriteSide: Double { Double(ClawdSprite.gridSize) * scale }
    var margin: Double { spriteSide * 0.75 }
}

/// Valores que cambian frame a frame. Se publican juntos para hacer un solo
/// `objectWillChange` por tick en lugar de uno por propiedad.
struct PetFrameState: Equatable {
    var x: Double = 300
    var bounceY: Double = 0
    var facing: Facing = .right
    var walkFrame: Int = ClawdSprite.standFrame
    var blinking: Bool = false
    var time: Double = 0
}

/// El cerebro de la mascota: máquina de estados + motor de movimiento a 60 Hz.
@MainActor
final class PetController: ObservableObject {

    // MARK: - Estado publicado

    @Published private(set) var frame = PetFrameState()
    @Published private(set) var state: PetState = .idle
    @Published private(set) var bubble: BubbleContent?
    @Published var layout = PetLayout()
    /// App que reclama atención (se detecta sola, ver `AppResolver`).
    @Published private(set) var pendingApp: TargetApp?
    /// Está abierto el campo para preguntarle a Claude.
    @Published private(set) var isPrompting = false

    /// Avisa a la ventana que tiene que tomar (o soltar) el foco de teclado.
    var onPromptVisibilityChange: ((Bool) -> Void)?
    /// Snapshot de diagnóstico, empujado 4 veces por segundo para `/health`.
    var onDiagnostics: ((String) -> Void)?

    var tint: ClawdTint { .tint(theme: store.config.theme, state: state) }

    // MARK: - Interno

    private let store: ConfigStore
    private var timer: Timer?
    private var targetX: Double?
    private var pauseUntil: Double = 0
    private var arrived = false
    private var bounceStart: Double?
    private var nextBlink: Double = 3
    private var blinkEnd: Double = 0
    private var messageExpiry: Double?
    private var stateEnteredAt: Double = 0
    private var walkAccumulator: Double = 0
    private var lastDiagnosticsPush: Double = 0
    /// De dónde salió el destino actual, para diagnóstico.
    private var targetSource = "—"
    /// Hay una pregunta a `claude -p` en vuelo.
    private var isAnswering = false
    private var cancellables = Set<AnyCancellable>()

    /// Si un estado `thinking` nunca recibe su `idle`, volvemos solos después de esto.
    private let thinkingTimeout: Double = 900 // 15 min

    private var config: PetConfig { store.config }

    /// Origen X en pantalla de la ventana-franja. Lo setea `PetWindowController`.
    var layoutOriginX: Double = 0

    /// Resumen para `/health`: sirve para diagnosticar sin adivinar por screenshots.
    var diagnostics: String {
        let bounds = (state == .idle) ? idleBounds : screenBounds
        let target = targetX.map { String(format: "%.0f", $0) } ?? "—"
        return String(format: "%@ x=%.0f destino=%@ límites=%.0f…%.0f %@%@",
                      state.rawValue, frame.x, target,
                      bounds.lowerBound, bounds.upperBound,
                      pendingApp.map { "app=\($0.name)(\(targetSource)) " } ?? "",
                      bounceStart == nil ? "" : "rebotando")
    }

    init(store: ConfigStore) {
        self.store = store
        self.frame.x = layout.width / 2
        store.$config
            .map(\.scale)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] scale in self?.layout.scale = scale }
            .store(in: &cancellables)
        observeAppSwitches()
    }

    /// Si vos mismo traés al frente la app que estaba reclamando, ya la atendiste:
    /// dejar de saltar. Esto es lo que cubre el caso de "le di el OK en la terminal"
    /// sin depender de que algún hook avise.
    private func observeAppSwitches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, self.state == .needsAction, let pending = self.pendingApp else { return }
                let key = NSWorkspace.applicationUserInfoKey
                guard let app = notification.userInfo?[key] as? NSRunningApplication,
                      app.bundleIdentifier == pending.bundleID else { return }
                self.setState(.idle)
            }
        }
    }

    // MARK: - Ciclo de vida

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // `.common` para que siga animando mientras hay un menú abierto o se arrastra algo.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        pickNewIdleTarget()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        closePrompt()
    }

    // MARK: - API pública

    func apply(_ payload: NotifyPayload) {
        guard let newState = payload.petState else { return }
        // La app se descubre sola desde el PID del hook; `app` es sólo el fallback.
        let target = (newState == .idle)
            ? nil
            : AppResolver.resolve(pid: payload.pid, identifier: payload.app)
        setState(newState, app: target, message: payload.displayMessage, duration: payload.duration)
    }

    /// Cuánto protegemos un aviso recién llegado de que un `thinking` lo pise.
    private let attentionGraceWindow: Double = 1.2

    func setState(_ newState: PetState,
                  app: TargetApp? = nil,
                  message: String? = nil,
                  duration: Double? = nil) {
        // Cada hook de Claude Code arranca su propio proceso, así que dos eventos
        // consecutivos (PostToolUse de una herramienta y PermissionRequest de la
        // siguiente) pueden llegar desordenados por milisegundos. Si dejáramos que un
        // `thinking` atrasado pisara un aviso recién llegado, te perderías el pedido
        // entero. Perder un aviso es mucho peor que atrasarlo, así que gana el aviso.
        if newState == .thinking, state == .needsAction,
           frame.time - stateEnteredAt < attentionGraceWindow {
            return
        }

        let changed = newState != state
        state = newState
        stateEnteredAt = frame.time
        pendingApp = (newState == .idle) ? nil : (app ?? pendingApp)

        switch newState {
        case .idle:
            bubble = nil
            messageExpiry = nil
            bounceStart = nil
            pendingApp = nil
            arrived = false
            pauseUntil = frame.time + 0.2
            pickNewIdleTarget()

        case .thinking:
            bubble = .dots
            messageExpiry = nil
            bounceStart = nil
            targetX = nil          // se queda quieta pensando
            arrived = false

        case .needsAction:
            arrived = false
            bounceStart = nil
            // La burbuja muestra QUÉ app te reclama: es la info accionable, y no
            // caduca — se va cuando clickeás (que te lleva a esa app) o cambia el estado.
            bubble = .attention(app: pendingApp?.name, message: message)
            messageExpiry = nil
            targetX = resolveTargetX(for: pendingApp)
            if changed && config.soundEnabled {
                NSSound.beep()
            }
        }
        if newState != .idle { closePrompt() }
    }

    /// Click sobre la mascota o la burbuja.
    func handleClick() {
        if state == .needsAction {
            // Prioridad: llevarte a la app que te estaba reclamando.
            pendingApp?.activate()
            setState(.idle)
            return
        }
        if config.clickOpensPrompt {
            togglePrompt()
        }
    }

    // MARK: - Campo para preguntarle a Claude

    func togglePrompt() {
        isPrompting ? closePrompt() : openPrompt()
    }

    func openPrompt() {
        guard !isPrompting else { return }
        isPrompting = true
        targetX = nil            // se queda quieta mientras escribís
        bubble = nil
        onPromptVisibilityChange?(true)
    }

    func closePrompt() {
        guard isPrompting else { return }
        isPrompting = false
        onPromptVisibilityChange?(false)
        if state == .idle { pickNewIdleTarget() }
    }

    /// Qué hacemos con lo que escribiste: responder en la burbuja (default) o
    /// mandarlo a Claude Desktop.
    func submitPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        closePrompt()
        guard !trimmed.isEmpty else { return }

        switch config.promptTarget {
        case .bubble:
            askClaude(trimmed)
        case .claudeDesktop:
            switch ClaudeDesktopBridge.send(trimmed) {
            case .success:
                showTransientMessage("Se lo mandé a Claude")
            case .failure(let error):
                showTransientMessage(error.shortMessage, duration: 6)
            }
        }
    }

    /// Corre `claude -p` y muestra la respuesta corta arriba de la cabeza.
    /// Mientras espera, la mascota se queda "pensando" con los puntitos.
    private func askClaude(_ prompt: String) {
        let previousState = state
        isAnswering = true
        setState(.thinking)

        ClaudeCLIBridge.ask(prompt) { [weak self] result in
            guard let self, self.isAnswering else { return }
            self.isAnswering = false
            // Volvemos al estado que había antes de preguntar, sin pisar un aviso
            // que haya llegado mientras tanto.
            if self.state == .thinking {
                self.setState(previousState == .thinking ? .idle : previousState)
            }
            switch result {
            case .success(let answer):
                self.showTransientMessage(answer, duration: max(10, self.config.messageDuration))
            case .failure(let error):
                self.showTransientMessage(error.shortMessage, duration: 8)
            }
        }
    }

    /// Mensaje corto que se auto-oculta, sin cambiar de estado.
    func showTransientMessage(_ text: String, duration: Double = 3) {
        bubble = .text(text)
        messageExpiry = frame.time + duration
    }

    // MARK: - Motor

    private func tick() {
        let dt = 1.0 / 60.0
        var f = frame
        f.time += dt
        let t = f.time

        // Parpadeo aleatorio.
        if t >= nextBlink && blinkEnd < t {
            blinkEnd = t + 0.13
            nextBlink = t + Double.random(in: 2.5...6.5)
        }
        f.blinking = t < blinkEnd

        // Expiración del mensaje transitorio (respuestas, avisos del prompt).
        // La burbuja de atención no caduca: se va al clickear o al cambiar de estado.
        if let expiry = messageExpiry, t >= expiry {
            messageExpiry = nil
            if case .text = bubble { bubble = nil }
        }

        // Watchdog del estado "pensando".
        if state == .thinking, t - stateEnteredAt > thinkingTimeout {
            setState(.idle)
        }

        // Los límites se recalculan seguido (el Dock se mide en vivo y su ancho
        // cambia al abrir/cerrar apps). Si el destino quedó fuera de los límites
        // nuevos, el clamp de abajo frena a la mascota antes de llegar y NUNCA
        // "llega": se queda caminando en el lugar, que es justo lo que se veía como
        // saltitos contra el borde derecho. Recortamos el destino a los límites
        // vigentes para que siempre sea alcanzable.
        let bounds = (state == .idle) ? idleBounds : screenBounds
        if let target = targetX {
            let clamped = min(max(target, bounds.lowerBound), bounds.upperBound)
            if clamped != target { targetX = clamped }
        }

        // Movimiento horizontal (quieta mientras escribís).
        var moving = false
        if !isPrompting, let target = targetX, t >= pauseUntil {
            let delta = target - f.x
            let dist = abs(delta)
            let step = max(8, config.walkSpeed) * dt
            if dist <= step {
                f.x = target
                if !arrived { onArrive(at: t) }
            } else {
                f.x += (delta > 0 ? step : -step)
                f.facing = delta > 0 ? .right : .left
                moving = true
            }
        }

        // Frame de patas: avanza en función de la distancia recorrida, no del tiempo,
        // así la cadencia acompaña a la velocidad de caminata.
        if moving {
            walkAccumulator += max(8, config.walkSpeed) * dt
            let stride = max(4.0, layout.scale * 2.2)
            f.walkFrame = Int(walkAccumulator / stride) % ClawdSprite.walkCycleCount
        } else {
            f.walkFrame = ClawdSprite.standFrame
        }

        // Rebote (estado "necesita acción", una vez que llegó).
        if let start = bounceStart {
            let phase = (t - start) * 2.6
            let raw = abs(sin(phase * .pi))
            f.bounceY = -raw * layout.scale * 4.5
        } else {
            f.bounceY = 0
        }

        // Idle: elegir un nuevo destino cuando terminó la pausa.
        if state == .idle, !isPrompting, targetX == nil, t >= pauseUntil {
            pickNewIdleTarget()
        }

        // En "needsAction" reevaluamos la ventana de la app cada tanto (se puede mover).
        if state == .needsAction, arrived, Int(t * 2) % 6 == 0, let app = pendingApp {
            if let newTarget = resolveTargetX(for: app), abs(newTarget - f.x) > layout.spriteSide {
                targetX = newTarget
                arrived = false
                bounceStart = nil
            }
        }

        f.x = min(max(f.x, bounds.lowerBound), bounds.upperBound)
        frame = f

        // 4 Hz alcanza para diagnosticar y no cuesta nada.
        if t - lastDiagnosticsPush > 0.25 {
            lastDiagnosticsPush = t
            onDiagnostics?(diagnostics)
        }
    }

    private func onArrive(at t: Double) {
        arrived = true
        switch state {
        case .idle:
            targetX = nil
            pauseUntil = t + Double.random(in: 0.8...3.0)
        case .thinking:
            targetX = nil
        case .needsAction:
            bounceStart = t
        }
    }

    // MARK: - Límites del paseo

    /// Todo el ancho de la pantalla, menos un margen para que no se corte el sprite.
    private var screenBounds: ClosedRange<Double> {
        let lo = layout.margin
        let hi = max(lo + 1, layout.width - layout.margin)
        return lo...hi
    }

    /// En idle preferimos que no se pase del Dock: el Dock sólo ocupa el ancho de sus
    /// íconos, así que caminar por todo el ancho de la pantalla la deja paseando sobre
    /// escritorio vacío. Si no podemos leer el Dock (sin permiso de Accesibilidad),
    /// usamos el ancho completo.
    private var idleBounds: ClosedRange<Double> {
        let full = screenBounds
        guard config.stayOnDock, let dock = DockLocator.iconStripFrame() else { return full }
        // Medio sprite: así el cuerpo entero queda sobre los íconos y no se asoma
        // por la curva del borde del Dock.
        let inset = layout.spriteSide * 0.5
        let lo = max(full.lowerBound, dock.minX - layoutOriginX + inset)
        let hi = min(full.upperBound, dock.maxX - layoutOriginX - inset)
        guard hi - lo > layout.spriteSide else { return full }
        return lo...hi
    }

    private func pickNewIdleTarget() {
        guard state == .idle, !isPrompting else { return }
        let bounds = idleBounds
        var candidate = Double.random(in: bounds)
        // Evitar micro-movimientos: forzamos un recorrido mínimo.
        let span = bounds.upperBound - bounds.lowerBound
        if abs(candidate - frame.x) < span * 0.25 {
            candidate = frame.x < (bounds.lowerBound + bounds.upperBound) / 2
                ? bounds.upperBound
                : bounds.lowerBound
        }
        targetX = candidate
        arrived = false
    }

    /// Dónde plantarse para señalar una app.
    ///
    /// Preferimos su **ícono en el Dock**: la mascota camina por el Dock, así que
    /// pararse sobre el ícono es lo que se lee como "es esta app". Usar el centro de
    /// la ventana deja a la mascota en cualquier lado — con una ventana maximizada
    /// termina en el medio de la pantalla, que no señala nada.
    ///
    /// Si la app no está en el Dock (o no hay permiso), caemos al centro de su
    /// ventana frontal, y si tampoco hay, se queda donde está.
    private func resolveTargetX(for app: TargetApp?) -> Double? {
        guard let app else { return frame.x }
        let bounds = screenBounds

        if let icon = DockLocator.iconFrame(bundleID: app.bundleID) {
            targetSource = "ícono-dock"
            return min(max(icon.midX - layoutOriginX, bounds.lowerBound), bounds.upperBound)
        }
        if let windowFrame = AccessibilityLocator.frontWindowFrame(bundleID: app.bundleID) {
            targetSource = "ventana"
            return min(max(windowFrame.midX - layoutOriginX, bounds.lowerBound), bounds.upperBound)
        }
        targetSource = "en-el-lugar"
        return frame.x
    }
}
