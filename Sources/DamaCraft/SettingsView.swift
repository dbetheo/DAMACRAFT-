import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var manager: ProcessManager

    private static let recommendedJVMFlags =
        "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+DisableExplicitGC -XX:+PerfDisableSharedMem"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            about
            appearance
            if manager.activeProfile != nil {
                eula
                java
                memory
                notifications
                rcon
                discord
                reliability
                paper
            }
            profiles
        }
    }

    // MARK: Sections
    private var about: some View {
        DCCard {
            HStack(spacing: 16) {
                AppLogo(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DamaCraft")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Version \(AppInfo.version) · gestionnaire de serveurs Minecraft pour macOS")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(DC.textSec)
                }
                Spacer()
                Button {
                    if let url = URL(string: "https://github.com/\(AppInfo.repo)/releases") { NSWorkspace.shared.open(url) }
                } label: { Label("Versions sur GitHub", systemImage: "arrow.up.right.square") }
                    .buttonStyle(ChipButtonStyle())
            }
        }
    }

    private var appearance: some View {
        group("Apparence", icon: "paintpalette.fill") {
            if manager.activeProfile != nil {
                HStack(spacing: 10) {
                    Text("Couleur d'accent").font(.system(size: 13, design: .rounded))
                    Spacer()
                    ForEach(AccentTheme.allCases) { theme in
                        let selected = manager.settings.accentTheme == theme.rawValue
                        Button {
                            var s = manager.settings
                            s.accentTheme = theme.rawValue
                            manager.settings = s
                        } label: {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.white.opacity(selected ? 0.95 : 0), lineWidth: 2).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .help(theme.label)
                    }
                }
                Toggle("Mode compact (fenêtre plus petite)", isOn: manager.binding(\.compactMode))
                    .toggleStyle(.switch)
            } else {
                Text("Ajoute ou crée un serveur pour régler l'apparence (les réglages sont enregistrés par serveur).")
                    .font(.caption).foregroundStyle(DC.textSec)
            }
        }
    }

    private var eula: some View {
        group("EULA Minecraft", icon: "checkmark.seal.fill") {
            HStack {
                Image(systemName: manager.eulaAccepted ? "checkmark.seal.fill" : "xmark.seal")
                    .foregroundStyle(manager.eulaAccepted ? DC.green : DC.amber)
                Text(manager.eulaAccepted ? "Acceptée" : "Non acceptée : le serveur ne démarrera pas")
                    .font(.system(size: 13, design: .rounded))
                Spacer()
                if !manager.eulaAccepted {
                    Button("Accepter l'EULA") { manager.acceptEULA() }.buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var java: some View {
        group("Java", icon: "cup.and.saucer.fill") {
            Picker("Exécutable", selection: manager.binding(\.javaPath)) {
                Text("Automatique (le plus récent)").tag("")
                ForEach(manager.javaInstalls) { j in
                    Text(j.label).tag(j.path)
                }
            }
            if manager.javaInstalls.isEmpty {
                Text("Aucun JDK détecté. Installe un JDK (Temurin 21 ou plus), puis redétecte.")
                    .font(.caption).foregroundStyle(DC.amber)
            }
            HStack {
                Button { manager.detectJavaInstalls() } label: { Label("Redétecter", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
                Button("Télécharger Temurin") {
                    if let url = URL(string: "https://adoptium.net/temurin/releases/") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(ChipButtonStyle())
            }
        }
    }

    private var memory: some View {
        group("Mémoire et arguments JVM", icon: "memorychip.fill") {
            HStack {
                Text("Min").foregroundStyle(DC.textSec).frame(width: 30, alignment: .leading)
                Slider(value: manager.binding(\.minMemoryGB), in: 0.5...16, step: 0.5)
                Text(String(format: "%.1f Go", manager.settings.minMemoryGB)).frame(width: 60, alignment: .trailing)
            }
            HStack {
                Text("Max").foregroundStyle(DC.textSec).frame(width: 30, alignment: .leading)
                Slider(value: manager.binding(\.maxMemoryGB), in: 1...32, step: 0.5)
                Text(String(format: "%.1f Go", manager.settings.maxMemoryGB)).frame(width: 60, alignment: .trailing)
            }
            if manager.settings.maxMemoryGB < manager.settings.minMemoryGB {
                Text("Le maximum est inférieur au minimum : il sera aligné sur le minimum au démarrage.")
                    .font(.caption).foregroundStyle(DC.amber)
            }
            TextField("Arguments JVM supplémentaires", text: manager.binding(\.extraJVMArgs))
                .dcField()
                .font(.system(size: 12, design: .monospaced))
            HStack {
                Button("Appliquer les flags recommandés") {
                    var s = manager.settings
                    s.extraJVMArgs = Self.recommendedJVMFlags
                    manager.settings = s
                }
                .buttonStyle(ChipButtonStyle())
                Button("Vider") {
                    var s = manager.settings
                    s.extraJVMArgs = ""
                    manager.settings = s
                }
                .buttonStyle(ChipButtonStyle())
            }
        }
    }

    private var notifications: some View {
        group("Notifications", icon: "bell.fill") {
            Toggle("Démarrage et arrêt du serveur", isOn: manager.binding(\.notifyOnServerStartStop))
            Toggle("Connexion d'un joueur", isOn: manager.binding(\.notifyOnPlayerJoin))
            Toggle("Déconnexion d'un joueur", isOn: manager.binding(\.notifyOnPlayerLeave))
        }
    }

    private var rcon: some View {
        group("RCON", icon: "antenna.radiowaves.left.and.right") {
            Toggle("Utiliser RCON quand le serveur n'a pas été lancé par DamaCraft", isOn: manager.binding(\.rconEnabled))
            HStack(spacing: 8) {
                TextField("Hôte", text: manager.binding(\.rconHost)).dcField()
                TextField("Port", value: manager.binding(\.rconPort), format: .number.grouping(.never))
                    .dcField()
                    .frame(width: 90)
            }
            SecureField("Mot de passe RCON", text: manager.binding(\.rconPassword)).dcField()
            HStack {
                Button("Connecter") { manager.rconConnect() }.buttonStyle(ChipButtonStyle())
                Text(manager.rconStatus).font(.caption).foregroundStyle(DC.textSec)
            }
        }
    }

    private var discord: some View {
        group("Discord", icon: "bubble.left.and.bubble.right.fill") {
            TextField("URL du webhook Discord", text: manager.binding(\.discordWebhookURL)).dcField()
            Toggle("Annoncer les connexions et déconnexions", isOn: manager.binding(\.discordNotifyJoinLeave))
            Toggle("Annoncer les plantages", isOn: manager.binding(\.discordNotifyCrash))
        }
    }

    private var reliability: some View {
        group("Fiabilité", icon: "shield.lefthalf.filled") {
            Toggle("Redémarrer automatiquement après un plantage", isOn: manager.binding(\.autoRestartOnCrash))
            Toggle("Watchdog : redémarrer si le serveur ne répond plus", isOn: manager.binding(\.watchdogEnabled))
            if manager.settings.watchdogEnabled {
                Stepper(value: manager.binding(\.watchdogTimeoutMinutes), in: 1...60, step: 1) {
                    Text("Délai sans réponse : \(Int(manager.settings.watchdogTimeoutMinutes)) min")
                        .font(.system(size: 12, design: .rounded))
                }
            }
        }
    }

    private var paper: some View {
        group("Paper", icon: "doc.richtext.fill") {
            Text("Met à jour paper.jar vers le dernier build de la même version de Minecraft. L'ancien fichier est conservé en paper.jar.bak.")
                .font(.caption).foregroundStyle(DC.textSec)
            HStack {
                Button { manager.checkPaperUpdate() } label: { Label("Mettre à jour Paper", systemImage: "arrow.down.circle") }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(manager.paperDownloading || manager.isRunning)
                if manager.paperDownloading { ProgressView().controlSize(.small) }
            }
            if !manager.paperStatus.isEmpty {
                Text(manager.paperStatus).font(.caption).foregroundStyle(DC.textSec)
            }
        }
    }

    private var profiles: some View {
        group("Profils et réseau", icon: "externaldrive.fill") {
            HStack {
                Button { manager.exportProfiles() } label: { Label("Exporter les profils", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ChipButtonStyle())
                Button { manager.importProfiles() } label: { Label("Importer des profils", systemImage: "square.and.arrow.down") }
                    .buttonStyle(ChipButtonStyle())
            }
            Text("L'export n'inclut ni le mot de passe RCON ni l'URL du webhook Discord.")
                .font(.caption).foregroundStyle(DC.textTer)
            Text("IP publique : \(manager.publicIP)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DC.textSec)
        }
    }

    private func group<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        DCCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(DC.accent)
                content()
            }
        }
    }
}
