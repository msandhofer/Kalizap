# Security-Architektur: API-Key-Speicherung

## Überblick

Der Anthropic-API-Key wird als AES-GCM-verschlüsselte Datei im Application-Support-Verzeichnis des Nutzers abgelegt (`~/Library/Application Support/Kalizap/anthropic-api-key.enc`). Der Verschlüsselungs-Schlüssel wird zur Laufzeit aus drei Quellen abgeleitet:

1. `IOPlatformUUID` (stabile Geräte-ID)
2. `NSUserName()` (macOS-User-Account-Name)
3. App-Secret (ins Binary einkompilierter 32-Byte-Zufallswert)

Keiner dieser Inputs wird in der Credentials-Datei selbst gespeichert.

## Threat-Modell

### Wovor wir schützen

| Szenario | Schutz? | Warum |
|---|---|---|
| Ungezielte Stealer-Malware scannt Home-Verzeichnis nach Klartext-Pattern (`sk-ant-...`) | ✓ | Datei enthält nur Ciphertext, keine Muster |
| Time-Machine-Backup-Festplatte gestohlen | ✓ | Key ist an IOPlatformUUID des Quellgeräts gebunden |
| App-Support-Ordner auf anderen Mac kopiert | ✓ | Gleicher Grund — UUID des Zielgeräts ist anders |
| Datei mitgepatched in Git-Repo (Unfall) | ✓ | Angreifer kennt weder UUID noch App-Secret |

### Wovor wir NICHT schützen

| Szenario | Kein Schutz | Warum |
|---|---|---|
| Angreifer hat vollen Zugriff auf das laufende/eingeschaltete Gerät | ✗ | Kann UUID, Username, Binary und Datei gleichzeitig lesen — kein Verfahren, das ohne Nutzer-Interaktion entschlüsselt, kann das abwehren |
| Gezielte Reverse-Engineering-Angriffe | ✗ | App-Secret ist im Binary via `strings` extrahierbar; Source-Code ist öffentlich |
| Keylogger, Memory-Dump zur Laufzeit | ✗ | Entschlüsselter Key liegt während der App-Laufzeit im RAM |

## Verfahrensdetails

### Dateiformat

```
[32 Byte Salt][AES.GCM.SealedBox.combined]
```

`SealedBox.combined` = `[12 Byte Nonce][Ciphertext][16 Byte GCM-Tag]`

Keine Magic-Bytes, keine Version-Header → Datei sieht wie reiner Zufall aus.

### Key-Derivation (HKDF-SHA256)

```
ikm  = UTF8(IOPlatformUUID) + 0x00 + UTF8(NSUserName()) + 0x00 + AppSecret
salt = 32 Byte random pro Schreibvorgang
info = UTF8(accountName)          // z. B. "anthropic-api-key"
key  = HKDF<SHA256>(ikm, salt, info, 32 Byte)
```

Der `0x00`-Separator zwischen den String-Inputs verhindert Ambiguität (z. B. UUID="AB", User="CD" vs. UUID="ABCD", User="" würden ohne Separator denselben IKM ergeben).

### Warum HKDF, nicht PBKDF2/scrypt/Argon2?

HKDF ist die richtige Wahl für **High-Entropy-Inputs**:

| Input | Effektive Entropie |
|---|---|
| IOPlatformUUID | ~122 Bit (UUIDv4) |
| NSUserName() | niedrig, aber irrelevant neben den anderen |
| AppSecret | 256 Bit |

Kombinierte Entropie ≥256 Bit → der Derivation-Key ist bereits brute-force-resistent ohne künstliche Rechenkosten. PBKDF2/Argon2 sind dazu da, User-gewählte Passwörter (niedrige Entropie) durch slow hashing aufzuwerten. Unsere Inputs brauchen das nicht.

### Warum kein System-Keychain?

Der macOS-System-Keychain hätte eine konzeptuell saubere Lösung (Secure Enclave + TouchID-Gate) geboten, setzt aber eine stabile Code-Signatur-Identität voraus (Designated Requirement über Apple Developer ID). Ohne Apple Developer Program:

- Keychain-ACL wird bei jedem unsignierten App-Update invalidiert → User-Dialog `„möchte auf Schlüsselbund zugreifen"` mit System-Admin-Passwort-Eingabe bei jedem App-Start.
- UX-Wortlaut suggeriert „Zugriff auf alle Passwörter" → untragbar für Endnutzer.

## Akzeptierte Trade-offs

- **App-Secret liegt im Binary** → via `strings` extrahierbar. Das ist bewusst in Kauf genommen — die Hürde für gezielte Angreifer ist damit niedrig. Der Schutz wirkt primär gegen ungezielte Stealer-Malware, die nicht jedes Binary nach Secrets durchsucht.
- **Kein User-Prompt, keine Biometrie** → Bequemlichkeit hat hier Vorrang, da Biometrie ohne Secure Enclave in unsigniertem Kontext Security-Theater wäre.
- **Kein Migration-Pfad vom alten Keychain** → Bestandsnutzer müssen ihren API-Key einmal neu eintragen. Vertretbar bei aktuell sehr kleiner Nutzerbasis; sauberer Bruch ohne Legacy-Code.

## Vergleich mit anderen Tools

**Claude Code CLI** (offizielle Anthropic-Lösung): nutzt für Pay-per-Use-API-Keys die Environment-Variable `ANTHROPIC_API_KEY`, die typischerweise in `.zshrc` (Klartext) liegt. Unsere Lösung bietet in diesem Szenario (unsigniert, ohne Developer Program) echten Schutzgewinn gegenüber Anthropics eigenem Default.
