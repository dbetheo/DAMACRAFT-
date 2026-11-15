import SwiftUI
import AppKit

// MARK: - Fichiers
struct FilesView: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button { manager.refreshFiles() } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
                Button {
                    if let d = manager.serverDirectory { NSWorkspace.shared.open(d) }
                } label: { Label("Ouvrir dans le Finder", systemImage: "folder") }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(manager.serverDirectory == nil)
            }
            if manager.serverDirectory == nil {
                EmptyState(title: "Aucun serveur", icon: "folder.fill")
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(manager.files) { f in
                                Button { manager.loadFileContent(f) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: f.isDirectory ? "folder.fill" : "doc.text")
                                            .foregroundStyle(f.isDirectory ? DC.accent : DC.textSec)
                                            .frame(width: 18)
                                        Text(f.name).lineLimit(1)
                                        Spacer()
                                    }
                                    .font(.system(size: 12, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(manager.selectedFile == f ? DC.accentDim : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .frame(width: 250)
                    .dcPanel(cornerRadius: 12)

                    ScrollView {
                        Text(manager.fileContent.isEmpty ? "Sélectionne un fichier à gauche." : manager.fileContent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(manager.fileContent.isEmpty ? DC.textSec : Color.white.opacity(0.85))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .dcPanel(cornerRadius: 12)
                }
                .frame(height: 500)
            }
        }
    }
}

// MARK: - Joueurs
struct PlayersView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var playerToBan: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                StatusPill(text: "\(manager.players.count)/\(manager.maxPlayers) en ligne", color: DC.cyan, icon: "person.2.fill")
                Spacer()
                Button { manager.sendCommand("list") } label: { Label("Actualiser (list)", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(!manager.isRunning)
            }
            if manager.players.isEmpty {
                EmptyState(
                    title: manager.isRunning ? "Personne en ligne" : "Serveur arrêté",
                    icon: "person.2.fill",
                    message: manager.isRunning ? "Les joueurs apparaîtront ici dès leur connexion." : "Démarre le serveur pour voir les joueurs."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(manager.players) { p in
                        playerCard(p)
                    }
                }
            }
        }
        .confirmationDialog(
            "Bannir \(playerToBan ?? "") ?",
            isPresented: Binding(get: { playerToBan != nil }, set: { if !$0 { playerToBan = nil } }),
            titleVisibility: .visible
        ) {
            Button("Bannir", role: .destructive) {
                if let n = playerToBan { manager.banPlayer(n) }
                playerToBan = nil
            }
            Button("Annuler", role: .cancel) { playerToBan = nil }
        }
    }

    private func avatar(_ name: String) -> some View {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return AsyncImage(url: URL(string: "https://minotar.net/helm/\(encoded)/64")) { image in
            image.resizable().interpolation(.none).scaledToFit()
        } placeholder: {
            Image(systemName: "person.fill").foregroundStyle(DC.green)
        }
        .frame(width: 38, height: 38)
        .background(DC.green.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func playerCard(_ p: OnlinePlayer) -> some View {
        DCCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    avatar(p.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("connecté \(p.joinedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(DC.textSec)
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Button("Kick") { manager.kickPlayer(p.name) }.buttonStyle(ChipButtonStyle())
                    Button("Ban") { playerToBan = p.name }.buttonStyle(ChipButtonStyle(tint: DC.red))
                    Button("Op") { manager.opPlayer(p.name) }.buttonStyle(ChipButtonStyle())
                    Menu("Mode") {
                        Button("Survie") { manager.gamemode("survival", player: p.name) }
                        Button("Créatif") { manager.gamemode("creative", player: p.name) }
                        Button("Aventure") { manager.gamemode("adventure", player: p.name) }
                        Button("Spectateur") { manager.gamemode("spectator", player: p.name) }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .disabled(!manager.isRunning)
            }
        }
    }
}

// MARK: - Configs plugins
struct PluginConfigsView: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button { manager.loadPluginConfigs() } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
                Button { manager.snapshotPlugins() } label: { Label("Snapshot des plugins", systemImage: "camera") }
                    .buttonStyle(ChipButtonStyle())
                Button { manager.savePluginConfig() } label: { Label("Enregistrer", systemImage: "square.and.arrow.down") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!manager.pluginConfigDirty)
            }
            if manager.pluginConfigs.isEmpty {
                EmptyState(
                    title: "Aucune config de plugin",
                    icon: "doc.badge.gearshape",
                    message: "Les fichiers .yml du dossier plugins/ apparaissent après le premier démarrage avec des plugins installés."
                )
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(manager.pluginConfigs) { f in
                                Button { manager.loadPluginConfig(f) } label: {
                                    HStack {
                                        Image(systemName: "doc.text").foregroundStyle(DC.textSec)
                                        Text(f.name).lineLimit(1)
                                        Spacer()
                                    }
                                    .font(.system(size: 12, design: .rounded))
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(manager.selectedPluginConfig == f ? DC.accentDim : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .frame(width: 230)
                    .dcPanel(cornerRadius: 12)

                    TextEditor(text: Binding(
                        get: { manager.pluginConfigContent },
                        set: { manager.pluginConfigContent = $0; manager.pluginConfigDirty = true }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .dcPanel(cornerRadius: 12)
                }
                .frame(height: 480)
            }
        }
    }
}

// MARK: - Mondes
struct WorldsView: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button { manager.refreshWorlds(); manager.loadDatapacks() } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
            }
            if manager.worlds.isEmpty {
                EmptyState(
                    title: "Aucun monde",
                    icon: "globe.europe.africa.fill",
                    message: "Le monde est généré au premier démarrage du serveur."
                )
            }
            ForEach(manager.worlds) { w in
                DCCard {
                    HStack(spacing: 12) {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.title2)
                            .foregroundStyle(DC.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text(String(format: "%.1f Mo", w.sizeMB)).font(.caption).foregroundStyle(DC.textSec)
                        }
                        Spacer()
                        Button { NSWorkspace.shared.open(w.url) } label: { Label("Finder", systemImage: "folder") }
                            .buttonStyle(ChipButtonStyle())
                        Button { manager.createBackup(worldName: w.name) } label: { Label("Sauvegarder", systemImage: "archivebox") }
                            .buttonStyle(ChipButtonStyle())
                    }
                }
            }
            if !manager.datapacks.isEmpty {
                Text("Datapacks").font(.system(size: 14, weight: .semibold, design: .rounded))
                FlowLabels(items: manager.datapacks.map(\.name))
            }
        }
    }
}

struct FlowLabels: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DC.accentDim)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Sauvegardes
struct BackupsView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var backupToRestore: BackupInfo?
    @State private var backupToDelete: BackupInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DCCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("Sauvegardes automatiques", isOn: manager.binding(\.autoBackupEnabled))
                            .toggleStyle(.switch)
                        Spacer()
                        Button { manager.createBackup() } label: { Label("Sauvegarder « \(manager.levelName) »", systemImage: "archivebox.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(manager.serverDirectory == nil)
                    }
                    HStack(spacing: 24) {
                        Stepper(value: manager.binding(\.autoBackupIntervalHours), in: 1...72, step: 1) {
                            Text("Toutes les \(Int(manager.settings.autoBackupIntervalHours)) h")
                                .font(.system(size: 12, design: .rounded))
                        }
                        .disabled(!manager.settings.autoBackupEnabled)
                        Stepper(value: manager.binding(\.maxBackups), in: 0...100, step: 1) {
                            Text(manager.settings.maxBackups == 0 ? "Conserver tout" : "Garder les \(manager.settings.maxBackups) dernières par monde")
                                .font(.system(size: 12, design: .rounded))
                        }
                    }
                    Text("Pendant que le serveur tourne, l'écriture du monde est suspendue quelques secondes pendant la copie pour garantir une sauvegarde cohérente.")
                        .font(.caption)
                        .foregroundStyle(DC.textTer)
                }
            }

            if manager.backups.isEmpty {
                EmptyState(title: "Aucune sauvegarde", icon: "archivebox.fill")
            }
            ForEach(manager.backups) { b in
                DCCard {
                    HStack(spacing: 12) {
                        Image(systemName: "archivebox.fill").foregroundStyle(DC.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(b.name).font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text("\(b.date.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.1f Mo", b.sizeMB))")
                                .font(.caption).foregroundStyle(DC.textSec)
                        }
                        Spacer()
                        Button { backupToRestore = b } label: { Label("Restaurer", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(ChipButtonStyle())
                            .disabled(manager.isRunning)
                        Button { backupToDelete = b } label: { Image(systemName: "trash") }
                            .buttonStyle(ChipButtonStyle(tint: DC.red))
                    }
                }
            }
        }
        .confirmationDialog(
            "Restaurer cette sauvegarde ?",
            isPresented: Binding(get: { backupToRestore != nil }, set: { if !$0 { backupToRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restaurer", role: .destructive) {
                if let b = backupToRestore { manager.restoreBackup(b) }
                backupToRestore = nil
            }
            Button("Annuler", role: .cancel) { backupToRestore = nil }
        } message: {
            Text("Le monde actuel sera remplacé. Il est conservé à côté dans un dossier « .avant-restauration ».")
        }
        .confirmationDialog(
            "Supprimer cette sauvegarde ?",
            isPresented: Binding(get: { backupToDelete != nil }, set: { if !$0 { backupToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let b = backupToDelete { manager.deleteBackup(b) }
                backupToDelete = nil
            }
            Button("Annuler", role: .cancel) { backupToDelete = nil }
        }
    }
}

// MARK: - Sécurité
struct SecurityView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button { manager.loadJSONLists() } label: { Label("Recharger", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
            }
            DCCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Whitelist", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DC.accent)
                    HStack(spacing: 8) {
                        TextField("Pseudo à ajouter", text: $newName)
                            .dcField()
                            .onSubmit(addToWhitelist)
                        Button(action: addToWhitelist) { Label("Ajouter", systemImage: "plus") }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!manager.isRunning || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if manager.whitelistEntries.isEmpty {
                        Text("Aucun joueur").font(.caption).foregroundStyle(DC.textSec)
                    }
                    ForEach(manager.whitelistEntries) { e in
                        HStack {
                            Text(e.name).font(.system(size: 13, design: .monospaced))
                            Spacer()
                            Button { manager.whitelistRemove(e.name); reloadSoon() } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .foregroundStyle(DC.red)
                                .disabled(!manager.isRunning)
                        }
                    }
                }
            }
            listCard("Opérateurs", manager.opsEntries.map(\.name), "star.fill")
            listCard("Bannis", manager.bannedEntries.map { $0.extra.isEmpty ? $0.name : "\($0.name) — \($0.extra)" }, "nosign")
        }
    }

    private func addToWhitelist() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, manager.isRunning else { return }
        manager.whitelistAdd(n)
        newName = ""
        reloadSoon()
    }

    private func reloadSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            manager.loadJSONLists()
        }
    }

    private func listCard(_ title: String, _ items: [String], _ icon: String) -> some View {
        DCCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DC.accent)
                if items.isEmpty {
                    Text("Aucun").font(.caption).foregroundStyle(DC.textSec)
                } else {
                    ForEach(items, id: \.self) { n in
                        Text("• \(n)").font(.system(size: 13, design: .monospaced))
                    }
                }
            }
        }
    }
}

// MARK: - Crashs
struct CrashesView: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button { manager.loadCrashReports() } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
            }
            if manager.crashReports.isEmpty {
                EmptyState(title: "Aucun crash", icon: "checkmark.shield.fill", message: "Tout va bien : aucun rapport de crash trouvé.")
            } else {
                ForEach(manager.crashReports) { c in
                    DCCard {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DC.amber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text(c.date.formatted()).font(.caption).foregroundStyle(DC.textSec)
                            }
                            Spacer()
                            Button("Ouvrir") { NSWorkspace.shared.open(c.url) }.buttonStyle(ChipButtonStyle())
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Activité
struct ActivityView: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if manager.activityLog.isEmpty {
                EmptyState(title: "Aucune activité", icon: "list.bullet")
            } else {
                ForEach(manager.activityLog) { a in
                    HStack(alignment: .top, spacing: 12) {
                        Text(a.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DC.textSec)
                            .frame(width: 52, alignment: .leading)
                        Text(a.message).font(.system(size: 13, design: .rounded))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(DC.border)
                }
            }
        }
    }
}
