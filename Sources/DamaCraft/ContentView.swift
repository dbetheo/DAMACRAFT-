import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var selection = "Dashboard"
    @State private var renameText = ""

    private let destinations = ["Dashboard", "Console", "Fichiers", "Joueurs", "Plugins", "Configuration", "Sauvegardes", "Paramètres"]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch selection {
                        case "Dashboard": dashboard
                        case "Console": consoleSection
                        case "Fichiers": filesSection
                        case "Joueurs": playersSection
                        case "Plugins": PluginMarketplaceView()
                        case "Configuration": PluginConfigEditorView()
                        case "Sauvegardes": backupsSection
                        case "Paramètres": settingsSection
                        default: Text(selection).font(.largeTitle.bold())
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.09))
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "cube.transparent").font(.title).foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DamaCraft").font(.headline)
                    Text("SERVER CONTROL").font(.caption2).foregroundStyle(.secondary)
                }
            }

            // Multi-server list
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SERVEURS").font(.caption2.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button { manager.addServer() } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.purple)
                    .help("Ajouter un serveur")
                }

                if manager.profiles.isEmpty {
                    Text("Aucun serveur")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(manager.profiles) { profile in
                        HStack {
                            Button {
                                manager.selectProfile(profile.id)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(manager.activeProfileID == profile.id && manager.isRunning ? Color.green : Color.gray.opacity(0.5))
                                        .frame(width: 8, height: 8)
                                    Text(profile.name)
                                        .lineLimit(1)
                                        .font(.subheadline)
                                    Spacer()
                                }
                                .padding(8)
                                .background(manager.activeProfileID == profile.id ? Color.purple.opacity(0.25) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(manager.activeProfileID == profile.id ? .white : .secondary)

                            Button {
                                manager.removeProfile(profile.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(0.7))
                            .help("Supprimer de la liste")
                        }
                    }
                }
            }
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            ForEach(destinations, id: \.self) { item in
                Button { selection = item } label: {
                    Label(item, systemImage: icon(for: item))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(selection == item ? Color.purple.opacity(0.25) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == item ? .white : .secondary)
            }

            Spacer()
            Text("VERSION 0.7.0").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 240)
        .background(Color.black.opacity(0.22))
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text(selection).font(.title2.bold())
            Spacer()
            Text(manager.statusLabel)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(manager.isRunning ? Color.green.opacity(0.16) : Color.gray.opacity(0.16))
                .clipShape(Capsule())
            Button("Ajouter un serveur") { manager.addServer() }
                .buttonStyle(.borderedProminent).tint(.purple)
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Dashboard
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [.purple.opacity(0.8), .indigo.opacity(0.45), .black],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 8) {
                    Text("MINECRAFT SERVER").font(.caption.bold()).tracking(2).foregroundStyle(.white.opacity(0.7))
                    Text(manager.serverName).font(.system(size: 32, weight: .bold))
                    Text(manager.serverDirectory?.path ?? "Aucun dossier sélectionné")
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1).truncationMode(.middle)
                }.padding(28)
            }.frame(height: 160)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                metric("Joueurs", value: "\(manager.players.count) / \(manager.maxPlayers)", icon: "person.2")
                metric("CPU", value: manager.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—", icon: "cpu")
                metric("RAM", value: ramLabel, icon: "memorychip")
                metric("TPS", value: manager.reportedTPS ?? "—", icon: "speedometer")
            }

            if let pct = manager.memoryPercent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Utilisation RAM").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", pct)).font(.caption.bold())
                    }
                    ProgressView(value: min(1.0, pct / 100.0))
                        .tint(pct > 85 ? .red : pct > 70 ? .orange : .purple)
                }
            }

            HStack(spacing: 12) {
                Button("Démarrer") { manager.startServer() }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .disabled(manager.isRunning || manager.serverDirectory == nil)
                Button("Arrêter") { manager.stopGracefully() }
                    .buttonStyle(.bordered).disabled(!manager.isRunning)
                Button("Redémarrer") { manager.restartServer() }
                    .buttonStyle(.bordered)
                    .disabled(manager.serverDirectory == nil)
                Button("Force Kill") { manager.forceKill() }
                    .buttonStyle(.bordered).tint(.red).disabled(!manager.isRunning)
                Spacer()
                Text(manager.serverStatusMessage).font(.caption).foregroundStyle(.secondary)
            }

            liveConsolePreview
        }
    }

    private var ramLabel: String {
        if let mb = manager.memoryMB {
            if let pct = manager.memoryPercent {
                return String(format: "%.0f MB (%.0f%%)", mb, pct)
            }
            return String(format: "%.0f MB", mb)
        }
        return "—"
    }

    private var liveConsolePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Console en direct").font(.headline)
                Spacer()
                Button("Voir tout") { selection = "Console" }.font(.caption)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(manager.consoleLines.suffix(80).enumerated()), id: \.offset) { idx, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(lineColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading).id(idx)
                        }
                    }.padding(12)
                }
                .frame(height: 200)
                .background(.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: manager.consoleLines.count) { _, _ in
                    if let last = manager.consoleLines.suffix(80).indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            HStack {
                TextField("Commande serveur…", text: $manager.commandInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { manager.sendCommand() }
                Button("Envoyer") { manager.sendCommand() }
                    .buttonStyle(.borderedProminent).tint(.purple)
                    .disabled(!manager.isRunning)
            }
        }
    }

    // MARK: - Console
    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Console complète").font(.title2.bold())
                Spacer()
                Button("Effacer") { manager.consoleLines.removeAll() }.buttonStyle(.bordered)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(manager.consoleLines.enumerated()), id: \.offset) { idx, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(lineColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading).id(idx)
                        }
                    }.padding(12)
                }
                .frame(minHeight: 480)
                .background(.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: manager.consoleLines.count) { _, _ in
                    if let last = manager.consoleLines.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            HStack {
                TextField("Commande…", text: $manager.commandInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { manager.sendCommand() }
                Button("Envoyer") { manager.sendCommand() }
                    .buttonStyle(.borderedProminent).tint(.purple)
                    .disabled(!manager.isRunning)
                Button("stop") { manager.sendCommand("stop") }.buttonStyle(.bordered).disabled(!manager.isRunning)
                Button("list") { manager.sendCommand("list") }.buttonStyle(.bordered).disabled(!manager.isRunning)
            }
        }
    }

    // MARK: - Files
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Fichiers du serveur").font(.title2.bold())
                Spacer()
                Button("Actualiser") { manager.refreshFiles() }.buttonStyle(.bordered)
                Button("Ouvrir dans Finder") {
                    if let dir = manager.serverDirectory { NSWorkspace.shared.open(dir) }
                }
                .buttonStyle(.bordered)
                .disabled(manager.serverDirectory == nil)
            }
            if manager.serverDirectory == nil {
                ContentUnavailableView("Aucun serveur", systemImage: "folder",
                                       description: Text("Ajoute un serveur via le bouton + dans la sidebar."))
            } else {
                HStack(alignment: .top, spacing: 16) {
                    List(manager.files) { file in
                        Button {
                            manager.loadFileContent(file)
                        } label: {
                            Label(file.name, systemImage: file.isDirectory ? "folder.fill" : "doc.text")
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 8) {
                        if let selected = manager.selectedFile {
                            Text(selected.name).font(.headline)
                            ScrollView {
                                Text(manager.fileContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .padding(12)
                            .background(.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Text("Sélectionne un fichier.").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 520)
                }
            }
        }
    }

    // MARK: - Players
    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Joueurs en ligne").font(.title2.bold())
                Spacer()
                Text("\(manager.players.count) / \(manager.maxPlayers)").foregroundStyle(.secondary)
                Button("Rafraîchir (list)") { manager.sendCommand("list") }
                    .buttonStyle(.bordered).disabled(!manager.isRunning)
            }
            if manager.players.isEmpty {
                ContentUnavailableView(
                    manager.isRunning ? "Personne en ligne" : "Serveur arrêté",
                    systemImage: "person.2",
                    description: Text(manager.isRunning ? "Les connexions apparaîtront automatiquement." : "Démarre le serveur.")
                ).frame(minHeight: 200)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                    ForEach(manager.players) { player in
                        HStack {
                            Image(systemName: "person.circle.fill").foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(player.name).font(.headline)
                                Text("Connecté").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { manager.sendCommand("kick \(player.name)") } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: - Backups
    private var backupsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sauvegardes").font(.title2.bold())
            Text("Copie le dossier world dans backups/ à l'intérieur du serveur.")
                .foregroundStyle(.secondary)
            Button("Créer une sauvegarde du monde") { manager.createBackup() }
                .buttonStyle(.borderedProminent).tint(.purple)
                .disabled(manager.serverDirectory == nil)
        }
    }

    // MARK: - Settings
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Paramètres").font(.title2.bold())

            if manager.activeProfile != nil {
                GroupBox("Profil serveur") {
                    HStack {
                        TextField("Nom", text: Binding(
                            get: { manager.activeProfile?.name ?? "" },
                            set: { manager.renameActiveProfile($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                }
            }

            GroupBox("Mémoire JVM") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Min (Go)")
                        Slider(value: Binding(
                            get: { manager.settings.minMemoryGB },
                            set: { var s = manager.settings; s.minMemoryGB = $0; manager.settings = s }
                        ), in: 0.5...16, step: 0.5)
                        Text(String(format: "%.1f", manager.settings.minMemoryGB)).frame(width: 40, alignment: .trailing)
                    }
                    HStack {
                        Text("Max (Go)")
                        Slider(value: Binding(
                            get: { manager.settings.maxMemoryGB },
                            set: { var s = manager.settings; s.maxMemoryGB = $0; manager.settings = s }
                        ), in: 1...32, step: 0.5)
                        Text(String(format: "%.1f", manager.settings.maxMemoryGB)).frame(width: 40, alignment: .trailing)
                    }
                    Text("Args : \(manager.settings.jvmArguments.joined(separator: " "))")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }

            GroupBox("Arguments JVM supplémentaires") {
                TextField("-XX:+UseG1GC …", text: Binding(
                    get: { manager.settings.extraJVMArgs },
                    set: { var s = manager.settings; s.extraJVMArgs = $0; manager.settings = s }
                ))
                .textFieldStyle(.roundedBorder)
            }

            GroupBox("Comportement & notifications") {
                Toggle("Redémarrage auto en cas de crash", isOn: Binding(
                    get: { manager.settings.autoRestartOnCrash },
                    set: { var s = manager.settings; s.autoRestartOnCrash = $0; manager.settings = s }
                ))
                Toggle("Notification joueur connecté", isOn: Binding(
                    get: { manager.settings.notifyOnPlayerJoin },
                    set: { var s = manager.settings; s.notifyOnPlayerJoin = $0; manager.settings = s }
                ))
                Toggle("Notification joueur déconnecté", isOn: Binding(
                    get: { manager.settings.notifyOnPlayerLeave },
                    set: { var s = manager.settings; s.notifyOnPlayerLeave = $0; manager.settings = s }
                ))
                Toggle("Notification démarrage / arrêt", isOn: Binding(
                    get: { manager.settings.notifyOnServerStartStop },
                    set: { var s = manager.settings; s.notifyOnServerStartStop = $0; manager.settings = s }
                ))
                HStack {
                    Text("Lignes max console")
                    Spacer()
                    Stepper("\(manager.settings.maxConsoleLines)", value: Binding(
                        get: { manager.settings.maxConsoleLines },
                        set: { var s = manager.settings; s.maxConsoleLines = $0; manager.settings = s }
                    ), in: 200...5000, step: 100)
                }
            }

            Text("Les changements JVM s'appliquent au prochain démarrage.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func icon(for item: String) -> String {
        switch item {
        case "Dashboard": return "square.grid.2x2"
        case "Console": return "terminal"
        case "Fichiers": return "folder"
        case "Joueurs": return "person.2"
        case "Plugins": return "puzzlepiece"
        case "Configuration": return "slider.horizontal.3"
        case "Sauvegardes": return "archivebox"
        default: return "gearshape"
        }
    }

    private func lineColor(_ line: String) -> Color {
        let lower = line.lowercased()
        if line.hasPrefix(">") { return .cyan }
        if lower.contains("error") || lower.contains("exception") || lower.contains("severe") { return .red.opacity(0.9) }
        if lower.contains("warn") { return .orange.opacity(0.9) }
        if lower.contains("joined the game") { return .green }
        if lower.contains("left the game") { return .yellow.opacity(0.85) }
        if lower.contains("done (") { return .green.opacity(0.9) }
        return .green.opacity(0.85)
    }
}
