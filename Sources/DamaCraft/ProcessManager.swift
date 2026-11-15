import Foundation
import SwiftUI
import AppKit
import UserNotifications
import Network
import UniformTypeIdentifiers

@MainActor
final class ProcessManager: ObservableObject {
    @Published var profiles: [ServerProfile] = []
    @Published var activeProfileID: UUID?
    @Published var statusLabel = "Arrêté"
    @Published var serverStatusMessage = "Ajoute ou sélectionne un serveur."
    @Published var consoleLines: [String] = []
    @Published var commandInput = ""
    @Published var commandHistory: [String] = []
    @Published var historyIndex: Int = -1
    @Published var cpuPercent: Double?
    @Published var memoryMB: Double?
    @Published var memoryPercent: Double?
    @Published var players: [OnlinePlayer] = []
    @Published var maxPlayers = 20
    @Published var reportedTPS: String?
    @Published var isRunning = false
    @Published var files: [ServerFile] = []
    @Published var selectedFile: ServerFile?
    @Published var fileContent = ""
    @Published var properties: [PropertyEntry] = []
    @Published var propertiesDirty = false
    @Published var metricHistory: [MetricSample] = []
    @Published var pluginQuery = ""
    @Published var pluginResults: [ModrinthProject] = []
    @Published var pluginSearching = false
    @Published var pluginStatus = ""
    @Published var downloadingPlugin = false
    @Published var marketplaceMode = "plugin" // plugin | mod
    @Published var javaInstalls: [JavaInstall] = []
    @Published var worlds: [WorldInfo] = []
    @Published var backups: [BackupInfo] = []
    @Published var logLines: [String] = []
    @Published var logFilter = ""
    @Published var portStatus = "—"
    @Published var serverPort = 25565
    @Published var paperStatus = ""
    @Published var paperDownloading = false
    @Published var pluginConfigs: [ServerFile] = []
    @Published var selectedPluginConfig: ServerFile?
    @Published var pluginConfigContent = ""
    @Published var pluginConfigDirty = false
    @Published var eulaAccepted = false
    @Published var activityLog: [ActivityEntry] = []
    @Published var crashReports: [CrashReport] = []
    @Published var healthScore: Int = 100
    @Published var publicIP = "—"
    @Published var pingInfo = ServerPingInfo()
    @Published var rconStatus = "Déconnecté"
    @Published var whitelistEntries: [JSONListEntry] = []
    @Published var opsEntries: [JSONListEntry] = []
    @Published var bannedEntries: [JSONListEntry] = []
    @Published var datapacks: [ServerFile] = []
    @Published var lastConsoleActivity = Date()
    /// Incrémenté à chaque nouvelle ligne : sert à l'auto-scroll même quand le tampon est plein.
    @Published private(set) var consoleRevision = 0

    private var process: Process?
    private var inputPipe: Pipe?
    private var monitorTimer: Timer?
    private var backupTimer: Timer?
    private var watchdogTimer: Timer?
    private var restartWorkItem: DispatchWorkItem?
    private var isRestarting = false
    private let profilesKey = "damacraft.profiles"
    private let activeKey = "damacraft.activeProfile"
    private let maxHistory = 150
    private let rcon = RCONClient()

    static weak var current: ProcessManager?
    @Published var detectedMCVersion: String?
    private var isQuitting = false
    private var quitCompletion: (() -> Void)?
    private var stopRequested = false
    private var crashDates: [Date] = []
    private var lineBuffer = ""
    private var lastResponsive = Date()

    let commandPresets: [CommandPreset] = [
        .init(title: "List", command: "list", icon: "person.2"),
        .init(title: "Save", command: "save-all", icon: "square.and.arrow.down"),
        .init(title: "Day", command: "time set day", icon: "sun.max"),
        .init(title: "Night", command: "time set night", icon: "moon.stars"),
        .init(title: "Clear", command: "weather clear", icon: "cloud.sun"),
        .init(title: "Rain", command: "weather rain", icon: "cloud.rain"),
        .init(title: "Peaceful", command: "difficulty peaceful", icon: "leaf"),
        .init(title: "Hard", command: "difficulty hard", icon: "flame"),
        .init(title: "Say", command: "say Bonjour !", icon: "text.bubble"),
        .init(title: "TPS", command: "tps", icon: "speedometer"),
    ]

    let templates: [ServerTemplate] = [
        .init(name: "Paper Survival", detail: "Survie Paper optimisé", jarHint: "paper.jar", minGB: 1, maxGB: 3,
              properties: ["gamemode": "survival", "difficulty": "normal", "pvp": "true", "max-players": "20"]),
        .init(name: "Créatif", detail: "Créatif, command blocks", jarHint: "paper.jar", minGB: 1, maxGB: 2,
              properties: ["gamemode": "creative", "difficulty": "peaceful", "spawn-monsters": "false", "max-players": "10"]),
        .init(name: "Mini-jeux", detail: "PVP, slots élevés", jarHint: "paper.jar", minGB: 2, maxGB: 4,
              properties: ["gamemode": "adventure", "pvp": "true", "max-players": "40", "view-distance": "8"]),
        .init(name: "Moddé Fabric", detail: "Pour fabric-server-launch.jar", jarHint: "fabric-server-launch.jar", minGB: 2, maxGB: 6,
              properties: ["max-players": "10", "view-distance": "10"]),
    ]

    var activeProfile: ServerProfile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first { $0.id == id }
    }
    var serverDirectory: URL? { activeProfile?.directoryURL }
    var serverName: String { activeProfile?.name ?? "Aucun serveur" }
    var settings: ServerSettings {
        get { activeProfile?.settings ?? ServerSettings() }
        set {
            guard let id = activeProfileID, let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
            profiles[idx].settings = newValue
            saveProfiles()
            scheduleAutoBackup()
            scheduleWatchdog()
        }
    }
    var connectionString: String {
        let ip = publicIP == "—" ? "127.0.0.1" : publicIP
        return "\(ip):\(serverPort)"
    }

    init() {
        ProcessManager.current = self
        loadProfiles()
        requestNotificationPermission()
        detectJavaInstalls()
        fetchPublicIP()
        if let id = activeProfileID { selectProfile(id) }
    }

    func logActivity(_ msg: String) {
        activityLog.insert(ActivityEntry(date: Date(), message: msg), at: 0)
        if activityLog.count > 200 { activityLog.removeLast(activityLog.count - 200) }
    }

    // MARK: Persistence
    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let d = try? JSONDecoder().decode([ServerProfile].self, from: data) { profiles = d }
        if let s = UserDefaults.standard.string(forKey: activeKey), let id = UUID(uuidString: s),
           profiles.contains(where: { $0.id == id }) { activeProfileID = id }
        else { activeProfileID = profiles.first?.id }
    }
    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: profilesKey) }
        if let id = activeProfileID { UserDefaults.standard.set(id.uuidString, forKey: activeKey) }
    }
    func exportProfiles() {
        let p = NSSavePanel(); p.nameFieldStringValue = "damacraft-profiles.json"
        // Les secrets (mot de passe RCON, webhook Discord) ne sont jamais exportés.
        let safe = profiles.map { profile -> ServerProfile in
            var copy = profile
            copy.settings.rconPassword = ""
            copy.settings.discordWebhookURL = ""
            return copy
        }
        guard p.runModal() == .OK, let url = p.url, let data = try? JSONEncoder().encode(safe) else { return }
        do { try data.write(to: url); serverStatusMessage = "Profils exportés (sans mot de passe RCON ni webhook)." }
        catch { serverStatusMessage = "Export impossible : \(error.localizedDescription)" }
    }
    func importProfiles() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let url = p.url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) else {
            serverStatusMessage = "Fichier de profils illisible."
            return
        }
        let existing = Set(profiles.map(\.directoryPath))
        var added = 0
        for var profile in decoded where !existing.contains(profile.directoryPath) {
            profile.id = UUID()
            profiles.append(profile)
            added += 1
        }
        if activeProfileID == nil { activeProfileID = profiles.first?.id }
        saveProfiles()
        serverStatusMessage = "\(added) profil(s) importé(s)."
    }

    // MARK: Multi-server
    func addServer() {
        guard !isRunning else { serverStatusMessage = "Arrête le serveur en cours avant d'en ajouter un autre."; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choisis le dossier d'un serveur Minecraft existant"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let existing = profiles.first(where: { $0.directoryURL.standardizedFileURL.path == url.standardizedFileURL.path }) {
            selectProfile(existing.id)
            serverStatusMessage = "Ce dossier est déjà dans la liste."
            return
        }
        let profile = ServerProfile(name: url.lastPathComponent, directoryPath: url.path)
        profiles.append(profile); activeProfileID = profile.id; saveProfiles()
        resetRuntimeState(); refreshAll()
        scheduleAutoBackup(); scheduleWatchdog()
        logActivity("Serveur ajouté : \(profile.name)")
        serverStatusMessage = "Serveur « \(profile.name) » ajouté."
    }
    func selectProfile(_ id: UUID) {
        if isRunning {
            if id != activeProfileID { serverStatusMessage = "Arrête « \(serverName) » avant de changer de serveur." }
            return
        }
        activeProfileID = id; saveProfiles(); resetRuntimeState(); refreshAll()
        scheduleAutoBackup(); scheduleWatchdog()
        serverStatusMessage = "Serveur : \(serverName)"
    }
    func removeProfile(_ id: UUID) {
        if activeProfileID == id, isRunning {
            serverStatusMessage = "Arrête le serveur avant de le retirer de la liste."
            return
        }
        let name = profiles.first(where: { $0.id == id })?.name ?? "Serveur"
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
            resetRuntimeState()
            if activeProfileID != nil { refreshAll() }
            scheduleAutoBackup(); scheduleWatchdog()
        }
        saveProfiles()
        serverStatusMessage = "« \(name) » retiré de la liste (les fichiers restent sur le disque)."
    }
    func renameActiveProfile(_ name: String) {
        guard let id = activeProfileID, let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name; saveProfiles()
    }
    private func resetRuntimeState() {
        consoleLines = []; players = []; metricHistory = []
        cpuPercent = nil; memoryMB = nil; memoryPercent = nil; reportedTPS = nil
        isRunning = false; statusLabel = "Arrêté"; properties = []; propertiesDirty = false
        selectedFile = nil; fileContent = ""; logLines = []; worlds = []; backups = []
        pluginConfigs = []; portStatus = "—"; healthScore = 100; pingInfo = ServerPingInfo()
        whitelistEntries = []; opsEntries = []; bannedEntries = []; datapacks = []; crashReports = []
        detectedMCVersion = nil; lineBuffer = ""; stopRequested = false
    }
    func refreshAll() {
        refreshFiles(); loadServerProperties(); loadServerPropertiesHints()
        loadEULA(); refreshWorlds(); refreshBackups(); loadLatestLog()
        loadPluginConfigs(); checkPortStatus(); loadCrashReports()
        loadJSONLists(); loadDatapacks(); pingServer()
    }

    // MARK: Templates
    func applyTemplate(_ t: ServerTemplate) {
        var s = settings
        s.minMemoryGB = t.minGB; s.maxMemoryGB = t.maxGB
        settings = s
        for (k, v) in t.properties { updateProperty(key: k, value: v) }
        if propertiesDirty { saveServerProperties() }
        logActivity("Template appliqué : \(t.name)")
        serverStatusMessage = "Template « \(t.name) » appliqué (place \(t.jarHint) dans le dossier)."
    }

    // MARK: Notifications
    private func requestNotificationPermission() {
        // Hors bundle .app (swift run), UNUserNotificationCenter plante : on s'en abstient.
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    func sendDiscord(content: String) {
        let u = settings.discordWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, let url = URL(string: u) else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["content": content])
        URLSession.shared.dataTask(with: req).resume()
    }

    func fetchPublicIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            Task { @MainActor in
                if let data, let s = String(data: data, encoding: .utf8) { self?.publicIP = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }.resume()
    }

    func copyConnectionString() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(connectionString, forType: .string)
        serverStatusMessage = "Copié : \(connectionString)"
    }

    // MARK: Ping
    func pingServer() {
        ServerPing.ping(host: "127.0.0.1", port: UInt16(clamping: serverPort)) { [weak self] info in
            Task { @MainActor in
                guard let self else { return }
                self.pingInfo = info
                if info.online {
                    self.lastResponsive = Date()
                    if self.detectedMCVersion == nil { self.detectedMCVersion = Self.extractMCVersion(from: info.version) }
                }
            }
        }
    }

    // MARK: RCON
    func rconConnect() {
        rconStatus = "Connexion…"
        rcon.connect(host: settings.rconHost, port: UInt16(clamping: settings.rconPort), password: settings.rconPassword) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success: self?.rconStatus = "Connecté ✓"
                case .failure(let e): self?.rconStatus = "Erreur : \(e.localizedDescription)"
                }
            }
        }
    }
    func rconCommand(_ cmd: String) {
        rcon.command(cmd) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let body): self?.append("[RCON] \(body)")
                case .failure(let e): self?.append("[RCON] \(e.localizedDescription)")
                }
            }
        }
    }

    // MARK: Java
    func detectJavaInstalls() {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var homes: [String] = []

        // JDK installés via .pkg / Temurin / Oracle / Zulu…
        for root in ["/Library/Java/JavaVirtualMachines", home + "/Library/Java/JavaVirtualMachines"] {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".jdk") {
                homes.append("\(root)/\(name)/Contents/Home")
            }
        }
        // Homebrew (openjdk, openjdk@17, openjdk@21…)
        for root in ["/opt/homebrew/opt", "/usr/local/opt"] {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasPrefix("openjdk") {
                homes.append("\(root)/\(name)/libexec/openjdk.jdk/Contents/Home")
                homes.append("\(root)/\(name)")
            }
        }
        // SDKMAN
        let sdkman = home + "/.sdkman/candidates/java"
        for name in (try? fm.contentsOfDirectory(atPath: sdkman)) ?? [] where name != "current" {
            homes.append("\(sdkman)/\(name)")
        }

        var results: [JavaInstall] = []
        for h in homes {
            let path = h + "/bin/java"
            guard fm.isExecutableFile(atPath: path), !results.contains(where: { $0.path == path }) else { continue }
            let version = javaVersion(atHome: h) ?? URL(fileURLWithPath: h).lastPathComponent
            results.append(JavaInstall(path: path, version: version))
        }
        // Liens Homebrew dans le PATH. /usr/bin/java est volontairement ignoré :
        // c'est un simple lanceur Apple qui existe même sans JDK.
        for candidate in ["/opt/homebrew/bin/java", "/usr/local/bin/java"] {
            if fm.isExecutableFile(atPath: candidate), !results.contains(where: { $0.path == candidate }) {
                results.append(JavaInstall(path: candidate, version: "PATH"))
            }
        }
        // Le plus récent d'abord : c'est celui qu'on utilise en mode automatique.
        javaInstalls = results.sorted { Self.javaMajor($0.version) > Self.javaMajor($1.version) }
    }

    private func javaVersion(atHome home: String) -> String? {
        guard let release = try? String(contentsOfFile: home + "/release", encoding: .utf8) else { return nil }
        for line in release.split(whereSeparator: \.isNewline) where line.hasPrefix("JAVA_VERSION=") {
            return line.dropFirst("JAVA_VERSION=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    static func javaMajor(_ version: String) -> Int {
        let parts = version.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
        guard let first = parts.first, let n = Int(first) else { return 0 }
        if n == 1, parts.count > 1, let second = Int(parts[1]) { return second } // 1.8.0 -> 8
        return n
    }

    static func extractMCVersion(from text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"\d+\.\d+(?:\.\d+)*"#) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }

    // MARK: Files / EULA / properties
    func refreshFiles() {
        guard let dir = serverDirectory else { files = []; return }
        let c = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        files = c.map { ServerFile(url: $0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func loadFileContent(_ file: ServerFile) {
        selectedFile = file
        guard !file.isDirectory else { fileContent = "(Dossier)"; return }
        let size = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 1_000_000 {
            // Gros fichier (latest.log, etc.) : on n'affiche que la fin pour ne pas figer l'app.
            if let handle = try? FileHandle(forReadingFrom: file.url) {
                defer { try? handle.close() }
                try? handle.seek(toOffset: UInt64(size - 200_000))
                let tail = (try? handle.readToEnd()) ?? Data()
                fileContent = "… fichier volumineux : seule la fin est affichée …\n" + String(decoding: tail, as: UTF8.self)
                return
            }
        }
        fileContent = (try? String(contentsOf: file.url, encoding: .utf8)) ?? "(Fichier binaire ou illisible)"
    }
    func loadEULA() {
        guard let dir = serverDirectory else { eulaAccepted = false; return }
        if let c = try? String(contentsOf: dir.appendingPathComponent("eula.txt"), encoding: .utf8) {
            eulaAccepted = c.lowercased().contains("eula=true")
        } else { eulaAccepted = false }
    }
    func acceptEULA() {
        guard let dir = serverDirectory else { return }
        try? "# DamaCraft\neula=true\n".write(to: dir.appendingPathComponent("eula.txt"), atomically: true, encoding: .utf8)
        eulaAccepted = true; logActivity("EULA accepté"); serverStatusMessage = "EULA accepté."
    }
    func loadServerProperties() {
        properties = []; propertiesDirty = false
        guard let dir = serverDirectory, let content = try? String(contentsOf: dir.appendingPathComponent("server.properties"), encoding: .utf8) else { return }
        var entries: [PropertyEntry] = []; var pending: String?
        for raw in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw); let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("#") { pending = String(t.dropFirst()).trimmingCharacters(in: .whitespaces); continue }
            if let eq = line.firstIndex(of: "=") {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                // Les valeurs vides (level-seed=, motd=…) sont conservées.
                if !key.isEmpty { entries.append(PropertyEntry(key: key, value: value, comment: pending)) }
                pending = nil
            }
        }
        properties = entries
    }
    func updateProperty(key: String, value: String) {
        if let i = properties.firstIndex(where: { $0.key == key }) { properties[i].value = value; propertiesDirty = true }
        else { properties.append(PropertyEntry(key: key, value: value, comment: nil)); propertiesDirty = true }
    }
    func saveServerProperties() {
        guard let dir = serverDirectory else { return }
        var lines = ["# DamaCraft", "# \(Date())"]
        for e in properties {
            if let c = e.comment, !c.isEmpty { lines.append("# \(c)") }
            lines.append("\(e.key)=\(e.value)")
        }
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("server.properties"), atomically: true, encoding: .utf8)
        } catch {
            serverStatusMessage = "Impossible d'enregistrer server.properties : \(error.localizedDescription)"
            return
        }
        propertiesDirty = false; loadServerPropertiesHints(); logActivity("server.properties sauvé")
        serverStatusMessage = serverIsRunningNote("server.properties enregistré.")
    }
    private func loadServerPropertiesHints() {
        if let m = properties.first(where: { $0.key == "max-players" })?.value, let v = Int(m) { maxPlayers = v }
        if let p = properties.first(where: { $0.key == "server-port" })?.value, let v = Int(p), (1...65535).contains(v) { serverPort = v }
        if let rp = properties.first(where: { $0.key == "rcon.port" })?.value, let v = Int(rp),
           (1...65535).contains(v), settings.rconPort != v {
            var s = settings; s.rconPort = v; settings = s
        }
    }
    private func serverIsRunningNote(_ base: String) -> String {
        isRunning ? base + " Redémarre le serveur pour appliquer les changements." : base
    }
    var levelName: String {
        let v = properties.first(where: { $0.key == "level-name" })?.value.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? "world" : v
    }

    // JSON lists
    func loadJSONLists() {
        whitelistEntries = loadNameList("whitelist.json")
        opsEntries = loadNameList("ops.json")
        bannedEntries = loadNameList("banned-players.json")
    }
    private func loadNameList(_ file: String) -> [JSONListEntry] {
        guard let dir = serverDirectory,
              let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let extra = dict["uuid"] as? String ?? dict["reason"] as? String ?? ""
            return JSONListEntry(name: name, extra: extra)
        }
    }

    // Datapacks
    func loadDatapacks() {
        datapacks = []
        guard let dir = serverDirectory else { return }
        let dp = dir.appendingPathComponent("world/datapacks")
        let c = (try? FileManager.default.contentsOfDirectory(at: dp, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        datapacks = c.map { ServerFile(url: $0) }
    }

    // Plugin configs
    func loadPluginConfigs() {
        pluginConfigs = []
        guard let dir = serverDirectory else { return }
        let plugins = dir.appendingPathComponent("plugins")
        guard let en = FileManager.default.enumerator(at: plugins, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        var found: [ServerFile] = []
        for case let url as URL in en where url.pathExtension == "yml" || url.pathExtension == "yaml" {
            found.append(ServerFile(url: url))
        }
        pluginConfigs = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func loadPluginConfig(_ f: ServerFile) {
        selectedPluginConfig = f; pluginConfigDirty = false
        pluginConfigContent = (try? String(contentsOf: f.url, encoding: .utf8)) ?? ""
    }
    func savePluginConfig() {
        guard let f = selectedPluginConfig else { return }
        try? pluginConfigContent.write(to: f.url, atomically: true, encoding: .utf8)
        pluginConfigDirty = false; logActivity("Config plugin : \(f.name)")
    }

    // Worlds / backups / crashes
    func refreshWorlds() {
        guard let dir = serverDirectory else { worlds = []; return }
        let level = levelName
        let names = [level, level + "_nether", level + "_the_end"]
        Task { [weak self] in
            let list: [WorldInfo] = await Task.detached(priority: .utility) { () -> [WorldInfo] in
                var out: [WorldInfo] = []
                for name in names {
                    let url = dir.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: url.path) {
                        out.append(WorldInfo(name: name, url: url, sizeMB: dirSizeMB(url)))
                    }
                }
                return out
            }.value
            self?.worlds = list
        }
    }
    func refreshBackups() {
        guard let dir = serverDirectory else { backups = []; return }
        let bd = dir.appendingPathComponent("backups")
        Task { [weak self] in
            let list: [BackupInfo] = await Task.detached(priority: .utility) { () -> [BackupInfo] in
                let items = (try? FileManager.default.contentsOfDirectory(at: bd, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
                return items.map { url -> BackupInfo in
                    let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return BackupInfo(url: url, name: url.lastPathComponent, date: d, sizeMB: dirSizeMB(url))
                }.sorted { $0.date > $1.date }
            }.value
            self?.backups = list
        }
    }
    func loadCrashReports() {
        crashReports = []
        guard let dir = serverDirectory else { return }
        let cd = dir.appendingPathComponent("crash-reports")
        let c = (try? FileManager.default.contentsOfDirectory(at: cd, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        crashReports = c.map { url in
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return CrashReport(url: url, name: url.lastPathComponent, date: d)
        }.sorted { $0.date > $1.date }
    }

    /// Nom du monde d'après le nom d'un dossier de sauvegarde « <monde>_yyyy-MM-dd_HH-mm-ss ».
    /// (L'ancien code coupait au premier « _ » : une sauvegarde de world_nether restaurait « world ».)
    static func worldName(fromBackup name: String) -> String {
        let suffixLength = 20 // "_" + 19 caractères de date
        if name.count > suffixLength {
            let cut = name.index(name.endIndex, offsetBy: -suffixLength)
            if name[cut] == "_" { return String(name[..<cut]) }
        }
        return name.split(separator: "_").first.map(String.init) ?? "world"
    }

    func createBackup(worldName requested: String? = nil) {
        guard let dir = serverDirectory else { return }
        let worldName = requested ?? levelName
        let world = dir.appendingPathComponent(worldName)
        guard FileManager.default.fileExists(atPath: world.path) else {
            serverStatusMessage = "Monde « \(worldName) » introuvable."
            return
        }
        let bd = dir.appendingPathComponent("backups")
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dest = bd.appendingPathComponent("\(worldName)_\(fmt.string(from: Date()))")
        let wasRunning = isRunning
        let keep = max(0, settings.maxBackups)
        serverStatusMessage = "Sauvegarde de \(worldName) en cours…"
        // On fige les écritures pendant la copie pour obtenir un monde cohérent.
        if wasRunning { sendCommand("save-off"); sendCommand("save-all flush") }
        Task { [weak self] in
            if wasRunning { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            let failure: String? = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try FileManager.default.createDirectory(at: bd, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: world, to: dest)
                    return nil
                } catch { return error.localizedDescription }
            }.value
            guard let self else { return }
            if wasRunning && self.isRunning { self.sendCommand("save-on") }
            if let failure {
                self.serverStatusMessage = "Échec de la sauvegarde : \(failure)"
                return
            }
            if keep > 0 { self.pruneBackups(keeping: keep, world: worldName) }
            self.serverStatusMessage = "Sauvegarde créée : \(dest.lastPathComponent)"
            self.logActivity("Backup \(dest.lastPathComponent)")
            self.notify(title: "Sauvegarde", body: dest.lastPathComponent)
            self.refreshBackups()
        }
    }

    private func pruneBackups(keeping keep: Int, world: String) {
        guard let dir = serverDirectory else { return }
        let bd = dir.appendingPathComponent("backups")
        let urls = (try? FileManager.default.contentsOfDirectory(at: bd, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let mine = urls
            .filter { Self.worldName(fromBackup: $0.lastPathComponent) == world }
            .map { url -> (URL, Date) in
                (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast)
            }
            .sorted { $0.1 > $1.1 }
        guard mine.count > keep else { return }
        for item in mine.dropFirst(keep) { try? FileManager.default.removeItem(at: item.0) }
    }

    func deleteBackup(_ b: BackupInfo) {
        do {
            try FileManager.default.removeItem(at: b.url)
            logActivity("Backup supprimé \(b.name)")
            serverStatusMessage = "Sauvegarde supprimée."
        } catch { serverStatusMessage = "Suppression impossible : \(error.localizedDescription)" }
        refreshBackups()
    }

    func restoreBackup(_ b: BackupInfo) {
        guard let dir = serverDirectory else { return }
        if isRunning { serverStatusMessage = "Arrête le serveur d'abord."; return }
        let worldName = Self.worldName(fromBackup: b.name)
        let dest = dir.appendingPathComponent(worldName)
        let stash = dir.appendingPathComponent("\(worldName).avant-restauration")
        let src = b.url
        serverStatusMessage = "Restauration de \(b.name)…"
        Task { [weak self] in
            let failure: String? = await Task.detached(priority: .userInitiated) { () -> String? in
                let fm = FileManager.default
                do {
                    if fm.fileExists(atPath: stash.path) { try fm.removeItem(at: stash) }
                    if fm.fileExists(atPath: dest.path) { try fm.moveItem(at: dest, to: stash) }
                    do {
                        try fm.copyItem(at: src, to: dest)
                    } catch {
                        // Échec : on remet l'ancien monde en place.
                        if fm.fileExists(atPath: stash.path) {
                            try? fm.removeItem(at: dest)
                            try? fm.moveItem(at: stash, to: dest)
                        }
                        throw error
                    }
                    return nil
                } catch { return error.localizedDescription }
            }.value
            guard let self else { return }
            if let failure { self.serverStatusMessage = "Échec de la restauration : \(failure)"; return }
            self.serverStatusMessage = "Restauré : \(b.name). L'ancien monde est conservé dans « \(stash.lastPathComponent) »."
            self.logActivity("Restore \(b.name)")
            self.refreshWorlds()
        }
    }
    private func scheduleAutoBackup() {
        backupTimer?.invalidate(); backupTimer = nil
        guard settings.autoBackupEnabled else { return }
        let interval = max(1, settings.autoBackupIntervalHours) * 3600
        backupTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.createBackup() }
        }
    }

    // Watchdog : redémarre le serveur s'il ne répond plus au ping de statut Minecraft.
    // (L'ancienne version se basait sur le silence de la console, ce qui redémarrait
    // à tort un serveur simplement calme.)
    private func scheduleWatchdog() {
        watchdogTimer?.invalidate(); watchdogTimer = nil
        guard settings.watchdogEnabled else { return }
        lastResponsive = Date()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkWatchdog() }
        }
    }
    private func checkWatchdog() {
        guard isRunning, settings.watchdogEnabled, statusLabel == "En ligne" else { return }
        if properties.first(where: { $0.key == "enable-status" })?.value == "false" { return }
        let timeout = max(1, settings.watchdogTimeoutMinutes) * 60
        ServerPing.ping(host: "127.0.0.1", port: UInt16(clamping: serverPort)) { [weak self] info in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.pingInfo = info
                if info.online { self.lastResponsive = Date(); return }
                if Date().timeIntervalSince(self.lastResponsive) > timeout {
                    self.lastResponsive = Date()
                    self.logActivity("Watchdog : le serveur ne répond plus, redémarrage")
                    self.sendDiscord(content: "🐕 Watchdog : redémarrage de **\(self.serverName)** (plus de réponse)")
                    self.restartServer()
                }
            }
        }
    }

    // Logs
    func loadLatestLog() {
        logLines = []
        guard let dir = serverDirectory,
              let c = try? String(contentsOf: dir.appendingPathComponent("logs/latest.log"), encoding: .utf8) else { return }
        logLines = c.split(whereSeparator: \.isNewline).map(String.init)
        if detectedMCVersion == nil,
           let line = logLines.first(where: { $0.contains("Starting minecraft server version") }) {
            detectedMCVersion = Self.extractMCVersion(from: line.components(separatedBy: "server version").last ?? line)
        }
    }
    func archiveLogs() {
        guard let dir = serverDirectory else { return }
        let logs = dir.appendingPathComponent("logs")
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd_HH-mm"
        let dest = logs.appendingPathComponent("archive_\(fmt.string(from: Date()))")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        if let c = try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil) {
            for u in c where u.pathExtension == "log" || u.pathExtension == "gz" {
                if u.lastPathComponent == "latest.log" { continue }
                try? FileManager.default.moveItem(at: u, to: dest.appendingPathComponent(u.lastPathComponent))
            }
        }
        serverStatusMessage = "Logs archivés."; logActivity("Logs archivés")
    }

    // Port
    func checkPortStatus() {
        portStatus = "…"
        PortProbe.check(host: "127.0.0.1", port: UInt16(clamping: serverPort)) { [weak self] open in
            Task { @MainActor in
                guard let self else { return }
                self.portStatus = open ? "Ouvert ✓" : (self.isRunning ? "Fermé" : "Arrêté")
            }
        }
    }

    // Plugin snapshot
    func snapshotPlugins() {
        guard let dir = serverDirectory else { return }
        let plugins = dir.appendingPathComponent("plugins")
        let c = (try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)) ?? []
        let jars = c.filter { $0.pathExtension == "jar" }.map(\.lastPathComponent).sorted()
        let text = jars.joined(separator: "\n")
        let dest = dir.appendingPathComponent("plugins-snapshot.txt")
        try? text.write(to: dest, atomically: true, encoding: .utf8)
        serverStatusMessage = "Snapshot \(jars.count) plugins."; logActivity("Snapshot plugins")
    }

    // Start/stop
    func startServer() {
        guard !isRunning else {
            serverStatusMessage = "Le serveur est déjà démarré."
            return
        }
        guard let directory = serverDirectory else {
            serverStatusMessage = "Aucun serveur sélectionné. Crée ou ajoute un serveur."
            return
        }
        guard eulaAccepted else {
            serverStatusMessage = "EULA non acceptée. Accepte-la dans Paramètres avant de démarrer."
            return
        }

        let jarName = ServerJarKind.allCases.map(\.rawValue).first {
            let jarURL = directory.appendingPathComponent($0)
            guard FileManager.default.fileExists(atPath: jarURL.path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: jarURL.path),
                  let size = (attributes[.size] as? NSNumber)?.intValue else { return false }
            return size > 0
        }
        guard let jarName else {
            serverStatusMessage = "Aucun fichier serveur .jar valide trouvé dans \(directory.path)."
            append("ERREUR : aucun JAR serveur détecté.")
            return
        }

        guard let javaURL = resolvedJavaExecutable() else {
            serverStatusMessage = "Java introuvable. Installe un JDK récent (Java 21 ou plus pour les versions actuelles, Java 8 pour Minecraft 1.8.8), puis relance la détection dans Paramètres."
            append("ERREUR : aucun Java détecté. Vérifie Paramètres > Java.")
            return
        }

        let task = Process()
        let output = Pipe()
        let input = Pipe()
        var args = settings.jvmArguments
        args.append(contentsOf: ["-jar", jarName, "nogui"])
        task.executableURL = javaURL
        task.arguments = args
        task.currentDirectoryURL = directory
        task.standardOutput = output
        task.standardError = output
        task.standardInput = input

        stopRequested = false
        lineBuffer = ""

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            // Décodage tolérant : un caractère coupé entre deux lectures ne fait plus perdre tout le bloc.
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.ingest(text) }
        }

        task.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            output.fileHandleForReading.readabilityHandler = nil
            let rest = try? output.fileHandleForReading.readToEnd()
            try? output.fileHandleForReading.close()
            let remaining = rest.map { String(decoding: $0, as: UTF8.self) } ?? ""
            Task { @MainActor in self?.handleTermination(status: status, remaining: remaining) }
        }

        do {
            try task.run()
            process = task
            inputPipe = input
            isRunning = true
            statusLabel = "Démarrage…"
            lastConsoleActivity = Date()
            lastResponsive = Date()
            serverStatusMessage = "Processus Java lancé (\(jarName)). En attente du serveur…"
            append(">>> \(javaURL.path) \(args.joined(separator: " "))")
            startMonitoring()
            logActivity("Démarrage \(jarName)")
            if settings.notifyOnServerStartStop { notify(title: "Démarrage", body: serverName) }
            sendDiscord(content: "🟢 **\(serverName)** démarre")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.checkPortStatus()
                    self.pingServer()
                    if self.isRunning && self.serverStatusMessage.hasPrefix("Processus Java lancé") {
                        self.serverStatusMessage = "Java est lancé. Vérifie la console pour confirmer « Done »."
                    }
                }
            }
        } catch {
            isRunning = false
            statusLabel = "Erreur"
            serverStatusMessage = "Impossible de lancer Java : \(error.localizedDescription)"
            append("ERREUR lancement Java : \(error.localizedDescription)")
        }
    }

    private func handleTermination(status: Int32, remaining: String) {
        if !remaining.isEmpty { ingest(remaining) }
        if !lineBuffer.isEmpty { appendLines([lineBuffer]); lineBuffer = "" }
        stopMonitoring()
        restartWorkItem?.cancel(); restartWorkItem = nil
        process = nil
        inputPipe = nil
        isRunning = false
        statusLabel = "Arrêté"
        cpuPercent = nil; memoryMB = nil; memoryPercent = nil
        players = []; reportedTPS = nil
        pingInfo = ServerPingInfo()
        portStatus = "Arrêté"
        updateHealth()
        append("Processus Java terminé (code \(status)).")

        let requested = stopRequested
        let crashed = status != 0 && !requested
        if settings.notifyOnServerStartStop {
            notify(title: crashed ? "Serveur planté" : "Serveur arrêté", body: serverName)
        }
        if crashed && settings.discordNotifyCrash {
            sendDiscord(content: "⚠️ Crash **\(serverName)** (code \(status))")
        }
        logActivity("Serveur arrêté (\(status))")
        loadCrashReports()

        if isQuitting { finishQuit(); return }

        if isRestarting {
            isRestarting = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                Task { @MainActor in self?.startServer() }
            }
            return
        }
        if crashed && settings.autoRestartOnCrash {
            // Garde-fou : pas de boucle infinie si le serveur plante au démarrage.
            let now = Date()
            crashDates = crashDates.filter { now.timeIntervalSince($0) < 300 } + [now]
            if crashDates.count >= 4 {
                serverStatusMessage = "Plantages répétés : le redémarrage automatique est suspendu. Consulte la console."
                logActivity("Auto-restart suspendu (4 plantages en 5 min)")
                return
            }
            serverStatusMessage = "Plantage (code \(status)). Redémarrage automatique dans 3 s…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                Task { @MainActor in self?.startServer() }
            }
            return
        }
        serverStatusMessage = (status == 0 || requested)
            ? "Serveur arrêté."
            : "Le serveur s'est arrêté avec le code \(status). Consulte la console."
    }

    func resolvedJavaExecutable() -> URL? {
        let configured = settings.javaPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty && configured != "/usr/bin/java" &&
            FileManager.default.isExecutableFile(atPath: configured) {
            return URL(fileURLWithPath: configured)
        }
        if let installed = javaInstalls.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return URL(fileURLWithPath: installed.path)
        }
        for candidate in ["/opt/homebrew/bin/java", "/usr/local/bin/java"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    func stopGracefully() {
        guard isRunning else { return }
        isRestarting = false
        stopRequested = true
        sendCommand("stop")
        serverStatusMessage = "Arrêt en cours…"
        statusLabel = "Arrêt…"
        scheduleForceKill(after: 20)
    }
    private func scheduleForceKill(after seconds: Double) {
        restartWorkItem?.cancel()
        let w = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.forceKill()
            }
        }
        restartWorkItem = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }
    func forceKill() {
        guard isRunning, let process, process.isRunning else { return }
        stopRequested = true
        isRestarting = false
        let pid = process.processIdentifier
        process.terminate()
        append(">>> Force kill"); logActivity("Force kill")
        // Si la JVM ignore SIGTERM, on passe à SIGKILL.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { @MainActor in
                if let p = self?.process, p.isRunning, p.processIdentifier == pid { kill(pid, SIGKILL) }
            }
        }
    }
    func restartServer() {
        guard isRunning else { startServer(); return }
        isRestarting = true
        stopRequested = true
        sendCommand("stop"); logActivity("Restart demandé")
        serverStatusMessage = "Redémarrage…"
        scheduleForceKill(after: 20)
    }

    /// Appelé par l'AppDelegate : arrête proprement le serveur avant de quitter l'app,
    /// pour ne pas laisser une JVM orpheline tourner en arrière-plan.
    func stopForQuit(completion: @escaping () -> Void) {
        guard isRunning else { completion(); return }
        isQuitting = true
        quitCompletion = completion
        isRestarting = false
        stopRequested = true
        sendCommand("stop")
        serverStatusMessage = "Arrêt du serveur avant fermeture…"
        scheduleForceKill(after: 20)
        // Filet de sécurité : la fermeture de l'app ne doit jamais rester bloquée.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            Task { @MainActor in self?.finishQuit() }
        }
    }
    private func finishQuit() {
        let c = quitCompletion
        quitCompletion = nil
        c?()
    }

    // Console
    func sendCommand() {
        let v = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        if commandHistory.last != v { commandHistory.append(v) }
        historyIndex = -1; commandInput = ""; sendCommand(v)
    }
    func historyUp() {
        guard !commandHistory.isEmpty else { return }
        if historyIndex == -1 { historyIndex = commandHistory.count - 1 }
        else { historyIndex = max(0, historyIndex - 1) }
        commandInput = commandHistory[historyIndex]
    }
    func historyDown() {
        guard historyIndex >= 0 else { return }
        historyIndex += 1
        if historyIndex >= commandHistory.count { historyIndex = -1; commandInput = "" }
        else { commandInput = commandHistory[historyIndex] }
    }
    func sendCommand(_ command: String) {
        let clean = command.hasPrefix("/") ? String(command.dropFirst()) : command
        guard let inputPipe, isRunning, let data = (clean + "\n").data(using: .utf8) else {
            if settings.rconEnabled { rconCommand(clean) }
            else { serverStatusMessage = "Le serveur n'est pas démarré." }
            return
        }
        do {
            // write(contentsOf:) lève une erreur Swift (l'ancien write(_:) levait une exception ObjC
            // et faisait planter l'app si le tube était déjà fermé).
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
            append("> \(clean)"); logActivity("CMD \(clean)")
        } catch {
            append("ERREUR : commande non envoyée (\(error.localizedDescription))")
        }
    }
    func kickPlayer(_ n: String) { sendCommand("kick \(n)") }
    func banPlayer(_ n: String) { sendCommand("ban \(n)"); players.removeAll { $0.name == n } }
    func opPlayer(_ n: String) { sendCommand("op \(n)") }
    func gamemode(_ m: String, player: String) { sendCommand("gamemode \(m) \(player)") }
    func whitelistAdd(_ n: String) { sendCommand("whitelist add \(n)") }
    func whitelistRemove(_ n: String) { sendCommand("whitelist remove \(n)") }

    private static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        return s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }
    /// Reconstitue des lignes complètes à partir des blocs lus sur le tube du serveur.
    private func ingest(_ raw: String) {
        lineBuffer += Self.stripANSI(raw)
        var parts = lineBuffer.components(separatedBy: "\n")
        lineBuffer = parts.removeLast()
        let lines = parts
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        appendLines(lines)
        parseConsole(lines)
    }
    private func appendLines(_ lines: [String]) {
        lastConsoleActivity = Date()
        consoleLines.append(contentsOf: lines)
        let limit = max(100, settings.maxConsoleLines)
        if consoleLines.count > limit { consoleLines.removeFirst(consoleLines.count - limit) }
        consoleRevision &+= 1
    }
    func clearConsole() {
        consoleLines.removeAll()
        consoleRevision &+= 1
    }
    private func append(_ text: String) {
        appendLines(text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty })
    }
    private func parseConsole(_ lines: [String]) {
        for line in lines {
            if let name = extractPlayer(from: line, patterns: [" joined the game"]) {
                if !players.contains(where: { $0.name == name }) {
                    players.append(OnlinePlayer(name: name))
                    if settings.notifyOnPlayerJoin { notify(title: "Connexion", body: name) }
                    if settings.discordNotifyJoinLeave { sendDiscord(content: "👤 **\(name)** a rejoint **\(serverName)**") }
                    logActivity("Join \(name)")
                }
            }
            if let name = extractPlayer(from: line, patterns: [" left the game"]) {
                players.removeAll { $0.name == name }
                if settings.notifyOnPlayerLeave { notify(title: "Déconnexion", body: name) }
                if settings.discordNotifyJoinLeave { sendDiscord(content: "🚪 **\(name)** a quitté le serveur") }
                logActivity("Leave \(name)")
            }
            if line.contains("of a max of"), line.contains("players online"),
               let max = extractInt(after: "max of", in: line) { maxPlayers = max }
            let lower = line.lowercased()
            // « tps » seul matchait aussi « https://… » et faussait la valeur affichée.
            if lower.contains("tps from") || lower.contains("tps:"), let tps = extractTPS(from: line) { reportedTPS = tps }
            if detectedMCVersion == nil, line.contains("Starting minecraft server version") {
                detectedMCVersion = Self.extractMCVersion(from: line.components(separatedBy: "server version").last ?? line)
            }
            if line.contains("Done ("), line.contains("For help") {
                statusLabel = "En ligne"
                serverStatusMessage = "Serveur prêt et en écoute."
                lastResponsive = Date()
                checkPortStatus(); pingServer()
            }
        }
        updateHealth()
    }
    private func extractPlayer(from line: String, patterns: [String]) -> String? {
        for p in patterns {
            if let r = line.range(of: p) {
                let before = String(line[..<r.lowerBound])
                if let last = before.split(whereSeparator: \.isWhitespace).last {
                    let n = String(last).trimmingCharacters(in: CharacterSet(charactersIn: "<>[]:"))
                    if !n.isEmpty && n.count < 32 && !n.contains("/") { return n }
                }
            }
        }
        return nil
    }
    private func extractInt(after m: String, in line: String) -> Int? {
        guard let r = line.range(of: m) else { return nil }
        return Int(line[r.upperBound...].drop(while: { $0 == " " }).prefix(while: { $0.isNumber }))
    }
    private func extractTPS(from line: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"(\d+\.\d+)"#) else { return nil }
        let ns = line as NSString
        let m = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
        return m.first.map { ns.substring(with: $0.range) }
    }

    private func updateHealth() {
        var score = 100
        if let cpu = cpuPercent, cpu > 90 { score -= 20 } else if let cpu = cpuPercent, cpu > 70 { score -= 10 }
        if let ram = memoryPercent, ram > 90 { score -= 25 } else if let ram = memoryPercent, ram > 75 { score -= 10 }
        if let tps = reportedTPS.flatMap(Double.init), tps < 15 { score -= 30 } else if let tps = reportedTPS.flatMap(Double.init), tps < 18 { score -= 15 }
        if !isRunning { score = 0 }
        healthScore = max(0, score)
    }

    private func startMonitoring() {
        stopMonitoring()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateResourceUsage() }
        }
        updateResourceUsage()
    }
    private func stopMonitoring() { monitorTimer?.invalidate(); monitorTimer = nil }
    private func updateResourceUsage() {
        guard let process, process.isRunning else { cpuPercent = nil; memoryMB = nil; memoryPercent = nil; return }
        let pid = process.processIdentifier
        let maxMB = settings.maxMemoryGB * 1024
        Task { [weak self] in
            // `ps` est lancé hors du thread principal pour ne pas bloquer l'interface.
            let usage = await Task.detached(priority: .utility) { readProcessUsage(pid: pid) }.value
            guard let self, self.isRunning, let usage else { return }
            self.cpuPercent = usage.cpu
            self.memoryMB = usage.mb
            let pct = maxMB > 0 ? min(100, usage.mb / maxMB * 100) : 0
            self.memoryPercent = pct
            self.metricHistory.append(MetricSample(date: Date(), cpu: usage.cpu, ramMB: usage.mb, ramPercent: pct, tps: self.reportedTPS.flatMap(Double.init)))
            if self.metricHistory.count > self.maxHistory { self.metricHistory.removeFirst(self.metricHistory.count - self.maxHistory) }
            self.updateHealth()
        }
    }

    // MARK: Marketplace (Modrinth)
    private static func jsonArrayString(_ items: [String]) -> String {
        "[" + items.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
    private func modrinthLoaders() -> [String] {
        if marketplaceMode == "mod" {
            if let dir = serverDirectory {
                let fm = FileManager.default
                if fm.fileExists(atPath: dir.appendingPathComponent("fabric-server-launch.jar").path) { return ["fabric"] }
                if fm.fileExists(atPath: dir.appendingPathComponent("forge.jar").path) { return ["forge", "neoforge"] }
            }
            return ["fabric", "forge", "neoforge", "quilt"]
        }
        return ["paper", "purpur", "spigot", "bukkit", "folia"]
    }

    func searchPlugins() {
        let q = pluginQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        pluginSearching = true; pluginStatus = "Recherche…"; pluginResults = []
        var groups: [String]
        if marketplaceMode == "mod" {
            // Seuls les mods utilisables côté serveur sont pertinents ici.
            groups = [#"["project_type:mod"]"#, #"["server_side:required","server_side:optional"]"#]
        } else {
            groups = [#"["project_type:plugin"]"#, #"["categories:bukkit","categories:spigot","categories:paper","categories:purpur","categories:folia"]"#]
        }
        if let v = detectedMCVersion { groups.append("[\"versions:\(v)\"]") }
        let facets = "[" + groups.joined(separator: ",") + "]"
        guard var c = URLComponents(string: "https://api.modrinth.com/v2/search") else { pluginSearching = false; return }
        c.queryItems = [URLQueryItem(name: "query", value: q), URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "facets", value: facets)]
        guard let url = c.url else { pluginSearching = false; return }
        let version = detectedMCVersion
        URLSession.shared.dataTask(with: HTTP.request(url)) { [weak self] data, response, err in
            Task { @MainActor in
                guard let self else { return }
                self.pluginSearching = false
                if let err { self.pluginStatus = err.localizedDescription; return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard (200...299).contains(code), let data,
                      let d = try? JSONDecoder().decode(ModrinthSearchResponse.self, from: data) else {
                    self.pluginStatus = "Erreur de recherche (HTTP \(code))"; return
                }
                self.pluginResults = d.hits
                let suffix = version.map { " · filtrés pour Minecraft \($0)" } ?? ""
                self.pluginStatus = "\(d.hits.count) résultat(s)\(suffix)"
            }
        }.resume()
    }

    func downloadPlugin(_ project: ModrinthProject) {
        guard let dir = serverDirectory else { return }
        let destDir = dir.appendingPathComponent(marketplaceMode == "mod" ? "mods" : "plugins")
        guard var comps = URLComponents(string: "https://api.modrinth.com/v2/project/\(project.projectId)/version") else { return }
        var items = [URLQueryItem(name: "loaders", value: Self.jsonArrayString(modrinthLoaders()))]
        let mc = detectedMCVersion
        if let mc { items.append(URLQueryItem(name: "game_versions", value: Self.jsonArrayString([mc]))) }
        comps.queryItems = items
        guard let url = comps.url else { return }
        downloadingPlugin = true; pluginStatus = "Recherche d'une version compatible…"
        URLSession.shared.dataTask(with: HTTP.request(url)) { [weak self] data, _, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let data, let versions = try? JSONDecoder().decode([ModrinthVersion].self, from: data) else {
                    self.downloadingPlugin = false; self.pluginStatus = "Échec de la recherche de versions"; return
                }
                guard let first = versions.first,
                      let file = first.files?.first(where: { $0.primary == true }) ?? first.files?.first,
                      let dl = URL(string: file.url) else {
                    self.downloadingPlugin = false
                    self.pluginStatus = mc.map { "Aucune version compatible avec Minecraft \($0)" } ?? "Aucune version compatible trouvée"
                    return
                }
                // lastPathComponent : on n'accepte jamais un nom de fichier contenant des « ../ ».
                let filename = (file.filename as NSString).lastPathComponent
                self.pluginStatus = "Téléchargement de \(filename)…"
                HTTP.download(from: dl, to: destDir.appendingPathComponent(filename)) { result in
                    Task { @MainActor in
                        self.downloadingPlugin = false
                        switch result {
                        case .success:
                            self.pluginStatus = "✓ \(filename) installé"
                            self.logActivity("Install \(filename)")
                            self.refreshFiles(); self.loadPluginConfigs()
                        case .failure(let e):
                            self.pluginStatus = "Échec du téléchargement : \(e.localizedDescription)"
                        }
                    }
                }
            }
        }.resume()
    }

    // MARK: Paper
    /// Met à jour paper.jar vers le dernier build de la MÊME version de Minecraft.
    /// (L'ancienne version téléchargeait la toute dernière version de Minecraft, ce qui pouvait
    /// migrer un monde de façon irréversible.)
    func checkPaperUpdate() {
        guard !isRunning else { paperStatus = "Arrête le serveur avant de mettre à jour Paper."; return }
        guard let dir = serverDirectory else { paperStatus = "Aucun serveur sélectionné."; return }
        let jar = dir.appendingPathComponent("paper.jar")
        guard FileManager.default.fileExists(atPath: jar.path) else { paperStatus = "Aucun paper.jar dans ce dossier."; return }
        guard let mc = detectedMCVersion else {
            paperStatus = "Version de Minecraft inconnue : démarre le serveur une fois (elle est lue dans les logs)."
            return
        }
        paperStatus = "Recherche du dernier build Paper pour Minecraft \(mc)…"
        paperDownloading = true
        PaperAPI.latestBuild(for: mc) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                self.paperDownloading = false
                self.paperStatus = "Échec : \(e.localizedDescription)"
            case .success(let build):
                self.paperStatus = "Téléchargement de \(build.filename)…"
                let staging = dir.appendingPathComponent("paper.jar.new")
                HTTP.download(from: build.url, to: staging) { dl in
                    Task { @MainActor in
                        self.paperDownloading = false
                        switch dl {
                        case .failure(let e):
                            self.paperStatus = "Échec du téléchargement : \(e.localizedDescription)"
                        case .success:
                            let fm = FileManager.default
                            let backup = dir.appendingPathComponent("paper.jar.bak")
                            try? fm.removeItem(at: backup)
                            try? fm.moveItem(at: jar, to: backup)
                            do {
                                try fm.moveItem(at: staging, to: jar)
                                self.paperStatus = "✓ Paper \(mc) build \(build.id) (ancienne version : paper.jar.bak)"
                                self.logActivity("Paper mis à jour : \(mc) #\(build.id)")
                            } catch {
                                try? fm.moveItem(at: backup, to: jar)
                                self.paperStatus = "Échec de l'installation : \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helpers hors acteur (exécutés en tâche de fond)
func dirSizeMB(_ url: URL) -> Double {
    guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total: Double = 0
    for case let u as URL in en {
        if let s = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Double(s) }
    }
    return total / 1_048_576
}

func readProcessUsage(pid: Int32) -> (cpu: Double, mb: Double)? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-p", "\(pid)", "-o", "%cpu=,rss="]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = out.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2 else { return nil }
        let cpu = Double(parts[0].replacingOccurrences(of: ",", with: ".")) ?? 0
        let mb = (Double(parts[1]) ?? 0) / 1024
        return (cpu, mb)
    } catch {
        return nil
    }
}

extension ProcessManager {
    /// Binding direct vers un réglage du serveur actif.
    func binding<T>(_ keyPath: WritableKeyPath<ServerSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                var s = self.settings
                s[keyPath: keyPath] = newValue
                self.settings = s
            }
        )
    }
}
