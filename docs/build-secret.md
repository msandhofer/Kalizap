# Build-Time App-Secret

Dieses Dokument richtet sich an Mitwirkende und an den Projekt-Maintainer.

## Zweck

Das App-Secret ist ein zufälliger 32-Byte-Wert, der beim Build in das Binary einkompiliert wird. Es fließt zusammen mit `IOPlatformUUID` und `NSUserName()` in die HKDF-Key-Derivation der verschlüsselten Credentials-Datei ein (`~/Library/Application Support/DerFluisterer/<account>.enc`).

Genaue Funktionsweise und Bedrohungsmodell: siehe [security.md](security.md).

## Speicherort

- **Pfad:** `Sources/DerFluistererApp/AppSecret.swift`
- **Gitignore-Status:** ignoriert (siehe `.gitignore`)
- **Format:** Swift-Datei mit einem `enum AppSecret { static let bytes: Data = ... }`

## Erstmalige Generierung

Beim ersten Klonen des Repositories existiert `AppSecret.swift` nicht. Der Build schlägt dann mit einem Linker-/Compile-Fehler `cannot find 'AppSecret' in scope` fehl.

Erzeugen via:

```bash
./Scripts/generate-app-secret.sh
```

Das Script legt die Datei genau einmal an. Ein zweiter Aufruf scheitert bewusst hart, um stille Secret-Rotation zu verhindern.

## Sichern

Der Maintainer (Release-Pipeline) MUSS das Secret sichern, z. B. als separaten Eintrag im Passwortmanager. Alternativ: verschlüsseltes Off-Site-Backup der Datei.

Warum: Bei Verlust des Secrets können alle bestehenden Release-Nutzer ihre verschlüsselten Credentials-Dateien nicht mehr entschlüsseln — sie müssen ihren API-Key neu eingeben. Für einzelne Entwickler-Builds ist das unkritisch, für offizielle Releases ist es Breaking.

## Secret rotieren (Notfall)

Nur im echten Kompromittierungsfall. Folgen:

1. `rm Sources/DerFluistererApp/AppSecret.swift`
2. `./Scripts/generate-app-secret.sh`
3. Neues Release bauen.
4. Release-Notes: "Alle Nutzer müssen ihren API-Key neu eintragen."

## Fork-Workflow

Wer einen Fork baut, führt `./Scripts/generate-app-secret.sh` einmal aus. Das erzeugt ein eigenes, vom offiziellen Release unabhängiges Secret. Dateien offizieller Release-Nutzer können damit nicht entschlüsselt werden — das ist gewollt.

## Was NIEMALS tun

- Secret als Compiler-Flag (`-D APP_SECRET=...`) übergeben — landet in Build-Logs, CI-Outputs, Xcode-Build-Settings-Dumps.
- Secret in ein öffentliches CI-Secret-Store eines Public-Repos legen und `set -x` im Script aktivieren.
- `AppSecret.swift` ins Git pushen (erzwungen durch `.gitignore`).
- In `print` / `NSLog` / Fehlermeldungen ausgeben.
