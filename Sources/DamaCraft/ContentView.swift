import SwiftUI
import AppKit

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, create
    case console, logs, players, security
    case plugins, pluginConfigs, properties, files
    case worlds, backups, crashes
    case activity, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Tableau de bord"
        case .create: return "Créer un serveur"
        case .console: return "Console"
        case .logs: return "Logs"
        case .players: return "Joueurs"
        case .security: return "Sécurité"
        case .plugins: return "Marketplace"
        case .pluginConfigs: return "Configs plugins"
        case .properties: return "server.properties"
        case .files: return "Fichiers"
        case .worlds: return "Mondes"
        case .backups: return "Sauvegardes"
        case .crashes: return "Crashs"
        case .activity: return "Activité"
        case .settings: return "Paramètres"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "Vue d'ensemble et contrôle du serveur"
        case .create: return "Paper, Spigot, Purpur ou Vanilla en quelques clics"
        case .console: return "Console en direct et envoi de commandes"
        case .logs: return "Contenu de logs/latest.log"
        case .players: return "Joueurs connectés et actions rapides"
        case .security: return "Whitelist, opérateurs et bannissements"
        case .plugins: return "Plugins et mods depuis Modrinth"
        case .pluginConfigs: return "Éditeur des fichiers .yml de vos plugins"
        case .properties: return "Réglages du fichier server.properties"
        case .files: return "Contenu du dossier du serveur"
        case .worlds: return "Mondes, datapacks et sauvegarde rapide"
        case .backups: return "Sauvegardes manuelles et automatiques"
        case .crashes: return "Rapports de crash du serveur"
        case .activity: return "Historique des actions de l'app"
        case .settings: return "Java, mémoire, notifications, apparence"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .create: return "plus.app.fill"
        case .console: return "terminal.fill"
        case .logs: return "doc.text.fill"
        case .players: return "person.2.fill"
        case .security: return "lock.shield.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        case .pluginConfigs: return "doc.badge.gearshape"
        case .properties: return "slider.horizontal.3"
        case .files: return "folder.fill"
        case .worlds: return "globe.europe.africa.fill"
        case .backups: return "archivebox.fill"
        case .crashes: return "exclamationmark.triangle.fill"
        case .activity: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    static let groups: [(String, [AppSection])] = [
        ("GÉNÉRAL", [.dashboard, .create]),
        ("SERVEUR", [.console, .logs, .players, .security]),
        ("CONTENU", [.plugins, .pluginConfigs, .properties, .files]),
        ("DONNÉES", [.worlds, .backups, .crashes]),
        ("SYSTÈME", [.activity, .settings]),
    ]
}

struct ContentView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var selection: AppSection = .dashboard
    @State private var profileToRemove: ServerProfile?

    var body: some View {
        // Applique le thème d'accent avant le rendu des vues enfants.
        let _ = DC.apply(manager.settings.accentTheme)
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topBar
                Divider().overlay(DC.border)
                ScrollView(showsIndicators: false) {
                    content
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(DC.bg)
        .preferredColorScheme(.dark)
        .tint(DC.accent)
        .toggleStyle(.switch)
        .confirmationDialog(
            "Retirer ce serveur de la liste ?",
            isPresented: Binding(
                get: { profileToRemove != nil },
                set: { if !$0 { profileToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Retirer de la liste", role: .destructive) {
                if let p = profileToRemove { manager.removeProfile(p.id) }
                profileToRemove = nil
            }
            Button("Annuler", role: .cancel) { profileToRemove = nil }
        } message: {
            Text("Les fichiers du serveur restent sur ton disque. Seule l'entrée dans DamaCraft est supprimée.")
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            serversList
            Rectangle().fill(DC.border).frame(height: 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AppSection.groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.0)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(DC.textTer)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 3)
                            ForEach(group.1) { section in
                                navItem(section)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            footer
        }
        .frame(width: 236)
        .background(
            ZStack {
                Color.black.opacity(0.38)
                LinearGradient(colors: [DC.accent.opacity(0.08), .clear], startPoint: .top, endPoint: .center)
            }
        )
    }

    private var brand: some View {
        HStack(spacing: 11) {
            AppLogo(size: 42)
                .shadow(color: DC.accent.opacity(0.45), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("DamaCraft")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("SERVER CONTROL")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(DC.textSec)
            }
        }
        .padding(.horizontal, 18)
        // Laisse la place aux boutons de fenêtre (titre masqué).
        .padding(.top, 40)
        .padding(.bottom, 18)
    }

    private var serversList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SERVEURS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(DC.textTer)
                Spacer()
                Button {
                    manager.addServer()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DC.accent)
                        .padding(5)
                        .background(DC.accentDim)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Ajouter un dossier de serveur existant")
            }
            .padding(.horizontal, 18)

            if manager.profiles.isEmpty {
                Text("Aucun serveur")
                    .font(.caption)
                    .foregroundStyle(DC.textSec)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            } else {
                ForEach(manager.profiles) { p in
                    serverRow(p)
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func serverRow(_ p: ServerProfile) -> some View {
        let active = manager.activeProfileID == p.id
        let live = active && manager.isRunning
        return HStack(spacing: 6) {
            Button {
                manager.selectProfile(p.id)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(live ? DC.green : Color.white.opacity(0.2))
                        .frame(width: 7, height: 7)
                        .shadow(color: live ? DC.green.opacity(0.7) : .clear, radius: 4)
                    Text(p.name)
                        .font(.system(size: 13, weight: active ? .semibold : .regular, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(active ? DC.accentDim : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(active ? Color.white : DC.textSec)

            if active {
                Button {
                    profileToRemove = p
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DC.textSec)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Retirer de la liste")
            }
        }
        .padding(.horizontal, 8)
    }

    private func navItem(_ section: AppSection) -> some View {
        let on = selection == section
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = section }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(on ? DC.accent : DC.textSec)
                Text(section.title)
                    .font(.system(size: 13, weight: on ? .semibold : .medium, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(on ? DC.accentDim : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(on ? DC.accent.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Color.white : Color.white.opacity(0.65))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.isRunning ? DC.green : Color.gray.opacity(0.5))
                .frame(width: 7, height: 7)
                .shadow(color: manager.isRunning ? DC.green.opacity(0.6) : .clear, radius: 4)
            Text(manager.isRunning ? "En ligne" : "Hors ligne")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DC.textSec)
            Spacer()
            Text("v\(AppInfo.version)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DC.textTer)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(selection.subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(DC.textSec)
            }

            Spacer()

            if manager.isRunning {
                StatusPill(text: "Santé \(manager.healthScore)", color: healthColor, icon: "heart.fill")
                    .help("Score calculé d'après le CPU, la RAM et les TPS")
            }
            StatusPill(text: manager.statusLabel, color: manager.isRunning ? DC.green : DC.textSec)

            Button {
                if manager.isRunning { manager.stopGracefully() } else { manager.startServer() }
            } label: {
                Label(manager.isRunning ? "Arrêter" : "Démarrer", systemImage: manager.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: manager.isRunning ? DC.red : DC.green))
            .disabled(manager.serverDirectory == nil)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.2))
    }

    private var healthColor: Color {
        let score = manager.healthScore
        return score > 70 ? DC.green : (score > 40 ? DC.amber : DC.red)
    }

    // MARK: - Content
    @ViewBuilder
    private var content: some View {
        switch selection {
        case .dashboard: DashboardView(selection: $selection)
        case .create: CreateServerView()
        case .console: ConsoleView()
        case .logs: LogsView()
        case .players: PlayersView()
        case .security: SecurityView()
        case .plugins: PluginMarketplaceView()
        case .pluginConfigs: PluginConfigsView()
        case .properties: PluginConfigEditorView()
        case .files: FilesView()
        case .worlds: WorldsView()
        case .backups: BackupsView()
        case .crashes: CrashesView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }
}
