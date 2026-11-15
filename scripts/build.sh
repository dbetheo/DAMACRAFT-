#!/bin/bash
# Construit DamaCraft.app (binaire universel arm64 + x86_64) et, au choix, un .dmg.
#   ./scripts/build.sh app       -> dist/DamaCraft.app
#   ./scripts/build.sh dmg       -> dist/DamaCraft.app + dist/DamaCraft-<version>.dmg (défaut)
#   ./scripts/build.sh install   -> compile et installe dans ~/Applications
# Version : variable d'environnement VERSION (ex. VERSION=1.2.0 ./scripts/build.sh dmg)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
MODE="${1:-dmg}"
VERSION="${VERSION:-1.0.0}"
APP_NAME="DamaCraft"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift introuvable. Installe Xcode (ou les Command Line Tools) puis réessaie." >&2
  exit 1
fi

echo "==> Compilation $APP_NAME $VERSION (universal)…"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assemblage de $APP_NAME.app…"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f "$ROOT/DamaCraft.icns" ]; then
  cp "$ROOT/DamaCraft.icns" "$APP/Contents/Resources/DamaCraft.icns"
else
  echo "⚠ DamaCraft.icns introuvable : l'app n'aura pas d'icône."
fi

# Signature « ad hoc » : nécessaire pour que l'app se lance sur Apple Silicon.
# (Ce n'est PAS une signature Developer ID : voir README pour le premier lancement.)
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "    signature ad hoc OK"

case "$MODE" in
  app)
    echo "✓ $APP"
    ;;
  install)
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    cp -R "$APP" "$HOME/Applications/$APP_NAME.app"
    xattr -dr com.apple.quarantine "$HOME/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
    echo "✓ Installé : $HOME/Applications/$APP_NAME.app"
    open "$HOME/Applications/$APP_NAME.app"
    ;;
  dmg)
    echo "==> Création du .dmg…"
    STAGE="$DIST/dmg-stage"
    DMG="$DIST/$APP_NAME-$VERSION.dmg"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cat > "$STAGE/LISEZ-MOI.txt" <<'TXT'
DamaCraft — premier lancement

1. Glisse DamaCraft dans le dossier Applications.
2. Ouvre DamaCraft. Si macOS affiche « Apple ne peut pas vérifier… » :
   - Ouvre Réglages Système > Confidentialité et sécurité,
   - descends jusqu'au message sur DamaCraft et clique sur « Ouvrir quand même ».
   (L'app n'est pas encore notarisée par Apple ; cette étape n'est nécessaire qu'une fois.)
3. Il faut un JDK Java installé pour lancer un serveur Minecraft : https://adoptium.net
TXT
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG"
    rm -rf "$STAGE"
    (cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
    echo "✓ $DMG"
    ;;
  *)
    echo "Mode inconnu : $MODE (app | dmg | install)" >&2
    exit 2
    ;;
esac
