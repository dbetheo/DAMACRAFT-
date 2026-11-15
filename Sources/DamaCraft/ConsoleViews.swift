import SwiftUI
import AppKit

/// Affichage de lignes de console avec défilement automatique vers le bas.
/// `revision` change à chaque nouvelle ligne (le nombre de lignes, lui, peut rester constant
/// quand le tampon est plein, ce qui cassait l'auto-scroll de l'ancienne version).
struct ConsoleLogView: View {
    let lines: [String]
    let revision: Int
    var height: CGFloat? = nil
    var minHeight: CGFloat = 200
    var fontSize: CGFloat = 12

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundStyle(consoleColor(line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(12)
            }
            .frame(minHeight: height ?? minHeight, maxHeight: height)
            .dcPanel()
            .onChange(of: revision) { _, _ in scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = lines.indices.last {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}

struct CommandBar: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("›")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(DC.accent)
                TextField("Commande serveur (flèches ↑ ↓ pour l'historique)", text: $manager.commandInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit { manager.sendCommand() }
                    .onKeyPress(.upArrow) { manager.historyUp(); return .handled }
                    .onKeyPress(.downArrow) { manager.historyDown(); return .handled }
            }
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DC.border, lineWidth: 1))

            Button {
                manager.sendCommand()
            } label: {
                Label("Envoyer", systemImage: "paperplane.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!manager.isRunning && !manager.settings.rconEnabled)
        }
    }
}

struct ConsoleView: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(manager.consoleLines.count) ligne(s)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(DC.textSec)
                Spacer()
                Button {
                    manager.clearConsole()
                } label: {
                    Label("Effacer", systemImage: "trash")
                }
                .buttonStyle(ChipButtonStyle())
            }
            ConsoleLogView(lines: manager.consoleLines, revision: manager.consoleRevision, minHeight: 480)
            CommandBar()
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var level = 0

    private var filtered: [String] {
        var out = manager.logLines
        if level == 1 {
            out = out.filter {
                let l = $0.lowercased()
                return l.contains("error") || l.contains("exception") || l.contains("severe")
            }
        } else if level == 2 {
            out = out.filter { $0.lowercased().contains("warn") }
        }
        if !manager.logFilter.isEmpty {
            out = out.filter { $0.localizedCaseInsensitiveContains(manager.logFilter) }
        }
        return Array(out.suffix(600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Picker("Niveau", selection: $level) {
                    Text("Tout").tag(0)
                    Text("Erreurs").tag(1)
                    Text("Alertes").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
                .labelsHidden()
                TextField("Filtrer…", text: $manager.logFilter)
                    .dcField()
                    .frame(maxWidth: 240)
                Spacer()
                Button { manager.loadLatestLog() } label: { Label("Recharger", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
                Button { manager.archiveLogs() } label: { Label("Archiver", systemImage: "archivebox") }
                    .buttonStyle(ChipButtonStyle())
            }
            if manager.serverDirectory == nil {
                EmptyState(title: "Aucun serveur", icon: "doc.text")
            } else if manager.logLines.isEmpty {
                EmptyState(title: "Aucun log", icon: "doc.text", message: "Le fichier logs/latest.log apparaît après le premier démarrage.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(consoleColor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
                .frame(minHeight: 480)
                .dcPanel()
            }
        }
    }
}
