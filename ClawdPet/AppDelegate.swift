import AppKit
import Combine

/// Delegate de la app: barra de menú, preferencias y arranque del coordinador.
/// El entry point está en `main.swift` (ver la nota de ahí sobre por qué no `@main`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let coordinator = AppCoordinator(store: .shared)
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var preferences: PreferencesWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // sin ícono en el Dock
        buildStatusItem()
        coordinator.start()

        // Refrescar los checkmarks del menú cuando cambia la config.
        coordinator.store.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenu() }
            .store(in: &cancellables)

        // Atajos para debug, para probar sin buscar el ícono en la barra de menú:
        //   CLAWDPET_SHOW_PREFS=1     abre Preferencias al arrancar
        //   CLAWDPET_OPEN_PROMPT=1    abre el campo de texto
        //   CLAWDPET_TEST_ASK="…"     manda esa pregunta como si la hubieras escrito
        let environment = ProcessInfo.processInfo.environment
        if environment["CLAWDPET_SHOW_PREFS"] == "1" {
            DispatchQueue.main.async { [weak self] in self?.showPreferences() }
        }
        if environment["CLAWDPET_OPEN_PROMPT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.coordinator.controller.openPrompt()
            }
        }
        if let question = environment["CLAWDPET_TEST_ASK"], !question.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.coordinator.controller.submitPrompt(question)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    // MARK: - Barra de menú

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.image()
        item.button?.toolTip = "Claw'd Pet — click para prender/apagar, click derecho para el menú"
        // No asignamos `item.menu`: si lo hacemos, AppKit se queda con TODOS los clicks
        // y no hay forma de distinguir izquierdo de derecho. Manejamos el click nosotros
        // y mostramos el menú a mano sólo cuando corresponde.
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        menu = makeMenu()
        refreshMenu()
    }

    /// Click izquierdo: prende/apaga la mascota al toque. Click derecho: menú.
    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            togglePet()
        }
    }

    private func showMenu() {
        guard let statusItem, let menu else { return }
        refreshMenu()
        // Asignar el menú, hacer click y desasignarlo: así se despliega bajo el ítem
        // con la posición y el resaltado correctos, sin quedarnos con todos los clicks.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// El menú es deliberadamente mínimo: Preferencias y Salir.
    ///
    /// Forzar el estado a mano existía sólo para probar, y confunde: la mascota
    /// refleja lo que hace el agente, no algo que vos elegís. Prender y apagar es
    /// el click izquierdo sobre el ícono; preguntarle algo a Claude es el click
    /// sobre la mascota.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let prefs = NSMenuItem(title: "Preferencias…",
                               action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Salir de Claw'd Pet",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func refreshMenu() {
        // El ícono atenuado dice de un vistazo si la mascota está apagada.
        statusItem?.button?.appearsDisabled = !coordinator.store.config.enabled
    }

    // MARK: - Acciones

    @objc private func togglePet() {
        coordinator.store.config.enabled.toggle()
    }

    @objc private func showPreferences() {
        if preferences == nil {
            preferences = PreferencesWindowController(coordinator: coordinator)
        }
        preferences?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
