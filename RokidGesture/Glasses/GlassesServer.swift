import Foundation
import Network

/// TCP server on :8104 — sends menu state and gesture events to Rokid glasses.
/// Also receives text commands from glasses (future bidirectional support).
@MainActor
final class GlassesServer: ObservableObject {

    @Published var isRunning   = false
    @Published var clientCount = 0

    /// Called when glasses send a command text
    var onGlassesCommand: ((String) -> Void)?

    private var listener:    NWListener?
    private var connections: [GlassesConn] = []
    private let port: NWEndpoint.Port = 8104
    private let queue = DispatchQueue(label: "GestureGlassesQ", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        guard let l = try? NWListener(using: .tcp, on: port) else { return }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.accept(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in self?.isRunning = (state == .ready) }
        }
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.forEach { $0.conn.cancel() }
        connections.removeAll()
        clientCount = 0; isRunning = false
    }

    // MARK: - Broadcast

    /// Send the current menu state to all glasses.
    func broadcastMenu(_ text: String) {
        send(type: "menu", text: text)
    }

    /// Notify glasses that a gesture was detected and mapped to an action.
    func broadcastGesture(_ emoji: String, gestureName: String, actionName: String) {
        send(type: "gesture", text: "\(emoji) \(gestureName) → \(actionName)")
    }

    /// Acknowledge a menu item selection.
    func broadcastSelect(_ itemTitle: String) {
        send(type: "select", text: "✓ \(itemTitle)")
    }

    /// Generic status line.
    func broadcastStatus(_ msg: String) {
        send(type: "status", text: msg)
    }

    // MARK: - Private

    private func send(type: String, text: String) {
        let dict: [String: String] = ["type": type, "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let packet = data + Data([0x0A])
        connections.forEach { $0.conn.send(content: packet, completion: .contentProcessed { _ in }) }
    }

    private func accept(_ conn: NWConnection) {
        let w = GlassesConn(conn: conn)
        conn.stateUpdateHandler = { [weak self, weak w] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self, weak w] in
                    guard let w else { return }
                    self?.connections.removeAll { $0 === w }
                    self?.clientCount = self?.connections.count ?? 0
                }
            default: break
            }
        }
        conn.start(queue: queue)
        connections.append(w)
        clientCount = connections.count
        send(type: "status", text: "Rokid Gesture HUD — hold up your hand")
        receiveNext(w)
    }

    private func receiveNext(_ w: GlassesConn) {
        w.conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self, weak w] data, _, done, err in
            Task { @MainActor [weak self, weak w] in
                guard let self, let w else { return }
                if let d = data, !d.isEmpty {
                    w.buffer.append(d)
                    self.flush(w)
                }
                if !done && err == nil { self.receiveNext(w) }
            }
        }
    }

    private func flush(_ w: GlassesConn) {
        while let idx = w.buffer.firstIndex(of: 0x0A) {
            let lineData = w.buffer[w.buffer.startIndex..<idx]
            w.buffer.removeSubrange(w.buffer.startIndex...idx)
            guard let raw  = String(data: lineData, encoding: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: String],
                  json["type"] == "cmd",
                  let text = json["text"], !text.isEmpty else { continue }
            onGlassesCommand?(text)
        }
    }
}

private final class GlassesConn {
    let conn: NWConnection
    var buffer = Data()
    init(conn: NWConnection) { self.conn = conn }
}
