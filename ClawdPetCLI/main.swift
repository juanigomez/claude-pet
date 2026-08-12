import Foundation

// clawdpet — CLI para disparar estados de la mascota desde cualquier script.
//
//   clawdpet notify --app terminal --state needs_action --message "Build falló"
//   clawdpet thinking
//   clawdpet done "Terminó el build"
//   clawdpet idle
//   clawdpet ping
//
// Es un target aparte del mismo proyecto Xcode y no depende de nada más que Foundation.

let version = "1.0"

// MARK: - Utilidades

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("clawdpet: \(message)\n".utf8))
    exit(code)
}

func resolvePort(explicit: Int?) -> Int {
    if let explicit { return explicit }
    if let env = ProcessInfo.processInfo.environment["CLAWDPET_PORT"], let port = Int(env) {
        return port
    }
    let configURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ClawdPet/config.json")
    if let data = try? Data(contentsOf: configURL),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let port = json["httpPort"] as? Int {
        return port
    }
    return 8787
}

func normalizeState(_ raw: String) -> String? {
    switch raw.lowercased().replacingOccurrences(of: "-", with: "_") {
    case "idle", "done", "reset": return "idle"
    case "thinking", "working", "busy": return "thinking"
    case "needs_action", "needsaction", "alert", "attention", "waiting": return "needs_action"
    default: return nil
    }
}

let usage = """
clawdpet \(version) — avisos para la mascota de escritorio Claw'd Pet

USO
  clawdpet notify [opciones]
  clawdpet thinking|idle|done|needs-action [mensaje]
  clawdpet ping
  clawdpet --help

OPCIONES de `notify`
  --state <s>      idle | thinking | needs_action   (obligatorio)
  --app <alias>    opcional: alias, bundle id o nombre de la app (vscode, terminal,
                   ghostty, com.microsoft.VSCode, "Visual Studio Code").
                   Si lo omitís, Claw'd Pet detecta sola la terminal/editor desde
                   donde corriste el comando, subiendo por el árbol de procesos.
  --message <txt>  texto corto para la burbuja
  --duration <seg> cuántos segundos dura el mensaje (default: el de Preferencias)
  --port <n>       puerto del servidor local (default: config.json, luego 8787)

EJEMPLOS
  clawdpet notify --state needs_action --message "Build falló"
  clawdpet notify --app vscode --state thinking
  clawdpet thinking
  clawdpet done "Terminó la tarea"
"""

// MARK: - Parseo de argumentos

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage)
    exit(0)
}
arguments.removeFirst()

if command == "--help" || command == "-h" || command == "help" {
    print(usage)
    exit(0)
}
if command == "--version" || command == "-v" {
    print(version)
    exit(0)
}

var state: String?
var app: String?
var message: String?
var duration: Double?
var explicitPort: Int?
var isPing = false

switch command {
case "notify":
    break
case "ping":
    isPing = true
case "thinking", "idle", "done", "needs-action", "needs_action", "needsaction", "alert":
    state = normalizeState(command)
    // El primer argumento suelto se toma como mensaje: `clawdpet done "listo"`.
    if let first = arguments.first, !first.hasPrefix("--") {
        message = first
        arguments.removeFirst()
    }
default:
    fail("comando desconocido «\(command)».\n\n\(usage)")
}

var index = 0
while index < arguments.count {
    let flag = arguments[index]
    func value() -> String {
        guard index + 1 < arguments.count else { fail("falta el valor de \(flag)") }
        index += 1
        return arguments[index]
    }
    switch flag {
    case "--state", "-s":
        let raw = value()
        guard let normalized = normalizeState(raw) else {
            fail("state inválido «\(raw)» — usá idle | thinking | needs_action")
        }
        state = normalized
    case "--app", "-a": app = value()
    case "--message", "-m": message = value()
    case "--duration", "-d": duration = Double(value())
    case "--port", "-p": explicitPort = Int(value())
    default: fail("opción desconocida «\(flag)».\n\n\(usage)")
    }
    index += 1
}

let port = resolvePort(explicit: explicitPort)

// MARK: - Request

func send(_ request: URLRequest) -> (Data?, HTTPURLResponse?, Error?) {
    let semaphore = DispatchSemaphore(value: 0)
    var result: (Data?, HTTPURLResponse?, Error?) = (nil, nil, nil)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        result = (data, response as? HTTPURLResponse, error)
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 5)
    return result
}

if isPing {
    guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { fail("URL inválida") }
    let (data, response, error) = send(URLRequest(url: url))
    if let error {
        fail("Claw'd Pet no responde en 127.0.0.1:\(port) — ¿está abierta la app? (\(error.localizedDescription))")
    }
    guard response?.statusCode == 200 else { fail("respuesta inesperada del servidor") }
    print("ok — Claw'd Pet escuchando en 127.0.0.1:\(port)")
    if let data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let trusted = json["accessibility"] as? Bool {
        print(trusted
              ? "accesibilidad: concedida"
              : "accesibilidad: FALTA — la mascota no puede ubicar ventanas ni medir el Dock")
        let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? nil
        if let dock = root?["dock"] as? String { print("dock detectado: \(dock)") }
        if let pet = root?["pet"] as? String { print("mascota: \(pet)") }
    }
    exit(0)
}

guard let state else {
    fail("falta --state (idle | thinking | needs_action).\n\n\(usage)")
}

// Mandamos nuestro PID para que la app resuelva sola de qué terminal/editor venimos.
var payload: [String: Any] = ["state": state, "pid": ProcessInfo.processInfo.processIdentifier]
if let app { payload["app"] = app }
if let message { payload["message"] = message }
if let duration { payload["duration"] = duration }

guard let url = URL(string: "http://127.0.0.1:\(port)/notify"),
      let body = try? JSONSerialization.data(withJSONObject: payload) else {
    fail("no se pudo armar el request")
}

var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = body
request.timeoutInterval = 5

let (data, response, error) = send(request)
if let error {
    fail("no se pudo avisar a Claw'd Pet en 127.0.0.1:\(port) — ¿está abierta la app? (\(error.localizedDescription))")
}
guard let response else { fail("sin respuesta del servidor") }
guard (200..<300).contains(response.statusCode) else {
    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    fail("el servidor respondió \(response.statusCode) \(text)")
}
exit(0)
