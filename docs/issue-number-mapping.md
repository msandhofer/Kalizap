# Issue-Number Mapping (DerFluesterer/Fluesterclon → Kalizap)

Beim Repo-Transfer am 2026-05-05 hat `gh issue transfer` zwei Source-Issues nicht uebernommen, wodurch sich die Nummerierung verschoben hat. Diese Tabelle dokumentiert das Mapping fuer kuenftige Referenzen aus Commit-Messages und externen Verlinkungen.

## Nicht transferiert
- Source #17 "Pipeline-Aktivierung sollte bei Model-Fehler Hotkey trotzdem starten können" (closed)
- Source #30 "WhisperKit Instanz-Caching für schnellen Modellwechsel" (closed)

## Mapping

| Source (Fluesterclon) | Dest (Kalizap) | Verschiebung |
|---|---|---|
| #1–#16 | #1–#16 | 0 |
| #17 | — (verloren) | — |
| #18–#29 | #17–#28 | -1 |
| #30 | — (verloren) | — |
| #31–#51 | #29–#49 | -2 |

### Wichtige Issue-Referenzen aus Commit-Messages

| Commit-Ref | Source | Dest |
|---|---|---|
| `feat(#44)` (API-Key-Storage) | #44 | **#42** |
| `chore(#45)` (LICENSE/Sparkle-Removal) | #45 | **#43** |
| `feat(#46)` (Update-Check) | #46 | **#44** |
| `fix(#49)` (LLM-Timeout) | #49 | **#47** |
| `fix(#50)` (LLM-Korrektur) | #50 | **#48** |

Hinweis: GitHub renderiert `#N`-Verlinkungen aus Commit-Messages weiter — sie zeigen jetzt aber auf andere Issues als urspruenglich gemeint. Für menschliche Leser, die Commit-History nachvollziehen, dient diese Tabelle als Schluessel.
