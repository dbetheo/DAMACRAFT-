import Foundation
import Network

/// Garantit qu'un callback n'est exécuté qu'une seule fois, quel que soit le thread.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Test d'ouverture d'un port TCP.
enum PortProbe {
    static func check(host: String, port: UInt16, timeout: TimeInterval = 2, completion: @escaping (Bool) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: port) else { completion(false); return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let once = Once()
        let finish: (Bool) -> Void = { ok in
            if once.fire() { conn.cancel(); completion(ok) }
        }
        // .waiting = connexion refusée (NWConnection retente au lieu de passer en .failed).
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .waiting, .cancelled: finish(false)
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
    }
}

/// Server List Ping (protocole de statut Minecraft).
enum ServerPing {
    static func ping(host: String, port: UInt16, completion: @escaping (ServerPingInfo) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: port) else { completion(ServerPingInfo()); return }
        let start = Date()
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let once = Once()
        let buffer = ByteBuffer()

        // Un seul appel au completion, et la connexion est toujours fermée.
        // Si le serveur ne répond pas (arrêté, en démarrage…), on renvoie un état « hors ligne »
        // au lieu de ne rien renvoyer : l'ancien code laissait l'ancien MOTD affiché après l'arrêt.
        let finish: (ServerPingInfo) -> Void = { info in
            if once.fire() { conn.cancel(); completion(info) }
        }

        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data, !data.isEmpty { buffer.append(data) }
                if let payload = buffer.completePacketPayload() {
                    var info = parseStatus(payload)
                    info.latencyMs = Int(Date().timeIntervalSince(start) * 1000)
                    finish(info)
                    return
                }
                if error != nil || isComplete { finish(ServerPingInfo()); return }
                readMore()
            }
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var handshake = Data()
                handshake.append(packVarInt(0))      // id du paquet handshake
                handshake.append(packVarInt(-1))     // version de protocole « inconnue » : accepté pour le statut
                let hostData = Data(host.utf8)
                handshake.append(packVarInt(Int32(hostData.count)))
                handshake.append(hostData)
                handshake.append(UInt8((port >> 8) & 0xff))
                handshake.append(UInt8(port & 0xff))
                handshake.append(packVarInt(1))      // état suivant : status
                var packet = packVarInt(Int32(handshake.count))
                packet.append(handshake)

                var statusPacket = packVarInt(1)
                statusPacket.append(packVarInt(0))   // status request

                conn.send(content: packet + statusPacket, completion: .contentProcessed { error in
                    if error != nil { finish(ServerPingInfo()); return }
                    readMore()
                })
            case .failed, .waiting, .cancelled:
                finish(ServerPingInfo())
            default:
                break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { finish(ServerPingInfo()) }
    }

    private static func parseStatus(_ payload: Data) -> ServerPingInfo {
        var info = ServerPingInfo()
        guard let idx = payload.firstIndex(of: 0x7B),
              let obj = try? JSONSerialization.jsonObject(with: payload.subdata(in: idx..<payload.endIndex)) as? [String: Any]
        else { return info }
        info.online = true
        if let version = obj["version"] as? [String: Any] {
            info.version = version["name"] as? String ?? ""
        }
        if let players = obj["players"] as? [String: Any] {
            info.playersOnline = players["online"] as? Int ?? 0
            info.playersMax = players["max"] as? Int ?? 0
        }
        if let desc = obj["description"] {
            info.motd = flattenText(desc)
        }
        return info
    }

    /// Le MOTD peut être une chaîne ou un composant de texte imbriqué (« extra »).
    private static func flattenText(_ value: Any) -> String {
        if let s = value as? String { return stripFormatting(s) }
        if let d = value as? [String: Any] {
            var out = d["text"] as? String ?? ""
            if let extra = d["extra"] as? [Any] { out += extra.map { flattenText($0) }.joined() }
            return stripFormatting(out)
        }
        if let a = value as? [Any] { return a.map { flattenText($0) }.joined() }
        return ""
    }

    private static func stripFormatting(_ s: String) -> String {
        // Retire les codes couleur « §x ».
        var out = ""
        var skip = false
        for ch in s {
            if skip { skip = false; continue }
            if ch == "§" { skip = true; continue }
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func packVarInt(_ value: Int32) -> Data {
        var val = UInt32(bitPattern: value)
        var data = Data()
        repeat {
            var temp = UInt8(val & 0x7F)
            val >>= 7
            if val != 0 { temp |= 0x80 }
            data.append(temp)
        } while val != 0
        return data
    }
}

/// Tampon d'octets : la réponse de statut (avec l'icône du serveur) dépasse souvent un seul
/// segment TCP, il faut donc accumuler jusqu'au paquet complet.
final class ByteBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ d: Data) {
        lock.lock(); data.append(d); lock.unlock()
    }

    /// Renvoie le contenu du premier paquet (après la longueur) si celui-ci est complet.
    func completePacketPayload() -> Data? {
        lock.lock(); defer { lock.unlock() }
        var length = 0
        var shift = 0
        var index = data.startIndex
        while true {
            guard index < data.endIndex else { return nil }
            let byte = Int(data[index])
            length |= (byte & 0x7F) << shift
            index = data.index(after: index)
            if byte & 0x80 == 0 { break }
            shift += 7
            if shift > 28 { return nil }
        }
        let remaining = data.distance(from: index, to: data.endIndex)
        guard remaining >= length else { return nil }
        return data.subdata(in: index..<data.index(index, offsetBy: length))
    }
}
