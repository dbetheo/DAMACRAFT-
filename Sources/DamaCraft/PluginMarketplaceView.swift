import SwiftUI

struct PluginMarketplaceView: View {
    @EnvironmentObject private var manager: ProcessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Marketplace Plugins").font(.title2.bold())
            Text("Recherche sur Modrinth (plugins Bukkit / Spigot / Paper / Purpur).")
                .foregroundStyle(.secondary)

            HStack {
                TextField("Ex: LuckPerms, Essentials, WorldEdit…", text: $manager.pluginQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { manager.searchPlugins() }
                Button("Rechercher") { manager.searchPlugins() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(manager.pluginSearching || manager.pluginQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if manager.pluginSearching {
                ProgressView("Recherche en cours…")
            } else if !manager.pluginStatus.isEmpty {
                Text(manager.pluginStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if manager.pluginResults.isEmpty && !manager.pluginSearching {
                ContentUnavailableView(
                    "Aucun résultat",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Lance une recherche pour trouver des plugins.")
                )
                .frame(minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(manager.pluginResults) { project in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.title ?? project.slug ?? "Plugin")
                                        .font(.headline)
                                    if let desc = project.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    HStack(spacing: 10) {
                                        if let author = project.author {
                                            Text(author).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        if let dl = project.downloads {
                                            Label("\(dl)", systemImage: "arrow.down.circle")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Button {
                                    manager.downloadPlugin(project)
                                } label: {
                                    if manager.downloadingPlugin {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Installer", systemImage: "arrow.down.circle.fill")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(manager.downloadingPlugin || manager.serverDirectory == nil)
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }

            if manager.serverDirectory == nil {
                Text("⚠ Sélectionne un serveur pour pouvoir installer des plugins.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
