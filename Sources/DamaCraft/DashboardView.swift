import SwiftUI
import AppKit
import Charts

struct DashboardView: View {
    @EnvironmentObject private var manager: ProcessManager
    @Binding var selection: AppSection
    @State private var confirmKill = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if manager.profiles.isEmpty {
                welcome
            } else {
                hero
                if manager.javaInstalls.isEmpty { javaBanner }
                metrics
                performance
                quickCommands
                templates
                liveConsole
            }
        }
        .confirmationDialog("Forcer l'arrêt du serveur ?", isPresented: $confirmKill, titleVisibility: .visible) {
            Button("Forcer l'arrêt", role: .destructive) { manager.forceKill() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le monde n'est pas sauvegardé proprement : utilise « Arrêter » si possible.")
        }
    }

    // MARK: Welcome (aucun serveur)
    private var welcome: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                AppLogo(size: 96)
                    .shadow(color: DC.accent.opacity(0.5), radius: 24, y: 8)
                Text("Bienvenue dans DamaCraft")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Crée un serveur Minecraft en quelques clics, ou ajoute un dossier de serveur que tu as déjà.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(DC.textSec)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button {
                        selection = .create
                    } label: {
                        Label("Créer un serveur", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        manager.addServer()
                    } label: {
                        Label("Ajouter un dossier existant", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(ChipButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [DC.accent.opacity(0.18), DC.surface], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(DC.border, lineWidth: 1))

            if manager.javaInstalls.isEmpty { javaBanner } else { javaOK }
        }
    }

    private var javaOK: some View {
        DCCard {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(DC.green)
                Text("Java détecté : \(manager.javaInstalls.first?.label ?? "")")
                    .font(.system(size: 13, design: .rounded))
                Spacer()
            }
        }
    }

    private var javaBanner: some View {
        DCCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DC.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aucun JDK Java détecté")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Minecraft a besoin de Java pour fonctionner. Installe un JDK récent (21 ou plus), puis clique sur « Redétecter ».")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(DC.textSec)
                }
                Spacer()
                Button("Télécharger Temurin") {
                    if let url = URL(string: "https://adoptium.net/temurin/releases/") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(ChipButtonStyle())
                Button("Redétecter") { manager.detectJavaInstalls() }
                    .buttonStyle(ChipButtonStyle())
            }
        }
    }

    // MARK: Hero
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DC.accent.opacity(0.95), DC.accentDeep.opacity(0.8), Color(red: 0.08, green: 0.06, blue: 0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Circle().fill(Color.white.opacity(0.07)).frame(width: 240, height: 240).offset(x: 520, y: -90)
            Circle().fill(DC.cyan.opacity(0.12)).frame(width: 150, height: 150).offset(x: 640, y: 70)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("SERVEUR MINECRAFT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.6))
                    if let v = manager.pingInfo.online ? manager.pingInfo.version : manager.detectedMCVersion, !v.isEmpty {
                        Text(v)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(manager.serverName)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label(manager.connectionString, systemImage: "network")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Button {
                        manager.copyConnectionString()
                    } label: {
                        Text("Copier")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 10) {
                    Button { manager.startServer() } label: { Label("Démarrer", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButtonStyle(color: DC.green))
                        .disabled(manager.isRunning || manager.serverDirectory == nil)
                    Button { manager.stopGracefully() } label: { Label("Arrêter", systemImage: "stop.fill") }
                        .buttonStyle(ChipButtonStyle())
                        .disabled(!manager.isRunning)
                    Button { manager.restartServer() } label: { Label("Redémarrer", systemImage: "arrow.clockwise") }
                        .buttonStyle(ChipButtonStyle())
                        .disabled(manager.serverDirectory == nil)
                    Button { confirmKill = true } label: { Label("Kill", systemImage: "xmark.octagon") }
                        .buttonStyle(ChipButtonStyle(tint: DC.red))
                        .disabled(!manager.isRunning)
                    Button { manager.pingServer(); manager.checkPortStatus() } label: { Label("Ping", systemImage: "wifi") }
                        .buttonStyle(ChipButtonStyle())
                }
                Text(manager.serverStatusMessage)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            .padding(26)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: DC.accent.opacity(0.22), radius: 22, y: 8)
    }

    // MARK: Metrics
    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            metricCard("Joueurs", "\(manager.players.count)/\(manager.maxPlayers)", "person.2.fill", DC.cyan)
            metricCard("CPU", manager.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "—", "cpu", DC.accent)
            metricCard("RAM", manager.memoryMB.map { String(format: "%.0f Mo", $0) } ?? "—", "memorychip", .orange)
            metricCard("TPS", manager.reportedTPS ?? "—", "gauge.with.needle.fill", DC.green)
            metricCard("Ping", manager.pingInfo.online ? "\(manager.pingInfo.latencyMs) ms" : "—", "wifi", .pink)
            metricCard("Port \(manager.serverPort)", manager.portStatus, "network", DC.amber)
        }
    }

    private func metricCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .padding(7)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DC.textSec)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DC.surface)
        .clipShape(RoundedRectangle(cornerRadius: DC.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DC.radius, style: .continuous).stroke(DC.border, lineWidth: 1))
    }

    // MARK: Performance
    @ViewBuilder
    private var performance: some View {
        if manager.metricHistory.count > 1 {
            let top = max(100, (manager.metricHistory.map(\.cpu).max() ?? 0).rounded(.up))
            DCCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Performances")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        legendDot(DC.cyan, "CPU %")
                        legendDot(DC.accent, "RAM %")
                    }
                    Chart {
                        ForEach(manager.metricHistory) { s in
                            LineMark(x: .value("Heure", s.date), y: .value("Valeur", s.cpu), series: .value("Métrique", "CPU"))
                                .foregroundStyle(by: .value("Métrique", "CPU"))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Heure", s.date), y: .value("Valeur", s.ramPercent), series: .value("Métrique", "RAM"))
                                .foregroundStyle(by: .value("Métrique", "RAM"))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartForegroundStyleScale(["CPU": DC.cyan, "RAM": DC.accent])
                    .chartYScale(domain: 0...top)
                    .chartLegend(.hidden)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 160)
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(DC.textSec)
        }
    }

    // MARK: Quick commands / templates
    private var quickCommands: some View {
        DCCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Commandes rapides")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(manager.commandPresets) { p in
                        Button {
                            manager.sendCommand(p.command)
                        } label: {
                            Label(p.title, systemImage: p.icon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ChipButtonStyle())
                        .disabled(!manager.isRunning)
                    }
                }
            }
        }
    }

    private var templates: some View {
        DCCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Templates")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("Modifie la mémoire et server.properties")
                        .font(.caption)
                        .foregroundStyle(DC.textTer)
                }
                HStack(spacing: 8) {
                    ForEach(manager.templates) { t in
                        Button(t.name) { manager.applyTemplate(t) }
                            .buttonStyle(ChipButtonStyle())
                            .help(t.detail)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: Live console
    private var liveConsole: some View {
        DCCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Console")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Button("Plein écran") { selection = .console }
                        .buttonStyle(ChipButtonStyle())
                }
                ConsoleLogView(
                    lines: Array(manager.consoleLines.suffix(80)),
                    revision: manager.consoleRevision,
                    height: 190,
                    fontSize: 11
                )
                CommandBar()
            }
        }
    }
}
