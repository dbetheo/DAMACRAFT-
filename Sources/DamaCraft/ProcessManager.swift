import Foundation
import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class ProcessManager: ObservableObject {
    // MARK: - Multi-server
    @Published var profiles: [ServerProfile] = []
    @Published var activeProfileID: UUID?

    // MARK: - Current server state
    @Published var statusLabel = "Arrêté"
    @Published var serverStatusMessage = "Ajoute ou sélectionne un serveur."
    @Published var consoleLines: [String] = []
    @Published var commandInput = ""
    @Published var cpuPercent: Double?
    @Published var memoryMB: Double?
    @Published var memoryPercent: Double?
    @Published var players: [OnlinePlayer] = []
    @Published var maxPlayers = 20
    @Published var reportedTPS: String?
    @Published var isRunning = false
    @Published var files: [ServerFile] = []
    @Published var selectedFile: ServerFile?
    @Published var fileContent: String = ""
    @Published var properties: [PropertyEntry] = []
    @Published var propertiesDirty = false

    // Marketplace
    @Published var pluginQuery = ""
    @Published var pluginResults: [ModrinthProject] = []
    @Published var pluginSearching = false
    @Published var pluginStatus = ""
    @Published var downloadingPlugin = false

    private var process: Process?
    private var inputPipe: Pipe?
    private var monitorTimer: Timer?
    private var restartWorkItem: DispatchWorkItem?
    private var isRestarting = false

    private let profilesKey = "damacraft.profiles"
    private let activeKey = "damacraft.activeProfile"

    var activeProfile: ServerProfile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first { $0.id == id }
    }

    var serverDirectory: URL? { activeProfile?.directoryURL }
    var serverName: String { activeProfile?.name ?? "Aucun serveur" }
    var settings: ServerSettings {
        get { activeProfile?.settings ?? ServerSettings() }
        set {
            guard let id = activeProfileID,
                  let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
            profiles[idx].settings = newValue
            saveProfiles()
        }
    }

    init() {
        loadProfiles()
        requestNotificationPermission()
        if let id = activeProfileID { selectProfile(id) }
    }

    // MARK: - Persistence
    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            profiles = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: idStr) {
            activeProfileID = id
        }
    }

    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if let id = activeProfileID {
            UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        }
    }

    // MARK: - Multi-server
    func addServer() {
        let panel = NSOpenPanel()
        panel.title = "Choisir le dossier du serveur Minecraft"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let profile = ServerProfile(name: url.lastPathComponent, directoryPath: url.path)
        profiles.append(profile)
        activeProfileID = profile.id
        saveProfiles()
        resetRuntimeState()
        refreshFiles()
        loadServerProperties()
        loadServerPropertiesHints()
        serverStatusMessage = "Serveur « \(profile.name) » ajouté."
        append("Serveur ajouté : \(url.path)")
    }

    func selectProfile(_ id: UUID) {
        if isRunning { stopGracefully() }
        activeProfileID = id
        saveProfiles()
        resetRuntimeState()
        refreshFiles()
        loadServerProperties()
        loadServerPropertiesHints()
        serverStatusMessage = "Serveur sélectionné : \(serverName)"
    }

    func removeProfile(_ id: UUID) {
        if activeProfileID == id, isRunning { stopGracefully() }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
            resetRuntimeState()
            if activeProfileID != nil {
                refreshFiles()
                loadServerProperties()
            }
        }
        saveProfiles()
    }

    func renameActiveProfile(_ name: String) {
        guard let id = activeProfileID,
              let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name
        saveProfiles()
    }

    private func resetRuntimeState() {
        consoleLines = []
        players = []
        cpuPercent = nil
        memoryMB = nil
        memoryPercent = nil
        reportedTPS = nil
        isRunning = false
        statusLabel = "Arrêté"
        properties = []
        propertiesDirty = false
        selectedFile = nil
        fileContent = ""
    }

    // MARK: - Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Files
    func refreshFiles() {
        guard let dir = serverDirectory else { files = []; return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            files = []; return
        }
        files = contents.map { ServerFile(url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loadFileContent(_ file: ServerFile) {
        selectedFile = file
        guard !file.isDirectory else { fileContent = "(Dossier)"; return }
        if let data = try? Data(contentsOf: file.url), let text = String(data: data, encoding: .utf8) {
            fileContent = text
        } else {
            fileContent = "(Impossible de lire ce fichier)"
        }
    }

    // MARK: - server.properties
    func loadServerProperties() {
        properties = []
        propertiesDirty = false
        guard let dir = serverDirectory else { return }
        let url = dir.appendingPathComponent("server.properties")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        var entries: [PropertyEntry] = []
        var pendingComment: String?
        for raw in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                pendingComment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                entries.append(PropertyEntry(key: parts[0].trimmingCharacters(in: .whitespaces),
                                             value: parts[1].trimmingCharacters(in: .whitespaces),
                                             comment: pendingComment))
                pendingComment = nil
            }
        }
        properties = entries
    }

    func updateProperty(key: String, value: String) {
        if let idx = properties.firstIndex(where: { $0.key == key }) {
            properties[idx].value = value
            propertiesDirty = true
        }
    }

    func saveServerProperties() {
        guard let dir = serverDirectory else { return }
        let url = dir.appendingPathComponent("server.properties")
        var lines: [String] = ["# DamaCraft — server.properties", "# \(Date())"]
        for e in properties {
            if let c = e.comment, !c.isEmpty { lines.append("# \(c)") }
            lines.append("\(e.key)=\(e.value)")
        }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            propertiesDirty = false
            serverStatusMessage = "server.properties enregistré."
            loadServerPropertiesHints()
            notify(title: "DamaCraft", body: "server.properties sauvegardé")
        } catch {
            serverStatusMessage = "Erreur écriture properties : \(error.localizedDescription)"
        }
    }

    private func loadServerPropertiesHints() {
        if let max = properties.first(where: { $0.key == "max-players" })?.value, let v = Int(max) {
            maxPlayers = v
        }
    }

    // MARK: - Start / Stop / Restart
    func startServer() {
        guard !isRunning else { return }
        guard let directory = serverDirectory else {
            serverStatusMessage = "Sélectionne un serveur d'abord."
            return
        }
        let jarName = ServerJarKind.allCases.map(\.rawValue)
            .first { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
        guard let jarName else {
            serverStatusMessage = "Aucun jar trouvé (server/paper/purpur/fabric/forge)."
            return
        }

        let task = Process()
        let output = Pipe()
        let input = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/java")
        var args = settings.jvmArguments
        args.append(contentsOf: ["-jar", jarName, "nogui"])
        task.arguments = args
        task.currentDirectoryURL = directory
        task.standardOutput = output
        task.standardError = output
        task.standardInput = input

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.append(text)
                self?.parseConsole(text)
            }
        }

        task.terminationHandler = { [weak self] ended in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stopMonitoring()
                self.isRunning = false
                self.statusLabel = "Arrêté"
                self.cpuPercent = nil
                self.memoryMB = nil
                self.memoryPercent = nil
                self.append("Processus terminé (code \(ended.terminationStatus)).")
                if self.settings.notifyOnServerStartStop {
                    self.notify(title: "Serveur arrêté", body: self.serverName)
                }
                if self.isRestarting {
                    self.isRestarting = false
                    self.serverStatusMessage = "Redémarrage…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.startServer() }
                } else if self.settings.autoRestartOnCrash && ended.terminationStatus != 0 {
                    self.serverStatusMessage = "Crash — redémarrage auto…"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.startServer() }
                } else {
                    self.serverStatusMessage = "Serveur arrêté."
                }
            }
        }

        do {
            try task.run()
            process = task
            inputPipe = input
            isRunning = true
            statusLabel = "En cours"
            serverStatusMessage = "Serveur démarré (\(jarName))."
            append(">>> java \(args.joined(separator: " "))")
            startMonitoring()
            if settings.notifyOnServerStartStop {
                notify(title: "Serveur démarré", body: "\(serverName) (\(jarName))")
            }
        } catch {
            serverStatusMessage = error.localizedDescription
            append("Erreur : \(error.localizedDescription)")
        }
    }

    func stopGracefully() {
        guard isRunning else { return }
        isRestarting = false
        sendCommand("stop")
        serverStatusMessage = "Arrêt en cours…"
        restartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.forceKill() }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    func forceKill() {
        guard let process, process.isRunning else { return }
        process.terminate()
        append(">>> Arrêt forcé (SIGTERM).")
    }

    func restartServer() {
        guard isRunning else { startServer(); return }
        isRestarting = true
        serverStatusMessage = "Redémarrage demandé…"
        sendCommand("stop")
        restartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.forceKill()
        }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    // MARK: - Console
    func sendCommand() {
        let value = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        commandInput = ""
        sendCommand(value)
    }

    func sendCommand(_ command: String) {
        guard let inputPipe, isRunning, let data = (command + "\n").data(using: .utf8) else { return }
        inputPipe.fileHandleForWriting.write(data)
        append("> \(command)")
    }

    private func append(_ text: String) {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        consoleLines.append(contentsOf: lines)
        let limit = max(100, settings.maxConsoleLines)
        if consoleLines.count > limit {
            consoleLines.removeFirst(consoleLines.count - limit)
        }
    }

    private func parseConsole(_ chunk: String) {
        for line in chunk.split(whereSeparator: \.isNewline).map(String.init) {
            if let name = extractPlayerName(from: line, patterns: [" joined the game", " joined the game."]) {
                if !players.contains(where: { $0.name == name }) {
                    players.append(OnlinePlayer(name: name))
                    if settings.notifyOnPlayerJoin {
                        notify(title: "Joueur connecté", body: "\(name) a rejoint \(serverName)")
                    }
                }
            }
            if let name = extractPlayerName(from: line, patterns: [" left the game", " left the game."]) {
                players.removeAll { $0.name == name }
                if settings.notifyOnPlayerLeave {
                    notify(title: "Joueur déconnecté", body: "\(name) a quitté \(serverName)")
                }
            }
            if line.contains("of a max of") && line.contains("players online") {
                if let max = extractInt(after: "max of", in: line) { maxPlayers = max }
            }
            if line.contains("TPS from last") || line.lowercased().contains("tps") {
                if let tps = extractTPS(from: line) { reportedTPS = tps }
            }
            if line.contains("Done (") && line.contains("For help, type") {
                serverStatusMessage = "Serveur prêt."
            }
        }
    }

    private func extractPlayerName(from line: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let range = line.range(of: pattern) {
                let before = String(line[..<range.lowerBound])
                if let last = before.split(whereSeparator: \.isWhitespace).last {
                    let name = String(last).trimmingCharacters(in: CharacterSet(charactersIn: "<>[]"))
                    if !name.isEmpty && name.count < 32 { return name }
                }
            }
        }
        return nil
    }

    private func extractInt(after marker: String, in line: String) -> Int? {
        guard let r = line.range(of: marker) else { return nil }
        let after = line[r.upperBound...]
        let digits = after.prefix(while: { $0.isNumber || $0 == " " }).trimmingCharacters(in: .whitespaces)
        return Int(digits)
    }

    private func extractTPS(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+\.\d+)"#) else { return nil }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        if let first = matches.first { return ns.substring(with: first.range) }
        return nil
    }

    // MARK: - Monitoring
    private func startMonitoring() {
        stopMonitoring()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateResourceUsage() }
        }
        updateResourceUsage()
    }

    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func updateResourceUsage() {
        guard let process, process.isRunning else {
            cpuPercent = nil; memoryMB = nil; memoryPercent = nil; return
        }
        let pid = process.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "%cpu=,rss="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !out.isEmpty else { return }
            let parts = out.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.count >= 2 {
                if let cpu = Double(parts[0]) { cpuPercent = cpu }
                if let rssKB = Double(parts[1]) {
                    let mb = rssKB / 1024.0
                    memoryMB = mb
                    let maxMB = settings.maxMemoryGB * 1024.0
                    if maxMB > 0 { memoryPercent = min(100.0, (mb / maxMB) * 100.0) }
                }
            }
        } catch {}
    }

    // MARK: - Plugin marketplace (Modrinth)
    func searchPlugins() {
        let q = pluginQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        pluginSearching = true
        pluginStatus = "Recherche…"
        pluginResults = []

        var components = URLComponents(string: "https://api.modrinth.com/v2/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: q),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "facets", value: "[[\"project_type:plugin\"],[\"categories:bukkit\",\"categories:spigot\",\"categories:paper\",\"categories:purpur\"]]")
        ]
        guard let url = components.url else { pluginSearching = false; return }

        var request = URLRequest(url: url)
        request.setValue("DamaCraft/0.7.0 (github.com/dbetheo/DAMACRAFT-)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor in
                self?.pluginSearching = false
                if let error {
                    self?.pluginStatus = "Erreur : \(error.localizedDescription)"
                    return
                }
                guard let data,
                      let decoded = try? JSONDecoder().decode(ModrinthSearchResponse.self, from: data) else {
                    self?.pluginStatus = "Réponse invalide"
                    return
                }
                self?.pluginResults = decoded.hits
                self?.pluginStatus = "\(decoded.hits.count) résultat(s)"
            }
        }.resume()
    }

    func downloadPlugin(_ project: ModrinthProject) {
        guard let dir = serverDirectory else {
            pluginStatus = "Sélectionne un serveur d'abord."
            return
        }
        let pluginsDir = dir.appendingPathComponent("plugins")
        try? FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

        downloadingPlugin = true
        pluginStatus = "Récupération des versions…"

        let versionURL = URL(string: "https://api.modrinth.com/v2/project/\(project.projectId)/version")!
        var request = URLRequest(url: versionURL)
        request.setValue("DamaCraft/0.7.0 (github.com/dbetheo/DAMACRAFT-)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.downloadingPlugin = false
                    self.pluginStatus = error.localizedDescription
                    return
                }
                guard let data,
                      let versions = try? JSONDecoder().decode([ModrinthVersion].self, from: data),
                      let version = versions.first,
                      let file = version.files?.first(where: { $0.primary == true }) ?? version.files?.first,
                      let downloadURL = URL(string: file.url) else {
                    self.downloadingPlugin = false
                    self.pluginStatus = "Aucune version téléchargeable"
                    return
                }

                self.pluginStatus = "Téléchargement de \(file.filename)…"
                URLSession.shared.downloadTask(with: downloadURL) { tempURL, _, err in
                    Task { @MainActor in
                        self.downloadingPlugin = false
                        if let err {
                            self.pluginStatus = err.localizedDescription
                            return
                        }
                        guard let tempURL else { return }
                        let dest = pluginsDir.appendingPathComponent(file.filename)
                        try? FileManager.default.removeItem(at: dest)
                        do {
                            try FileManager.default.moveItem(at: tempURL, to: dest)
                            self.pluginStatus = "✓ \(file.filename) installé dans plugins/"
                            self.notify(title: "Plugin installé", body: file.filename)
                            self.refreshFiles()
                        } catch {
                            self.pluginStatus = "Erreur copie : \(error.localizedDescription)"
                        }
                    }
                }.resume()
            }
        }.resume()
    }

    // MARK: - Backup
    func createBackup() {
        guard let dir = serverDirectory else { return }
        let world = dir.appendingPathComponent("world")
        let backups = dir.appendingPathComponent("backups")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dest = backups.appendingPathComponent("world_\(formatter.string(from: Date()))")
        do {
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: world.path) {
                try FileManager.default.copyItem(at: world, to: dest)
                serverStatusMessage = "Sauvegarde : \(dest.lastPathComponent)"
                notify(title: "Sauvegarde créée", body: dest.lastPathComponent)
            } else {
                serverStatusMessage = "Dossier world introuvable."
            }
        } catch {
            serverStatusMessage = "Erreur sauvegarde : \(error.localizedDescription)"
        }
    }
}
