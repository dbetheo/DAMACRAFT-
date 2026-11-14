#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="DamaCraft"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
VERSION="0.7.0"

echo "=== DamaCraft ${VERSION} — compilation et installation ==="
cd "$PROJECT_DIR"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift introuvable. Installe Xcode puis relance."
  exit 1
fi

echo "→ Compilation release…"
swift build -c release

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/${APP_NAME}" "$CONTENTS/MacOS/${APP_NAME}"

ICON_KEY=""
if [ -f "$PROJECT_DIR/DamaCraft.icns" ]; then
  cp "$PROJECT_DIR/DamaCraft.icns" "$CONTENTS/Resources/DamaCraft.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>DamaCraft</string>"
else
  echo "⚠ Pas d'icône DamaCraft.icns — installation sans icône custom."
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>DamaCraft</string>
<key>CFBundleIdentifier</key><string>fr.dama.damacraft</string>
<key>CFBundleVersion</key><string>${VERSION}</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleExecutable</key><string>DamaCraft</string>
<key>CFBundlePackageType</key><string>APPL</string>
${ICON_KEY}
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

chmod +x "$CONTENTS/MacOS/${APP_NAME}"
mkdir -p "$HOME/Applications"
echo "✓ Installé : $APP_DIR"
open "$APP_DIR"
