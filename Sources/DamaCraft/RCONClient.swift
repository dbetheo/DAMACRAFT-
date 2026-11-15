import Foundation
import Network

/// Minimal Minecraft RCON client (Source RCON protocol).
final class RCONClient: @unchecked Sendable {
    enum RCONError: Error { case notConnected, authFailed, timeout, sendFailed }

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "damacraft.rcon")
    private var requestId: Int32 = 1

    func connect(host: String, port: UInt16, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        connection?.cancel()
        let conn = NWConnection(host: NWEndpoint.Host(host), port: (NWEndpoint.Port(rawValue: port) ?? 25575), using: .tcp)
        self.connection = conn
        let once = Once()
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendPacket(type: 3, body: password) { result in
                    guard once.fire() else { return }
                    switch result {
                    case .failure(let e): completion(.failure(e))
                    case .success(let (id, type, _)):
                        // Réponse d'authentification : type 2 avec l'id de la requête = succès ; id -1 = échec.
                        if type == 2 && id >= 0 {
                            completion(.success(()))
                        } else {
                            completion(.failure(RCONError.authFailed))
                        }
                    }
                }
            case .failed(let e):
                if once.fire() { completion(.failure(e)) }
            case .waiting(let e):
                // Connexion refusée (RCON désactivé ou serveur arrêté) : NWConnection réessaierait indéfiniment.
                if once.fire() { conn.cancel(); completion(.failure(e)) }
            default: break
            }
        }
        conn.start(queue: queue)
    }

    func command(_ cmd: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendPacket(type: 2, body: cmd) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let (_, _, body)): completion(.success(body))
            }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    private func sendPacket(type: Int32, body: String, completion: @escaping (Result<(Int32, Int32, String), Error>) -> Void) {
        guard let connection else { completion(.failure(RCONError.notConnected)); return }
        let id = requestId
        requestId += 1
        var payload = Data()
        func appendInt32(_ v: Int32) {
            var le = v.littleEndian
            payload.append(Data(bytes: &le, count: 4))
        }
        let bodyData = Data(body.utf8) + Data([0, 0])
        let length = Int32(4 + 4 + bodyData.count)
        appendInt32(length)
        appendInt32(id)
        appendInt32(type)
        payload.append(bodyData)

        connection.send(content: payload, completion: .contentProcessed { error in
            if let error { completion(.failure(error)); return }
            connection.receive(minimumIncompleteLength: 12, maximumLength: 65536) { data, _, _, error in
                if let error { completion(.failure(error)); return }
                guard let data, data.count >= 12 else {
                    completion(.failure(RCONError.timeout)); return
                }
                let respId = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
                let respType = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
                let bodyEnd = max(12, data.count - 2)
                let bodyStr = String(data: data.subdata(in: 12..<bodyEnd), encoding: .utf8) ?? ""
                completion(.success((respId, respType, bodyStr)))
            }
        })
    }
}
