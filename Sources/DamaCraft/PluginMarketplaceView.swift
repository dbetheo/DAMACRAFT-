import SwiftUI

struct PluginMarketplaceView: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Picker("Type", selection: $manager.marketplaceMode) {
                    Text("Plugins").tag("plugin")
                    Text("Mods").tag("mod")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                if let v = manager.detectedMCVersion {
                    StatusPill(text: "Minecraft \(v)", color: DC.cyan, icon: "checkmark.circle.fill")
                        .help("Les résultats sont filtrés pour cette version")
                }
                Spacer()
            }

            HStack(spacing: 10) {
                TextField(
                    manager.marketplaceMode == "mod" ? "Lithium, Fabric API, Ferrite Core…" : "LuckPerms, EssentialsX, WorldEdit…",
                    text: $manager.pluginQuery
                )
                .dcField()
                .onSubmit { manager.searchPlugins() }

                Button {
                    manager.searchPlugins()
                } label: {
                    Label("Rechercher", systemImage: "magnifyingglass")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(manager.pluginSearching)
            }

            HStack(spacing: 8) {
                if manager.pluginSearching || manager.downloadingPlugin { ProgressView().controlSize(.small) }
                if !manager.pluginStatus.isEmpty {
                    Text(manager.pluginStatus)
                        .font(.caption)
                        .foregroundStyle(DC.textSec)
                }
            }

            if manager.serverDirectory == nil {
                EmptyState(title: "Aucun serveur", icon: "puzzlepiece.extension.fill", message: "Sélectionne un serveur pour y installer des plugins.")
            } else if manager.pluginResults.isEmpty && manager.pluginStatus.isEmpty {
                EmptyState(
                    title: "Cherche un plugin",
                    icon: "puzzlepiece.extension.fill",
                    message: "Les fichiers sont téléchargés depuis Modrinth dans le dossier plugins/ (ou mods/) du serveur."
                )
            }

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(manager.pluginResults) { p in
                    DCCard {
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.title ?? p.slug ?? "Projet")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                if let d = p.description {
                                    Text(d)
                                        .font(.caption)
                                        .foregroundStyle(DC.textSec)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 10) {
                                    if let a = p.author {
                                        Label(a, systemImage: "person").font(.caption2).foregroundStyle(DC.textTer)
                                    }
                                    if let dl = p.downloads {
                                        Label(dl.formatted(), systemImage: "arrow.down.circle").font(.caption2).foregroundStyle(DC.textTer)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                manager.downloadPlugin(p)
                            } label: {
                                Label("Installer", systemImage: "arrow.down.to.line")
                            }
                            .buttonStyle(PrimaryButtonStyle(color: DC.green))
                            .disabled(manager.downloadingPlugin || manager.serverDirectory == nil)
                        }
                    }
                }
            }
        }
    }
}
