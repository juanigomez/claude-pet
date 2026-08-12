import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var store: ConfigStore

    var body: some View {
        TabView {
            GeneralTab(coordinator: coordinator, store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            IntegrationTab(coordinator: coordinator, store: store)
                .tabItem { Label("Integración", systemImage: "network") }
            PermissionsTab(coordinator: coordinator)
                .tabItem { Label("Permisos", systemImage: "lock.shield") }
        }
        // El aire de arriba es lo que separa la barra de solapas del title bar de la
        // ventana; sin esto quedan pegadas y se ve un seam gris.
        .padding(.top, 12)
        .frame(width: 540, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var store: ConfigStore
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Mostrar la mascota", isOn: $store.config.enabled)
                Toggle("Sonido al pedir atención", isOn: $store.config.soundEnabled)
                Toggle("Abrir al iniciar sesión", isOn: Binding(
                    get: { store.config.launchAtLogin },
                    set: { newValue in
                        store.config.launchAtLogin = newValue
                        if case .failure(let error) = LoginItemManager.setEnabled(newValue) {
                            loginError = error.localizedDescription
                            store.config.launchAtLogin = LoginItemManager.isEnabled
                        } else {
                            loginError = nil
                        }
                    }))
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Aspecto") {
                Picker("Tema", selection: $store.config.theme) {
                    ForEach(PetTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                ThemePreviewRow(theme: store.config.theme)

                slider("Tamaño", value: $store.config.scale, range: 2...8, step: 1) {
                    "×\(Int($0))"
                }
            }

            Section("Comportamiento") {
                slider("Velocidad", value: $store.config.walkSpeed, range: 10...200) {
                    "\(Int($0)) pt/s"
                }
                slider("Altura", value: $store.config.verticalOffset, range: -40...80, step: 1) {
                    "\(Int($0)) pt"
                }
                slider("Duración del mensaje", value: $store.config.messageDuration,
                       range: 2...60, step: 1) { "\(Int($0)) s" }

                Toggle("No pasarse del Dock", isOn: $store.config.stayOnDock)
                Text("Camina sólo sobre el ancho de los íconos del Dock en vez de toda la pantalla. Necesita permiso de Accesibilidad para medirlo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Click abre el campo para preguntarle a Claude",
                       isOn: $store.config.clickOpensPrompt)
                Text("Cuando la mascota te está reclamando algo, el click siempre te lleva a esa app en vez de abrir el campo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.config.clickOpensPrompt {
                    Picker("Qué hace con tu pregunta", selection: $store.config.promptTarget) {
                        ForEach(PromptTarget.allCases) { target in
                            Text(target.displayName).tag(target)
                        }
                    }
                    if store.config.promptTarget == .bubble {
                        Label(ClaudeCLIBridge.locateBinary().map { "Usa \($0.path) — sin API key ni permisos" }
                              ?? "No encontré el comando `claude`. Instalá Claude Code para usar esta opción.",
                              systemImage: ClaudeCLIBridge.isAvailable ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(ClaudeCLIBridge.isAvailable
                                             ? AnyShapeStyle(.secondary)
                                             : AnyShapeStyle(Color.orange))
                    } else {
                        Text("Necesita permiso de Accesibilidad para escribir en Claude Desktop.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        step: Double? = nil,
                        format: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack {
                if let step {
                    Slider(value: value, in: range, step: step)
                } else {
                    Slider(value: value, in: range)
                }
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 66, alignment: .trailing)
            }
        }
    }
}

/// Muestra la mascota con el tema elegido, en sus tres estados.
private struct ThemePreviewRow: View {
    let theme: PetTheme

    var body: some View {
        HStack(spacing: 22) {
            ForEach(PetState.allCases, id: \.self) { state in
                VStack(spacing: 6) {
                    ClawdSpriteView(scale: 3,
                                    walkFrame: state == .idle ? 0 : ClawdSprite.standFrame,
                                    blinking: false,
                                    tint: .tint(theme: theme, state: state))
                    Text(shortName(state))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func shortName(_ state: PetState) -> String {
        switch state {
        case .idle: return "idle"
        case .thinking: return "pensando"
        case .needsAction: return "alerta"
        }
    }
}

// MARK: - Integración (HTTP + hooks + CLI)

private struct IntegrationTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var store: ConfigStore
    @State private var cliMessage: String?
    @State private var hookMessage: String?

    private var port: Int { store.config.httpPort }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Servidor local") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(coordinator.isServerRunning ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(coordinator.serverStatusText)
                                .font(.callout)
                            Spacer()
                        }
                        HStack {
                            Text("Puerto")
                            TextField("", value: $store.config.httpPort,
                                      format: .number.grouping(.never))
                                .frame(width: 70)
                            Button("Reiniciar servidor") { coordinator.restartServer() }
                        }
                        Text("Sólo escucha en 127.0.0.1; no queda expuesto a la red.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Conectar con Claude Code") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instala `clawdpet` y `clawdpet-hook` en `~/.local/bin` y escribe los hooks en `~/.claude/settings.json`, con backup del que tengas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Conectar ahora") {
                                hookMessage = coordinator.installEverything()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Copiar comando con sudo") {
                                copy(CLIInstaller.manualCommand)
                                cliMessage = "Comando copiado al portapapeles"
                            }
                        }
                        if let hookMessage {
                            Text(hookMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let cliMessage {
                            Text(cliMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("No hace falta configurar qué app es cuál: el hook manda su PID y Claw'd Pet sube por el árbol de procesos hasta la terminal o el editor de donde vino.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Disparar a mano") {
                    VStack(alignment: .leading, spacing: 8) {
                        SnippetView(text: "clawdpet notify --state needs_action --message \"Build falló\"")
                        SnippetView(text: curlSnippet)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private var curlSnippet: String {
        """
        curl -s -X POST http://127.0.0.1:\(port)/notify \\
          -H 'Content-Type: application/json' \\
          -d '{"state":"needs_action","message":"Necesito tu OK"}'
        """
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct SnippetView: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Permisos

private struct PermissionsTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var permissions = PermissionsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: permissions.isTrusted
                      ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permissions.isTrusted ? .green : .orange)
                Text(permissions.isTrusted
                     ? "Accesibilidad concedida"
                     : "Accesibilidad no concedida")
                    .font(.headline)
            }

            Text(PermissionsManager.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !permissions.isTrusted {
                HStack {
                    Button("Pedir permiso") { permissions.requestAccess() }
                        .buttonStyle(.borderedProminent)
                    Button("Abrir Ajustes del Sistema…") { permissions.openSystemSettings() }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("¿Ya lo activaste y sigue en rojo?")
                            .font(.callout.bold())
                        Text(PermissionsManager.staleGrantExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Reiniciar Claw'd Pet") { coordinator.relaunch() }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            // Clave para diagnosticar: el permiso se le da a UNA copia concreta de la
            // app. Si concediste el permiso a otra copia (por ejemplo la de
            // DerivedData) esta no lo tiene.
            Text("Esta copia de la app es la que tiene que estar autorizada:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(Bundle.main.bundleURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Mostrar en el Finder")
            }

            Text("Config guardada en:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ConfigStore.configURL.path)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { permissions.refresh() }
    }
}
