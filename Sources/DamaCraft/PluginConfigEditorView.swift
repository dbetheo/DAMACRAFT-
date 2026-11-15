import SwiftUI

/// Éditeur de server.properties.
struct PluginConfigEditorView: View {
    @EnvironmentObject private var manager: ProcessManager
    @State private var filter = ""

    private var filtered: [PropertyEntry] {
        let q = filter.lowercased()
        return q.isEmpty ? manager.properties : manager.properties.filter {
            $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Filtrer les propriétés…", text: $filter)
                    .dcField()
                    .frame(maxWidth: 320)
                Spacer()
                Button { manager.loadServerProperties() } label: { Label("Recharger", systemImage: "arrow.clockwise") }
                    .buttonStyle(ChipButtonStyle())
                Button { manager.saveServerProperties() } label: { Label("Enregistrer", systemImage: "square.and.arrow.down") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!manager.propertiesDirty)
            }

            if manager.serverDirectory == nil {
                EmptyState(title: "Aucun serveur", icon: "slider.horizontal.3")
            } else if manager.properties.isEmpty {
                EmptyState(
                    title: "Pas de server.properties",
                    icon: "slider.horizontal.3",
                    message: "Le fichier est créé au premier démarrage du serveur."
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filtered) { e in
                        row(e)
                    }
                }
            }
        }
    }

    private func row(_ e: PropertyEntry) -> some View {
        let isBool = e.value == "true" || e.value == "false"
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.key).font(.system(size: 13, weight: .medium, design: .monospaced))
                if let c = e.comment, !c.isEmpty {
                    Text(c).font(.caption2).foregroundStyle(DC.textTer).lineLimit(2)
                }
            }
            Spacer()
            if isBool {
                Toggle("", isOn: Binding(
                    get: { e.value == "true" },
                    set: { manager.updateProperty(key: e.key, value: $0 ? "true" : "false") }
                ))
                .labelsHidden()
            } else {
                TextField(e.key, text: Binding(
                    get: { e.value },
                    set: { manager.updateProperty(key: e.key, value: $0) }
                ))
                .dcField()
                .frame(width: 260)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DC.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DC.border, lineWidth: 1))
    }
}
