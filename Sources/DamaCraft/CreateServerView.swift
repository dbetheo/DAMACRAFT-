import SwiftUI
import AppKit

struct CreateServerView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var serverName = "MonServeur"
    @State private var parentPath = ""
    @State private var software: ServerSoftware = .paper
    @State private var selectedVersion = ""
    @State private var versions: [String] = []
    @State private var loadingVersions = false
    @State private var creating = false
    @State private var status = ""
    @State private var progress: Double = 0
    @State private var minRAM: Double = 1
    @State private var maxRAM: Double = 2
    @State private var acceptsEULA = false
    @State private var autoStartAfterCreation = true
    @State private var versionsRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Choisis le dossier parent, le type de serveur et la version. DamaCraft télécharge le jar et prépare les fichiers de base.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            // Location
            groupCard("Emplacement") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("Nom du serveur", text: $serverName)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            pickFolder()
                        } label: {
                            Label(parentPath.isEmpty ? "Choisir le dossier…" : "Changer", systemImage: "folder")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(DC.accent.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DC.accent)
                    }

                    if parentPath.isEmpty {
                        Text("Sélectionne le dossier où créer le serveur (ex. Documents/MinecraftServers).")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dossier parent")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                            Text(parentPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                            Text("→ \(parentPath)/\(sanitizedName)/")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(DC.accent)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            // Software
            groupCard("Logiciel") {
                HStack(spacing: 10) {
                    ForEach(ServerSoftware.allCases) { sw in
                        softwareChip(sw)
                    }
                }
                Text(software.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            // Version
            groupCard("Version Minecraft") {
                if loadingVersions {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Chargement des versions…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else if versions.isEmpty {
                    Text("Impossible de charger les versions. Vérifie ta connexion.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Réessayer") { loadVersions() }
                        .font(.caption)
                } else {
                    Picker("Version", selection: $selectedVersion) {
                        ForEach(versions, id: \.self) { v in
                            Text(v).tag(v)
                        }
                    }
                    .pickerStyle(.menu)

                    // Quick picks for popular / legacy
                    if software == .paper || software == .purpur || software == .spigot {
                        HStack(spacing: 8) {
                            Text("Rapide :").font(.caption).foregroundStyle(.white.opacity(0.4))
                            ForEach(quickVersions, id: \.self) { v in
                                if versions.contains(v) {
                                    Button(v) { selectedVersion = v }
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(selectedVersion == v ? DC.accent.opacity(0.3) : Color.white.opacity(0.06))
                                        .clipShape(Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            // RAM
            groupCard("Mémoire") {
                HStack {
                    Text("Min").foregroundStyle(.white.opacity(0.45))
                    Slider(value: $minRAM, in: 0.5...8, step: 0.5)
                        .tint(DC.accent)
                    Text(String(format: "%.1f Go", minRAM)).frame(width: 55)
                }
                HStack {
                    Text("Max").foregroundStyle(.white.opacity(0.45))
                    Slider(value: $maxRAM, in: 1...16, step: 0.5)
                        .tint(DC.accent)
                    Text(String(format: "%.1f Go", maxRAM)).frame(width: 55)
                }
            }

            // EULA and automatic start
            groupCard("Démarrage") {
                Toggle("J’accepte le contrat Minecraft EULA", isOn: $acceptsEULA)
                    .toggleStyle(.switch)
                Toggle("Démarrer le serveur après sa création", isOn: $autoStartAfterCreation)
                    .toggleStyle(.switch)
                Text("L’acceptation de l’EULA est obligatoire. Java doit être installé sur ce Mac pour démarrer le serveur.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }

            // Create button
            if creating {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress)
                        .tint(DC.accent)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            } else {
                Button {
                    create()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Créer et télécharger")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        canCreate
                        ? LinearGradient(colors: [DC.accent, DC.accentDeep], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: canCreate ? DC.accent.opacity(0.35) : .clear, radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canCreate ? .white : .white.opacity(0.35))
                .disabled(!canCreate)
            }

            if !status.isEmpty && !creating {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.contains("✓") ? DC.green : .orange)
            }

            Text("Spigot officiel est compilé avec BuildTools (Java + Git requis). Paper et Purpur acceptent la plupart des plugins Spigot/Bukkit.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .onAppear { loadVersions() }
        .onChange(of: software) { _, _ in loadVersions() }
    }

    /// Dernière version disponible + quelques classiques.
    private var quickVersions: [String] {
        var list: [String] = []
        if let latest = versions.first { list.append(latest) }
        for v in ["1.21.4", "1.20.4", "1.16.5", "1.12.2", "1.8.8"] where !list.contains(v) { list.append(v) }
        return list
    }

    private var sanitizedName: String {
        let invalid = CharacterSet(charactersIn: "/\\:.*?\"<>|")
        let cleaned = serverName.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "MonServeur" : cleaned
    }

    private var canCreate: Bool {
        !parentPath.isEmpty && !selectedVersion.isEmpty && !loadingVersions &&
        maxRAM >= minRAM && acceptsEULA
    }

    private func softwareChip(_ sw: ServerSoftware) -> some View {
        let on = software == sw
        return Button {
            software = sw
        } label: {
            VStack(spacing: 4) {
                Text(sw.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(sw.short)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(on ? .white.opacity(0.7) : .white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(on ? DC.accent.opacity(0.25) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(on ? DC.accent.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? .white : .white.opacity(0.65))
    }

    private func groupCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(DC.accent)
                .tracking(0.5)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        panel.message = "Dossier où créer le serveur Minecraft"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        parentPath = url.path
    }

    private func loadVersions() {
        loadingVersions = true
        versions = []
        selectedVersion = ""
        versionsRequest += 1
        let token = versionsRequest
        manager.fetchVersions(for: software) { list in
            // Ignore une réponse périmée (changement rapide de logiciel).
            guard token == versionsRequest else { return }
            versions = list
            selectedVersion = list.first ?? ""
            loadingVersions = false
        }
    }

    private func create() {
        creating = true
        progress = 0.05
        status = "Création du dossier…"
        let name = sanitizedName
        manager.createServer(
            name: name,
            parentPath: parentPath,
            software: software,
            version: selectedVersion,
            minRAM: minRAM,
            maxRAM: maxRAM,
            acceptEULA: acceptsEULA,
            autoStart: autoStartAfterCreation
        ) { p, msg in
            progress = p
            status = msg
            if p >= 1.0 {
                creating = false
            }
        }
    }
}

enum ServerSoftware: String, CaseIterable, Identifiable {
    case paper = "Paper"
    case spigot = "Spigot"
    case purpur = "Purpur"
    case vanilla = "Vanilla"

    var id: String { rawValue }
    var short: String {
        switch self {
        case .paper: return "Plugins Spigot"
        case .spigot: return "BuildTools officiel"
        case .purpur: return "Paper+"
        case .vanilla: return "Officiel Mojang"
        }
    }
    var detail: String {
        switch self {
        case .paper: return "Recommandé. Compatible plugins Spigot/Bukkit, performances élevées."
        case .spigot: return "Spigot officiel compilé localement avec BuildTools. Git et Java sont nécessaires ; la compilation peut prendre plusieurs minutes."
        case .purpur: return "Fork de Paper avec plus d’options de gameplay."
        case .vanilla: return "Serveur officiel Mojang, sans plugins."
        }
    }
    var jarName: String {
        switch self {
        case .paper: return "paper.jar"
        case .spigot: return "spigot.jar"
        case .purpur: return "purpur.jar"
        case .vanilla: return "server.jar"
        }
    }
}
