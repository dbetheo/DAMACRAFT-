import Foundation
import SwiftUI

struct ServerFile: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

struct OnlinePlayer: Identifiable, Hashable {
    let name: String
    var id: String { name }
    var joinedAt: Date = Date()
}

struct MetricSample: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let ramMB: Double
    let ramPercent: Double
    let tps: Double?
}

struct ServerSettings: Codable, Equatable, Hashable {
    var minMemoryGB: Double = 1.0
    var maxMemoryGB: Double = 2.0
    var extraJVMArgs: String = ""
    var autoRestartOnCrash: Bool = false
    var maxConsoleLines: Int = 1000
    var notifyOnPlayerJoin: Bool = true
    var notifyOnPlayerLeave: Bool = true
    var notifyOnServerStartStop: Bool = true
    var autoBackupEnabled: Bool = false
    var autoBackupIntervalHours: Double = 6
    var maxBackups: Int = 10
    var rconEnabled: Bool = false
    var rconHost: String = "127.0.0.1"
    var rconPort: Int = 25575
    var rconPassword: String = ""
    var discordWebhookURL: String = ""
    var discordNotifyJoinLeave: Bool = false
    var discordNotifyCrash: Bool = true
    /// Chaîne vide = détection automatique du JDK.
    var javaPath: String = ""
    var watchdogEnabled: Bool = false
    var watchdogTimeoutMinutes: Double = 5
    var accentTheme: String = "purple"
    var compactMode: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case minMemoryGB, maxMemoryGB, extraJVMArgs, autoRestartOnCrash, maxConsoleLines
        case notifyOnPlayerJoin, notifyOnPlayerLeave, notifyOnServerStartStop
        case autoBackupEnabled, autoBackupIntervalHours, maxBackups
        case rconEnabled, rconHost, rconPort, rconPassword
        case discordWebhookURL, discordNotifyJoinLeave, discordNotifyCrash
        case javaPath, watchdogEnabled, watchdogTimeoutMinutes, accentTheme, compactMode
    }

    /// Décodage tolérant : un champ absent (ancienne version) reprend sa valeur par défaut
    /// au lieu de faire échouer tout le profil.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ServerSettings()
        minMemoryGB = c.value(.minMemoryGB, d.minMemoryGB)
        maxMemoryGB = c.value(.maxMemoryGB, d.maxMemoryGB)
        extraJVMArgs = c.value(.extraJVMArgs, d.extraJVMArgs)
        autoRestartOnCrash = c.value(.autoRestartOnCrash, d.autoRestartOnCrash)
        maxConsoleLines = c.value(.maxConsoleLines, d.maxConsoleLines)
        notifyOnPlayerJoin = c.value(.notifyOnPlayerJoin, d.notifyOnPlayerJoin)
        notifyOnPlayerLeave = c.value(.notifyOnPlayerLeave, d.notifyOnPlayerLeave)
        notifyOnServerStartStop = c.value(.notifyOnServerStartStop, d.notifyOnServerStartStop)
        autoBackupEnabled = c.value(.autoBackupEnabled, d.autoBackupEnabled)
        autoBackupIntervalHours = c.value(.autoBackupIntervalHours, d.autoBackupIntervalHours)
        maxBackups = c.value(.maxBackups, d.maxBackups)
        rconEnabled = c.value(.rconEnabled, d.rconEnabled)
        rconHost = c.value(.rconHost, d.rconHost)
        rconPort = c.value(.rconPort, d.rconPort)
        rconPassword = c.value(.rconPassword, d.rconPassword)
        discordWebhookURL = c.value(.discordWebhookURL, d.discordWebhookURL)
        discordNotifyJoinLeave = c.value(.discordNotifyJoinLeave, d.discordNotifyJoinLeave)
        discordNotifyCrash = c.value(.discordNotifyCrash, d.discordNotifyCrash)
        let java: String = c.value(.javaPath, d.javaPath)
        // /usr/bin/java n'est qu'un lanceur Apple, pas un JDK : on le traite comme « automatique ».
        javaPath = java == "/usr/bin/java" ? "" : java
        watchdogEnabled = c.value(.watchdogEnabled, d.watchdogEnabled)
        watchdogTimeoutMinutes = c.value(.watchdogTimeoutMinutes, d.watchdogTimeoutMinutes)
        accentTheme = c.value(.accentTheme, d.accentTheme)
        compactMode = c.value(.compactMode, d.compactMode)
    }

    var jvmArguments: [String] {
        let minMB = max(256, Int(minMemoryGB * 1024))
        let maxMB = max(minMB, Int(maxMemoryGB * 1024))
        var args = ["-Xms\(minMB)M", "-Xmx\(maxMB)M"]
        args.append(contentsOf: extraJVMArgs.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty })
        return args
    }
}

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

struct ServerProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    var settings: ServerSettings = ServerSettings()
    var directoryURL: URL { URL(fileURLWithPath: directoryPath) }
}

struct PropertyEntry: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var value: String
    var comment: String?
}

enum ServerJarKind: String, CaseIterable {
    case server = "server.jar"
    case paper = "paper.jar"
    case spigot = "spigot.jar"
    case purpur = "purpur.jar"
    case fabric = "fabric-server-launch.jar"
    case forge = "forge.jar"
}

struct JavaInstall: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let version: String

    var label: String {
        let parts = path.split(separator: "/")
        let folder = parts.first(where: { $0.hasSuffix(".jdk") }).map(String.init) ?? ""
        return folder.isEmpty ? "Java \(version)" : "Java \(version) — \(folder)"
    }
}

struct WorldInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let url: URL
    let sizeMB: Double
}

struct BackupInfo: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let date: Date
    let sizeMB: Double
}

struct CommandPreset: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let command: String
    let icon: String
}

struct ActivityEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let message: String
}

struct CrashReport: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let date: Date
}

struct ServerPingInfo {
    var online = false
    var motd: String = ""
    var version: String = ""
    var playersOnline: Int = 0
    var playersMax: Int = 0
    var latencyMs: Int = 0
}

struct ServerTemplate: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let jarHint: String
    let minGB: Double
    let maxGB: Double
    let properties: [String: String]
}

struct ModrinthSearchResponse: Codable {
    let hits: [ModrinthProject]
    enum CodingKeys: String, CodingKey { case hits }
}

struct ModrinthProject: Codable, Identifiable, Hashable {
    var id: String { projectId }
    let projectId: String
    let title: String?
    let description: String?
    let author: String?
    let downloads: Int?
    let slug: String?
    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case title, description, author, downloads, slug
    }
}

struct ModrinthVersion: Codable, Identifiable {
    let id: String
    let files: [ModrinthFile]?
    let versionNumber: String?
    enum CodingKeys: String, CodingKey {
        case id, files
        case versionNumber = "version_number"
    }
}

struct ModrinthFile: Codable {
    let url: String
    let filename: String
    let primary: Bool?
}

struct JSONListEntry: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var extra: String
}
