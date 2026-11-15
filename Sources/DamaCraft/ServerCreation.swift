import Foundation
import AppKit

extension ProcessManager {
    func fetchVersions(for software: ServerSoftware, completion: @escaping ([String]) -> Void) {
        switch software {
        case .paper:
            PaperAPI.versions(completion: completion)
        case .spigot:
            fetchMojangReleaseVersions(completion: completion)
        case .purpur:
            // Purpur API
            guard let url = URL(string: "https://api.purpurmc.org/v2/purpur") else {
                completion([]); return
            }
            HTTP.json(url) { result in
                var list: [String] = []
                if case .success(let obj) = result, let dict = obj as? [String: Any],
                   let versions = dict["versions"] as? [String] {
                    list = PaperAPI.sortDescending(versions.filter { PaperAPI.isStableVersion($0) })
                }
                Task { @MainActor in completion(list) }
            }
        case .vanilla:
            guard let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json") else {
                completion([]); return
            }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                var list: [String] = []
                if let data,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let versions = obj["versions"] as? [[String: Any]] {
                    list = versions.compactMap { v in
                        guard let id = v["id"] as? String, let type = v["type"] as? String, type == "release" else { return nil }
                        return id
                    }
                }
                Task { @MainActor in completion(list) }
            }.resume()
        }
    }

    /// Creates a server, downloads/compiles its jar, writes configuration and registers it.
    func createServer(
        name: String,
        parentPath: String,
        software: ServerSoftware,
        version: String,
        minRAM: Double,
        maxRAM: Double,
        acceptEULA: Bool,
        autoStart: Bool,
        progress: @escaping (Double, String) -> Void
    ) {
        guard acceptEULA else {
            progress(1.0, "Tu dois accepter l’EULA Minecraft avant de créer le serveur.")
            return
        }
        guard !isRunning else {
            progress(1.0, "Arrête le serveur en cours avant d’en créer un autre.")
            return
        }

        let parent = URL(fileURLWithPath: parentPath, isDirectory: true)
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dir.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    progress(1.0, "Un fichier portant le nom « \(name) » existe déjà à cet emplacement.")
                    return
                }
                // Reuse an existing empty/incomplete server folder (for example a folder
                // previously added with “Ajouter un serveur”). Never replace an existing JAR.
                let existingJars = ServerJarKind.allCases.map { dir.appendingPathComponent($0.rawValue) }
                    .filter { fm.fileExists(atPath: $0.path) }
                guard existingJars.isEmpty else {
                    progress(1.0, "Ce dossier contient déjà un fichier serveur .jar. Ajoute-le comme serveur existant au lieu de le recréer.")
                    return
                }
            } else {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        } catch {
            progress(1.0, "Erreur de création du dossier : \(error.localizedDescription)")
            return
        }

        progress(0.12, "Préparation de \(software.rawValue) \(version)…")

        let finish: (URL) -> Void = { [weak self] jarURL in
            guard let self else { return }
            do {
                let expectedJar = dir.appendingPathComponent(software.jarName)
                if jarURL.standardizedFileURL != expectedJar.standardizedFileURL {
                    if fm.fileExists(atPath: expectedJar.path) { try fm.removeItem(at: expectedJar) }
                    try fm.copyItem(at: jarURL, to: expectedJar)
                }
                let attributes = try fm.attributesOfItem(atPath: expectedJar.path)
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                guard size > 0 else {
                    progress(1.0, "Le fichier serveur téléchargé est vide.")
                    return
                }

                progress(0.82, "Écriture de la configuration…")
                self.writeBaseFiles(dir: dir, version: version, acceptEULA: acceptEULA)

                var profileSettings = ServerSettings()
                profileSettings.minMemoryGB = minRAM
                profileSettings.maxMemoryGB = maxRAM
                let normalizedPath = dir.standardizedFileURL.path
                let profile: ServerProfile
                if let existingIndex = self.profiles.firstIndex(where: {
                    $0.directoryURL.standardizedFileURL.path == normalizedPath
                }) {
                    self.profiles[existingIndex].name = name
                    self.profiles[existingIndex].settings = profileSettings
                    profile = self.profiles[existingIndex]
                } else {
                    profile = ServerProfile(name: name, directoryPath: dir.path, settings: profileSettings)
                    self.profiles.append(profile)
                }
                self.activeProfileID = profile.id
                self.saveProfiles()
                self.resetRuntimeForNewServer()
                self.refreshAll()
                self.detectedMCVersion = version
                self.logActivity("Serveur créé : \(name) (\(software.rawValue) \(version))")
                self.serverStatusMessage = "Serveur « \(name) » prêt."
                self.notify(title: "Serveur créé", body: "\(name) — \(software.rawValue) \(version)")

                if autoStart {
                    progress(0.94, "Serveur créé. Démarrage de Minecraft…")
                    self.startServer()
                    if self.isRunning {
                        progress(1.0, "✓ Serveur créé et démarré dans \(dir.path)")
                    } else {
                        progress(1.0, "✓ Serveur créé. Démarrage impossible : \(self.serverStatusMessage)")
                    }
                } else {
                    progress(1.0, "✓ Serveur créé dans \(dir.path). Tu peux le démarrer depuis le tableau de bord.")
                }
            } catch {
                progress(1.0, "Erreur lors de la préparation du serveur : \(error.localizedDescription)")
            }
        }

        if software == .spigot {
            progress(0.22, "Téléchargement de BuildTools officiel…")
            compileSpigot(version: version, in: dir, progress: { message in
                Task { @MainActor in progress(0.35, message) }
            }) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let jar): finish(jar)
                    case .failure(let error):
                        progress(1.0, "Échec BuildTools : \(error.localizedDescription)")
                    }
                }
            }
        } else {
            progress(0.2, "Recherche du téléchargement \(software.rawValue)…")
            resolveDownloadURL(software: software, version: version) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .failure(let error):
                        progress(1.0, "Erreur de téléchargement : \(error.localizedDescription)")
                    case .success(let url):
                        progress(0.4, "Téléchargement de \(software.jarName)…")
                        HTTP.download(from: url, to: dir.appendingPathComponent(software.jarName)) { downloadResult in
                            Task { @MainActor in
                                switch downloadResult {
                                case .success:
                                    finish(dir.appendingPathComponent(software.jarName))
                                case .failure(let error):
                                    progress(1.0, "Échec du téléchargement : \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchMojangReleaseVersions(completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json") else {
            completion([]); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var versions: [String] = []
            if let data,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let entries = object["versions"] as? [[String: Any]] {
                versions = entries.compactMap { entry in
                    guard entry["type"] as? String == "release" else { return nil }
                    return entry["id"] as? String
                }
            }
            Task { @MainActor in completion(versions) }
        }.resume()
    }

    /// Downloads the official BuildTools artifact and compiles Spigot in the background.
    private func compileSpigot(
        version: String,
        in serverDirectory: URL,
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let javaURL = resolvedJavaExecutable() else {
            completion(.failure(NSError(domain: "DamaCraft.BuildTools", code: 24, userInfo: [NSLocalizedDescriptionKey: "Java introuvable. Installe un JDK avant de compiler Spigot."])))
            return
        }
        guard let buildToolsURL = URL(string: "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar") else {
            completion(.failure(NSError(domain: "DamaCraft", code: 20, userInfo: [NSLocalizedDescriptionKey: "URL BuildTools invalide."])))
            return
        }

        let buildDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DamaCraft-BuildTools-\(UUID().uuidString)", isDirectory: true)
        let logDirectory = serverDirectory.appendingPathComponent(".buildtools", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error)); return
        }

        URLSession.shared.downloadTask(with: buildToolsURL) { temporaryURL, response, error in
            if let error { completion(.failure(error)); return }
            guard let temporaryURL else {
                completion(.failure(NSError(domain: "DamaCraft", code: 21, userInfo: [NSLocalizedDescriptionKey: "BuildTools n’a pas été téléchargé."])))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(NSError(domain: "DamaCraft", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Téléchargement BuildTools : HTTP \(http.statusCode)."])))
                return
            }

            let buildToolsJar = buildDirectory.appendingPathComponent("BuildTools.jar")
            do {
                if FileManager.default.fileExists(atPath: buildToolsJar.path) {
                    try FileManager.default.removeItem(at: buildToolsJar)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: buildToolsJar)
            } catch {
                completion(.failure(error)); return
            }

            progress("Compilation Spigot \(version) en cours (cela peut prendre plusieurs minutes)…")
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = javaURL
                process.arguments = ["-jar", buildToolsJar.path, "--rev", version, "--compile", "SPIGOT"]
                process.currentDirectoryURL = buildDirectory
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = environment

                let logURL = logDirectory.appendingPathComponent("BuildTools.log")
                try? FileManager.default.removeItem(at: logURL)
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                do {
                    let logHandle = try FileHandle(forWritingTo: logURL)
                    process.standardOutput = logHandle
                    process.standardError = logHandle
                    try process.run()
                    process.waitUntilExit()
                    try? logHandle.close()

                    guard process.terminationStatus == 0 else {
                        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                        let tail = log.split(whereSeparator: \.isNewline).suffix(12).joined(separator: "\n")
                        try? FileManager.default.removeItem(at: buildDirectory)
                        completion(.failure(NSError(domain: "DamaCraft.BuildTools", code: Int(process.terminationStatus), userInfo: [
                            NSLocalizedDescriptionKey: "BuildTools a échoué (code \(process.terminationStatus)). Vérifie que Java et Git sont installés. Journal : \(logURL.path)\n\(tail)"
                        ])))
                        return
                    }

                    let enumerator = FileManager.default.enumerator(at: buildDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                    var candidates: [URL] = []
                    while let item = enumerator?.nextObject() as? URL {
                        if item.pathExtension.lowercased() == "jar",
                           item.lastPathComponent.lowercased().hasPrefix("spigot-") {
                            candidates.append(item)
                        }
                    }
                    guard let jar = candidates.sorted(by: { $0.path < $1.path }).first else {
                        try? FileManager.default.removeItem(at: buildDirectory)
                        completion(.failure(NSError(domain: "DamaCraft.BuildTools", code: 22, userInfo: [NSLocalizedDescriptionKey: "Compilation terminée mais aucun spigot-<version>.jar n’a été trouvé. Consulte \(logURL.path)."])))
                        return
                    }
                    let destination = serverDirectory.appendingPathComponent("spigot.jar")
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: jar, to: destination)
                    try? FileManager.default.removeItem(at: buildDirectory)
                    completion(.success(destination))
                } catch {
                    try? FileManager.default.removeItem(at: buildDirectory)
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private func resetRuntimeForNewServer() {
        // soft reset without requiring private method name collision
        consoleLines = []
        players = []
        isRunning = false
        statusLabel = "Arrêté"
        eulaAccepted = true
    }

    private func writeBaseFiles(dir: URL, version: String, acceptEULA: Bool) {
        let eula = "# Generated by DamaCraft\neula=\(acceptEULA ? "true" : "false")\n"
        try? eula.write(to: dir.appendingPathComponent("eula.txt"), atomically: true, encoding: .utf8)

        let props = """
        # DamaCraft generated
        # Minecraft \(version)
        motd=Serveur DamaCraft
        max-players=20
        gamemode=survival
        difficulty=normal
        online-mode=true
        pvp=true
        spawn-monsters=true
        view-distance=10
        server-port=25565
        enable-command-block=false
        """
        let propertiesURL = dir.appendingPathComponent("server.properties")
        if !FileManager.default.fileExists(atPath: propertiesURL.path) {
            try? props.write(to: propertiesURL, atomically: true, encoding: .utf8)
        }

        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("plugins"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("logs"), withIntermediateDirectories: true)
    }

    private func resolveDownloadURL(software: ServerSoftware, version: String, completion: @escaping (Result<URL, Error>) -> Void) {
        switch software {
        case .paper:
            PaperAPI.latestBuild(for: version) { result in
                switch result {
                case .success(let build): completion(.success(build.url))
                case .failure(let error): completion(.failure(error))
                }
            }

        case .spigot:
            completion(.failure(NSError(domain: "DamaCraft", code: 23, userInfo: [NSLocalizedDescriptionKey: "Spigot est compilé avec BuildTools, pas téléchargé directement."])))
        case .purpur:
            let url = URL(string: "https://api.purpurmc.org/v2/purpur/\(version)/latest/download")!
            // Purpur latest download redirects — URLSession follows redirects
            completion(.success(url))

        case .vanilla:
            guard let manifestURL = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json") else {
                completion(.failure(NSError(domain: "DamaCraft", code: 2, userInfo: [NSLocalizedDescriptionKey: "Manifest Mojang"]))); return
            }
            URLSession.shared.dataTask(with: manifestURL) { data, _, error in
                if let error { completion(.failure(error)); return }
                guard let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let versions = obj["versions"] as? [[String: Any]],
                      let match = versions.first(where: { ($0["id"] as? String) == version }),
                      let versionURLStr = match["url"] as? String,
                      let versionURL = URL(string: versionURLStr)
                else {
                    completion(.failure(NSError(domain: "DamaCraft", code: 3, userInfo: [NSLocalizedDescriptionKey: "Version \(version) introuvable"]))); return
                }
                URLSession.shared.dataTask(with: versionURL) { data2, _, error2 in
                    if let error2 { completion(.failure(error2)); return }
                    guard let data2,
                          let vobj = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
                          let downloads = vobj["downloads"] as? [String: Any],
                          let server = downloads["server"] as? [String: Any],
                          let urlStr = server["url"] as? String,
                          let url = URL(string: urlStr)
                    else {
                        completion(.failure(NSError(domain: "DamaCraft", code: 4, userInfo: [NSLocalizedDescriptionKey: "Pas de server.jar pour \(version)"])))
                        return
                    }
                    completion(.success(url))
                }.resume()
            }.resume()
        }
    }

}

// MARK: - HTTP helpers
enum HTTPError: LocalizedError {
    case status(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .status(let code): return "HTTP \(code)"
        case .empty: return "Réponse vide ou illisible"
        }
    }
}

enum HTTP {
    static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    /// Télécharge un fichier. Le déplacement est fait DANS le callback : URLSession supprime
    /// le fichier temporaire dès que celui-ci retourne. Le completion est appelé hors thread principal.
    static func download(from url: URL, to dest: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let task = URLSession.shared.downloadTask(with: request(url)) { temp, response, error in
            if let error { completion(.failure(error)); return }
            guard let temp else { completion(.failure(HTTPError.empty)); return }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(HTTPError.status(http.statusCode))); return
            }
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: temp, to: dest)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    static func json(_ url: URL, completion: @escaping (Result<Any, Error>) -> Void) {
        URLSession.shared.dataTask(with: request(url)) { data, response, error in
            if let error { completion(.failure(error)); return }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(HTTPError.status(http.statusCode))); return
            }
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) else {
                completion(.failure(HTTPError.empty)); return
            }
            completion(.success(obj))
        }.resume()
    }
}

// MARK: - PaperMC « Fill » v3
// L'ancienne API (api.papermc.io/v2) a été désactivée le 1er juillet 2026.
enum PaperAPI {
    struct Build {
        let id: Int
        let channel: String
        let url: URL
        let filename: String
    }

    static let base = "https://fill.papermc.io/v3/projects/paper"

    /// Versions de Minecraft supportées, de la plus récente à la plus ancienne (versions stables uniquement).
    static func versions(completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: base) else { completion([]); return }
        HTTP.json(url) { result in
            var list: [String] = []
            if case .success(let obj) = result, let dict = obj as? [String: Any] {
                if let grouped = dict["versions"] as? [String: [String]] {
                    list = grouped.values.flatMap { $0 }
                } else if let flat = dict["versions"] as? [String] {
                    list = flat
                }
            }
            let stable = list.filter { isStableVersion($0) }
            let sorted = sortDescending(stable.isEmpty ? list : stable)
            Task { @MainActor in completion(sorted) }
        }
    }

    /// Dernier build (stable en priorité) pour une version de Minecraft donnée.
    static func latestBuild(for version: String, completion: @escaping (Result<Build, Error>) -> Void) {
        let encoded = version.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? version
        guard let url = URL(string: "\(base)/versions/\(encoded)/builds") else {
            completion(.failure(HTTPError.empty)); return
        }
        HTTP.json(url) { result in
            let outcome: Result<Build, Error>
            switch result {
            case .failure(let e):
                outcome = .failure(e)
            case .success(let obj):
                if let build = pickBuild(from: obj) {
                    outcome = .success(build)
                } else {
                    outcome = .failure(NSError(domain: "DamaCraft", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Aucun build Paper disponible pour Minecraft \(version)."
                    ]))
                }
            }
            Task { @MainActor in completion(outcome) }
        }
    }

    private static func pickBuild(from obj: Any) -> Build? {
        let array: [[String: Any]]
        if let a = obj as? [[String: Any]] {
            array = a
        } else if let d = obj as? [String: Any], let a = d["builds"] as? [[String: Any]] {
            array = a
        } else {
            return nil
        }
        let parsed: [Build] = array.compactMap { (b: [String: Any]) -> Build? in
            guard let downloads = b["downloads"] as? [String: Any] else { return nil }
            let entry: Any? = downloads["server:default"] ?? downloads.values.first
            guard let server = entry as? [String: Any],
                  let urlString = server["url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            let id = (b["id"] as? Int) ?? (b["number"] as? Int) ?? 0
            let channel = ((b["channel"] as? String) ?? "STABLE").uppercased()
            let name = (server["name"] as? String) ?? url.lastPathComponent
            return Build(id: id, channel: channel, url: url, filename: name)
        }
        for channel in ["STABLE", "BETA", "ALPHA"] {
            if let best = parsed.filter({ $0.channel == channel }).max(by: { $0.id < $1.id }) { return best }
        }
        return parsed.max(by: { $0.id < $1.id })
    }

    static func isStableVersion(_ v: String) -> Bool {
        v.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil
    }

    static func sortDescending(_ list: [String]) -> [String] {
        list.sorted { lhs, rhs in
            let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
            let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
            for i in 0..<max(l.count, r.count) {
                let a = i < l.count ? l[i] : 0
                let b = i < r.count ? r[i] : 0
                if a != b { return a > b }
            }
            return false
        }
    }
}
