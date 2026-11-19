#!/bin/bash
set -euo pipefail

# Wraps `swift build -c release --target KalizapApp` in einer macOS .app-Bundle
# fuer die Distribution via Homebrew Cask. Output unter dist/.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

if [ ! -f "Sources/KalizapApp/AppSecret.swift" ]; then
    echo "ERROR: Sources/KalizapApp/AppSecret.swift fehlt."
    echo "Lauf einmalig: ./Scripts/generate-app-secret.sh"
    exit 1
fi

if [ ! -f "Sources/CDeepFilter/lib/libdf.a" ]; then
    echo "ERROR: Sources/CDeepFilter/lib/libdf.a fehlt (Git-LFS-Asset)."
    echo "Lauf: git lfs pull"
    exit 1
fi

VERSION=$(plutil -extract CFBundleShortVersionString raw Sources/KalizapApp/Info.plist)
echo "=== Build Kalizap.app v${VERSION} ==="
echo ""

echo "Step 1/5: swift build -c release --product KalizapApp"
swift build -c release --product KalizapApp

# Bin-Pfad von SwiftPM erfragen statt hartkodieren (aendert sich je nach Build-System/Toolchain)
BUILD_DIR="$(swift build -c release --product KalizapApp --show-bin-path)"
EXEC="$BUILD_DIR/KalizapApp"
RESOURCE_BUNDLE="$BUILD_DIR/Kalizap_KalizapApp.bundle"

if [ ! -f "$EXEC" ]; then
    echo "ERROR: Executable nicht gefunden: $EXEC"
    exit 1
fi

if [ ! -d "$RESOURCE_BUNDLE" ]; then
    echo "ERROR: Resource-Bundle nicht gefunden: $RESOURCE_BUNDLE"
    exit 1
fi

echo ""
echo "Step 2/5: Erstelle Kalizap.app"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/Kalizap.app"

mkdir -p "$DIST_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXEC" "$APP_DIR/Contents/MacOS/Kalizap"
cp Sources/KalizapApp/Info.plist "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "Kalizap" "$APP_DIR/Contents/Info.plist"
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"

echo ""
echo "Step 3/5: Codesignatur mit Self-Signed Cert"
# Self-signed Identity statt Adhoc, damit TCC-Permissions (Mikrofon,
# Bedienungshilfen) ueber `brew upgrade --cask kalizap` persistieren.
# Der Cert-Hash ist Teil der Designated Requirement, die in der TCC-DB
# pro App gespeichert wird — solange wir mit demselben Cert signieren,
# erkennt macOS auf User-Maschinen Updates als "dieselbe App".
# Bei Verlust des Certs siehe Backup-Hinweis in docs/release-process.md.
SIGN_IDENTITY="${KALIZAP_SIGN_IDENTITY:-Kalizap Code Signing}"

if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "ERROR: Code-Signing-Identity '$SIGN_IDENTITY' nicht in Keychain gefunden."
    echo "Pruefen mit: security find-identity -v -p codesigning"
    echo "Setup-Anleitung: docs/release-process.md (Abschnitt Self-Signed Cert)"
    exit 1
fi

codesign --force --sign "$SIGN_IDENTITY" --deep "$APP_DIR"

echo ""
echo "Step 4/5: Verifikation"
codesign --verify --strict "$APP_DIR"
echo "  Signatur mit '$SIGN_IDENTITY' ok"

echo ""
echo "Step 5/5: ZIP packen"
ZIP_NAME="Kalizap-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

(cd "$DIST_DIR" && rm -f "$ZIP_NAME" && zip -r -q "$ZIP_NAME" Kalizap.app)

SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

echo ""
echo "=== Done ==="
echo "  App:    $APP_DIR"
echo "  ZIP:    $ZIP_PATH"
echo "  SHA256: $SHA256"
echo ""
echo "Cask-Update (Tap-Repo Casks/kalizap.rb):"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA256\""
