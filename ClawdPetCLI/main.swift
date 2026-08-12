import Foundation

// clawdpet — CLI to trigger the desktop pet's states from any script.
//
//   clawdpet notify --app terminal --state needs_action
//   clawdpet thinking
//   clawdpet done
//   clawdpet idle
//   clawdpet ping
//
// A separate target in the same Xcode project; depends on nothing but Foundation.

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
clawdpet \(version) — notifications for the Claw'd Pet desktop mascot

USAGE
  clawdpet notify [options]
  clawdpet thinking|idle|done|needs-action
  clawdpet ping
  clawdpet --help

OPTIONS for `notify`
  --state <s>      idle | thinking | needs_action   (required)
  --app <alias>    optional: alias, bundle id, or app name (vscode, terminal,
                   ghostty, com.microsoft.VSCode, "Visual Studio Code").
                   If omitted, Claw'd Pet detects on its own the terminal/editor
                   you ran the command from, by climbing the process tree.
  --port <n>       local server port (default: config.json, then 8787)

EXAMPLES
  clawdpet notify --state needs_action
  clawdpet notify --app vscode --state thinking
  clawdpet thinking
  clawdpet done
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
var explicitPort: Int?
var isPing = false

switch command {
case "notify":
    break
case "ping":
    isPing = true
case "thinking", "idle", "done", "needs-action", "needs_action", "needsaction", "alert":
    state = normalizeState(command)
default:
    fail("unknown command «\(command)».\n\n\(usage)")
}

var index = 0
while index < arguments.count {
    let flag = arguments[index]
    func value() -> String {
        guard index + 1 < arguments.count else { fail("missing value for \(flag)") }
        index += 1
        return arguments[index]
    }
    switch flag {
    case "--state", "-s":
        let raw = value()
        guard let normalized = normalizeState(raw) else {
            fail("invalid state «\(raw)» — use idle | thinking | needs_action")
        }
        state = normalized
    case "--app", "-a": app = value()
    case "--port", "-p": explicitPort = Int(value())
    default: fail("unknown option «\(flag)».\n\n\(usage)")
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
    guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { fail("invalid URL") }
    let (data, response, error) = send(URLRequest(url: url))
    if let error {
        fail("Claw'd Pet isn't responding on 127.0.0.1:\(port) — is the app open? (\(error.localizedDescription))")
    }
    guard response?.statusCode == 200 else { fail("unexpected response from the server") }
    print("ok — Claw'd Pet listening on 127.0.0.1:\(port)")
    if let data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let trusted = json["accessibility"] as? Bool {
        print(trusted
              ? "accessibility: granted"
              : "accessibility: MISSING — the pet can't locate windows or measure the Dock")
        let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? nil
        if let dock = root?["dock"] as? String { print("dock detected: \(dock)") }
        if let pet = root?["pet"] as? String { print("pet: \(pet)") }
    }
    exit(0)
}

guard let state else {
    fail("missing --state (idle | thinking | needs_action).\n\n\(usage)")
}

// Mandamos nuestro PID para que la app resuelva sola de qué terminal/editor venimos.
var payload: [String: Any] = ["state": state, "pid": ProcessInfo.processInfo.processIdentifier]
if let app { payload["app"] = app }

guard let url = URL(string: "http://127.0.0.1:\(port)/notify"),
      let body = try? JSONSerialization.data(withJSONObject: payload) else {
    fail("couldn't build the request")
}

var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = body
request.timeoutInterval = 5

let (data, response, error) = send(request)
if let error {
    fail("couldn't reach Claw'd Pet on 127.0.0.1:\(port) — is the app open? (\(error.localizedDescription))")
}
guard let response else { fail("no response from the server") }
guard (200..<300).contains(response.statusCode) else {
    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    fail("server responded \(response.statusCode) \(text)")
}
exit(0)
