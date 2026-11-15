import SwiftUI
import AppKit

/// Arrête proprement le serveur Minecraft quand on quitte l'app (⌘Q, menu…),
/// au lieu de laisser une JVM orpheline tourner en arrière-plan.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let manager = ProcessManager.current, manager.isRunning else { return .terminateNow }
        manager.stopForQuit {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct DamaCraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = ProcessManager()

    var body: some Scene {
        Window("DamaCraft", id: "main") {
            ContentView()
                .environmentObject(manager)
                .frame(
                    minWidth: manager.settings.compactMode ? 920 : 1100,
                    minHeight: manager.settings.compactMode ? 620 : 760
                )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Serveur") {
                Button("Démarrer") { manager.startServer() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Arrêter") { manager.stopGracefully() }
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Button("Redémarrer") { manager.restartServer() }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Divider()
                Button("save-all") { manager.sendCommand("save-all") }
                    .keyboardShortcut("s", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarContent(manager: manager)
        } label: {
            Image(systemName: manager.isRunning ? "cube.fill" : "cube")
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var manager: ProcessManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(manager.serverName).font(.headline)
        Text(manager.isRunning ? "En ligne — \(manager.players.count) joueur(s)" : "Arrêté")
        if manager.isRunning {
            Text(String(format: "CPU %.0f%% · RAM %.0f Mo · Santé %d", manager.cpuPercent ?? 0, manager.memoryMB ?? 0, manager.healthScore))
                .font(.caption)
        }
        Divider()
        Button("Ouvrir DamaCraft") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(manager.isRunning ? "Arrêter" : "Démarrer") {
            if manager.isRunning { manager.stopGracefully() } else { manager.startServer() }
        }
        .disabled(manager.serverDirectory == nil)
        Button("Redémarrer") { manager.restartServer() }
            .disabled(manager.serverDirectory == nil)
        Button("Copier IP:port") { manager.copyConnectionString() }
        Divider()
        Button("Quitter DamaCraft") { NSApplication.shared.terminate(nil) }
    }
}
