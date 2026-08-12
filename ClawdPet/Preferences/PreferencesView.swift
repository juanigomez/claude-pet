import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var store: ConfigStore

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            IntegrationTab(coordinator: coordinator, store: store)
                .tabItem { Label("Integration", systemImage: "network") }
            PermissionsTab(coordinator: coordinator)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        // El aire de arriba es lo que separa la barra de solapas del title bar de la
        // ventana; sin esto quedan pegadas y se ve un seam gris.
        .padding(.top, 12)
        .frame(width: 480, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var store: ConfigStore
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show the pet", isOn: $store.config.enabled)
                Toggle("Sound when it needs attention", isOn: $store.config.soundEnabled)
                Toggle("Open at login", isOn: Binding(
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

            Section {
                Toggle("Stay on the Dock", isOn: $store.config.stayOnDock)
                Text("Walks only over the width of the Dock icons instead of the whole screen. Needs Accessibility permission to measure it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                slider("Vertical offset", value: $store.config.verticalOffset,
                       range: -40...80, step: 1) { "\(Int($0)) pt" }
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

// MARK: - Integration (HTTP + hooks + CLI)

private struct IntegrationTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var store: ConfigStore
    @State private var cliMessage: String?
    @State private var hookMessage: String?

    private var port: Int { store.config.httpPort }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Local server") {
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
                            Text("Port")
                            TextField("", value: $store.config.httpPort,
                                      format: .number.grouping(.never))
                                .frame(width: 70)
                            Button("Restart server") { coordinator.restartServer() }
                        }
                        Text("Only listens on 127.0.0.1; never exposed to the network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Connect to Claude Code") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installs `clawdpet` and `clawdpet-hook` in `~/.local/bin` and writes the hooks to `~/.claude/settings.json`, backing up whatever you already have.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Connect now") {
                                hookMessage = coordinator.installEverything()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Copy sudo command") {
                                copy(CLIInstaller.manualCommand)
                                cliMessage = "Command copied to the clipboard"
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
                        Text("No need to configure which app is which: the hook sends its PID and Claw'd Pet climbs the process tree up to the terminal or editor it came from.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Trigger by hand") {
                    VStack(alignment: .leading, spacing: 8) {
                        SnippetView(text: "clawdpet notify --state needs_action")
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
          -d '{"state":"needs_action"}'
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

// MARK: - Permissions

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
                     ? "Accessibility granted"
                     : "Accessibility not granted")
                    .font(.headline)
            }

            Text(PermissionsManager.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !permissions.isTrusted {
                HStack {
                    Button("Request permission") { permissions.requestAccess() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings…") { permissions.openSystemSettings() }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Already turned it on and it's still red?")
                            .font(.callout.bold())
                        Text(PermissionsManager.staleGrantExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Restart Claw'd Pet") { coordinator.relaunch() }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            // Clave para diagnosticar: el permiso se le da a UNA copia concreta de la
            // app. Si concediste el permiso a otra copia (por ejemplo la de
            // DerivedData) esta no lo tiene.
            Text("This is the copy of the app that needs to be authorized:")
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
                .help("Show in Finder")
            }

            Text("Config saved at:")
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
