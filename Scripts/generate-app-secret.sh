#!/usr/bin/env bash
# Generiert einmalig Sources/KalizapApp/AppSecret.swift mit 32 Byte Random-Secret.
# Scheitert hart, wenn die Datei bereits existiert — keine stille Rotation.
# Siehe docs/build-secret.md.

set -euo pipefail

# Script vom Projekt-Root aus aufrufbar machen
cd "$(dirname "$0")/.."

TARGET="Sources/KalizapApp/AppSecret.swift"

if [ -f "$TARGET" ]; then
  echo "FEHLER: $TARGET existiert bereits. Nicht überschrieben." >&2
  echo "Soll das Secret absichtlich rotiert werden: Datei manuell löschen und Script neu ausführen." >&2
  echo "Achtung: Rotation invalidiert alle bestehenden verschlüsselten Credentials." >&2
  exit 1
fi

SECRET=$(openssl rand -base64 32)

cat > "$TARGET" <<EOF
// Auto-generiert von Scripts/generate-app-secret.sh. NICHT committen.
// Siehe docs/build-secret.md für Hintergrund und Backup-Pflicht.
import Foundation

enum AppSecret {
    static let bytes: Data = Data(base64Encoded: "$SECRET")!
}
EOF

echo "OK: $TARGET generiert."
echo "WICHTIG: Dieses Secret sichern (z. B. Passwortmanager-Eintrag)."
echo "         Bei Verlust müssen alle Nutzer ihren API-Key neu eintragen."
