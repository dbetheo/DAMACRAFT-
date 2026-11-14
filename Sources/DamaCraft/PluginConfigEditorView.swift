import SwiftUI

struct PluginConfigEditorView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var filter = ""

    private var filtered: [PropertyEntry] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return manager.properties }
        return manager.properties.filter {
            $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("server.properties").font(.title2.bold())
                Spacer()
                if manager.propertiesDirty {
                    Text("Modifications non enregistrées")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Recharger") { manager.loadServerProperties() }
                    .buttonStyle(.bordered)
                Button("Enregistrer") { manager.saveServerProperties() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(!manager.propertiesDirty || manager.serverDirectory == nil)
            }

            TextField("Filtrer une propriété…", text: $filter)
                .textFieldStyle(.roundedBorder)

            if manager.serverDirectory == nil {
                ContentUnavailableView("Aucun serveur", systemImage: "slider.horizontal.3",
                                       description: Text("Sélectionne un serveur pour éditer server.properties."))
            } else if manager.properties.isEmpty {
                ContentUnavailableView("Fichier introuvable", systemImage: "doc",
                                       description: Text("Aucun server.properties dans ce dossier. Démarre une fois le serveur pour le générer."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filtered) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.key)
                                        .font(.system(.body, design: .monospaced).weight(.medium))
                                    Spacer()
                                }
                                if let c = entry.comment, !c.isEmpty {
                                    Text(c).font(.caption2).foregroundStyle(.secondary)
                                }
                                TextField(entry.key, text: Binding(
                                    get: { entry.value },
                                    set: { manager.updateProperty(key: entry.key, value: $0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(minHeight: 420)
            }
        }
    }
}
