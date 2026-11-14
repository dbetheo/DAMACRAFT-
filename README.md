# DamaCraft

Gestionnaire macOS de serveurs Minecraft en SwiftUI.

## Version 0.7.0

### Nouveautés majeures
- **Multi-serveurs** : ajoute, sélectionne et gère plusieurs dossiers serveur
- **Éditeur server.properties** : lecture / modification / sauvegarde avec filtre
- **Marketplace plugins** : recherche Modrinth + installation directe dans `plugins/`
- **Notifications macOS** : joueur join/leave, démarrage / arrêt serveur
- Monitoring CPU / RAM réel + jauge %
- Parsing console (joueurs, TPS)
- Onglets Joueurs, Console, Fichiers, Sauvegardes
- Paramètres JVM par serveur + auto-restart crash
- Support jars : server, paper, purpur, fabric, forge

## Build
```bash
swift build -c release
```

## Installation / Mise à jour
```bash
chmod +x Installer-DamaCraft.command
./Installer-DamaCraft.command
```

L’app s’installe dans `~/Applications/DamaCraft.app`.

> Optionnel : place `DamaCraft.icns` à la racine pour l’icône.

macOS 14+ requis. Swift Package Manager.
