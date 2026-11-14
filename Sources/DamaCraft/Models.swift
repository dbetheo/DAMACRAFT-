import Foundation

// MARK: - Files
struct ServerFile: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

// MARK: - Players
struct OnlinePlayer: Identifiable, Hashable {
    let name: String
    var id: String { name }
    var joinedAt: Date = Date()
}

// MARK: - JVM / per-server settings
struct ServerSettings: Codable, Equatable, Hashable {
    var minMemoryGB: Double = 1.0
    var maxMemoryGB: Double = 2.0
    var extraJVMArgs: String = ""
    var autoRestartOnCrash: Bool = false
    var maxConsoleLines: Int = 800
    var notifyOnPlayerJoin: Bool = true
    var notifyOnPlayerLeave: Bool = true
    var notifyOnServerStartStop: Bool = true

    var jvmArguments: [String] {
        var args: [String] = [
            "-Xms\(Int(minMemoryGB * 1024))M",
            "-Xmx\(Int(maxMemoryGB * 1024))M"
        ]
        let extra = extraJVMArgs
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        args.append(contentsOf: extra)
        return args
    }
}

// MARK: - Multi-server profile
struct ServerProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    var settings: ServerSettings = ServerSettings()

    var directoryURL: URL { URL(fileURLWithPath: directoryPath) }
}

// MARK: - server.properties
struct PropertyEntry: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var value: String
    var comment: String?
}

enum ServerJarKind: String, CaseIterable {
    case server = "server.jar"
    case paper = "paper.jar"
    case purpur = "purpur.jar"
    case fabric = "fabric-server-launch.jar"
    case forge = "forge.jar"
}

// MARK: - Modrinth plugin search
struct ModrinthSearchResponse: Codable {
    let hits: [ModrinthProject]
    let totalHits: Int?

    enum CodingKeys: String, CodingKey {
        case hits
        case totalHits = "total_hits"
    }
}

struct ModrinthProject: Codable, Identifiable, Hashable {
    var id: String { projectId }
    let projectId: String
    let title: String?
    let description: String?
    let author: String?
    let downloads: Int?
    let iconUrl: String?
    let slug: String?
    let categories: [String]?
    let versions: [String]?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case title, description, author, downloads
        case iconUrl = "icon_url"
        case slug, categories, versions
    }
}

struct ModrinthVersion: Codable, Identifiable {
    let id: String
    let name: String?
    let versionNumber: String?
    let files: [ModrinthFile]?
    let gameVersions: [String]?
    let loaders: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, files
        case versionNumber = "version_number"
        case gameVersions = "game_versions"
        case loaders
    }
}

struct ModrinthFile: Codable {
    let url: String
    let filename: String
    let primary: Bool?
}
