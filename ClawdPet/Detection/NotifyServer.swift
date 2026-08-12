import Foundation
import Network
import ApplicationServices

/// Servidor HTTP mínimo, sólo en loopback, que recibe los avisos de estado.
///
/// ```
/// POST http://127.0.0.1:8787/notify
/// { "app": "claude-code", "state": "needs_action", "message": "Necesito tu OK" }
/// ```
///
/// También acepta `GET /notify?state=thinking&app=vscode&message=...` para poder
/// dispararlo con un `curl` de una línea, y `GET /health` para chequear que está vivo.
final class NotifyServer {

    enum Status: Equatable {
        case stopped
        case running(port: Int)
        case failed(String)

        var description: String {
            switch self {
            case .stopped: return "detenido"
            case .running(let port): return "escuchando en 127.0.0.1:\(port)"
            case .failed(let reason): return "error: \(reason)"
            }
        }
    }

    /// Se llama en el main thread.
    var onPayload: ((NotifyPayload) -> Void)?
    /// Se llama en el main thread.
    var onStatusChange: ((Status) -> Void)?

    /// Diagnóstico de la mascota para `/health`.
    ///
    /// Las conexiones se atienden en la cola del servidor, no en el main, así que
    /// **no** podemos leer el controller desde acá (`MainActor.assumeIsolated` en un
    /// hilo que no es el main mata el proceso). El controller empuja un snapshot y
    /// nosotros sólo lo leemos, con un lock de por medio.
    private let diagnosticsLock = NSLock()
    private var diagnosticsSnapshot = "—"

    func updateDiagnostics(_ value: String) {
        diagnosticsLock.lock()
        diagnosticsSnapshot = value
        diagnosticsLock.unlock()
    }

    private var currentDiagnostics: String {
        diagnosticsLock.lock()
        defer { diagnosticsLock.unlock() }
        return diagnosticsSnapshot
    }

    private(set) var status: Status = .stopped {
        didSet {
            guard status != oldValue else { return }
            let value = status
            DispatchQueue.main.async { [weak self] in self?.onStatusChange?(value) }
        }
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.clawdpet.notify-server")
    private let maxRequestBytes = 64 * 1024

    // MARK: - Ciclo de vida

    func start(port: Int) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            status = .failed("puerto inválido: \(port)")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind explícito a loopback: el endpoint no queda expuesto a la red.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
        (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay = true

        do {
            // Sin `on:`: el puerto ya viene en `requiredLocalEndpoint`. Pasar los dos
            // hace que NWListener falle con EINVAL.
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.status = .running(port: port)
                case .failed(let error):
                    self.status = .failed(Self.describe(error, port: port))
                case .cancelled:
                    self.status = .stopped
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            status = .failed(Self.describe(error, port: port))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        status = .stopped
    }

    private static func describe(_ error: Error, port: Int) -> String {
        if let nwError = error as? NWError,
           case .posix(let code) = nwError, code == .EADDRINUSE {
            return "el puerto \(port) ya está ocupado"
        }
        return error.localizedDescription
    }

    // MARK: - Conexiones

    private func handle(_ connection: NWConnection) {
        guard isLoopback(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback
        default: return false
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if buffer.count > self.maxRequestBytes {
                self.respond(on: connection, status: 413,
                             body: NotifyResponse(ok: false, error: "request demasiado grande"))
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            if let request = HTTPRequest(buffer) {
                self.route(request, on: connection)
                return
            }

            if isComplete {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/dock-debug"):
            respond(on: connection, status: 200,
                    body: NotifyResponse(ok: true, state: DockLocator.debugItems()))

        case ("GET", "/health"), ("GET", "/"):
            respond(on: connection, status: 200,
                    body: NotifyResponse(ok: true, state: "up",
                                         accessibility: AXIsProcessTrusted(),
                                         dock: DockLocator.iconStripFrame().map {
                                             "x \(Int($0.minX))…\(Int($0.maxX)) (ancho \(Int($0.width)))"
                                         },
                                         pet: currentDiagnostics))

        case ("POST", "/notify"), ("GET", "/notify"):
            // El cuerpo puede ser el JSON crudo del hook de Claude Code (sin `state`),
            // así que el query string manda: es donde el hook pone state y pid sin
            // tener que escapar nada.
            var payload = (try? JSONDecoder().decode(NotifyPayload.self, from: request.body))
                ?? NotifyPayload()
            if let state = request.query["state"] { payload.state = state }
            if let app = request.query["app"] { payload.app = app }
            if let message = request.query["message"] { payload.message = message }
            if let pid = request.query["pid"].flatMap(Int32.init) { payload.pid = pid }
            if let duration = request.query["duration"].flatMap(Double.init) { payload.duration = duration }

            guard !payload.state.isEmpty else {
                respond(on: connection, status: 400,
                        body: NotifyResponse(ok: false,
                                             error: "falta `state` (en el JSON o como ?state=)"))
                return
            }
            deliver(payload, on: connection)

        default:
            respond(on: connection, status: 404, body: NotifyResponse(ok: false, error: "ruta desconocida"))
        }
    }

    private func deliver(_ payload: NotifyPayload, on connection: NWConnection) {
        guard let resolved = payload.petState else {
            respond(on: connection, status: 400,
                    body: NotifyResponse(ok: false,
                                         error: "state debe ser idle | thinking | needs_action"))
            return
        }
        DispatchQueue.main.async { [weak self] in self?.onPayload?(payload) }
        respond(on: connection, status: 200,
                body: NotifyResponse(ok: true, state: resolved.rawValue, app: payload.app))
    }

    private func respond(on connection: NWConnection, status: Int, body: NotifyResponse) {
        let json = (try? JSONEncoder().encode(body)) ?? Data("{\"ok\":false}".utf8)
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(json.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(json)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        default: return "Error"
        }
    }
}

// MARK: - Parser HTTP mínimo

/// Sólo lo necesario: línea de request, `Content-Length` y body.
/// Devuelve `nil` mientras el request todavía esté incompleto.
struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data

    init?(_ buffer: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return nil }

        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0]).uppercased()

        let target = String(parts[1])
        if let questionMark = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<questionMark])
            query = HTTPRequest.parseQuery(String(target[target.index(after: questionMark)...]))
        } else {
            path = target
            query = [:]
        }

        let contentLength = lines.dropFirst()
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0

        let bodyStart = headerEnd.upperBound
        let available = buffer.count - buffer.distance(from: buffer.startIndex, to: bodyStart)
        guard available >= contentLength else { return nil }   // faltan bytes, seguimos leyendo
        body = Data(buffer[bodyStart...].prefix(contentLength))
    }

    private static func parseQuery(_ string: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in string.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = kv.first?.removingPercentEncoding else { continue }
            let value = kv.count > 1 ? (kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "") : ""
            result[key] = value
        }
        return result
    }
}

private extension IPv4Address {
    var isLoopback: Bool { rawValue.first == 127 }
}

private extension IPv6Address {
    var isLoopback: Bool {
        if self == IPv6Address("::1") { return true }
        // IPv4-mapped (::ffff:127.0.0.1)
        if let mapped = asIPv4 { return mapped.isLoopback }
        return false
    }
}
