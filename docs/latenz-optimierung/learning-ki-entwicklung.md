# Learning: Wenn die KI eine Simulation baut, die nicht die Realitaet abbildet

## Was passiert ist

Ich entwickle eine macOS Dictation-App mit KI-Unterstuetzung (Claude Code).
Die App nimmt Sprache auf, transkribiert sie mit Whisper und fuegt den Text
per Cmd+V ein. Das Ziel: die Latenz zwischen Loslassen des Aufnahmeknopfes
und dem eingefuegten Text reduzieren.

Die KI analysierte die Pipeline, identifizierte vier Engpaesse und schlug
Optimierungen vor. Fuer den groessten Engpass (StreamWait: ~1300ms Wartezeit
auf den finalen Whisper-Decode) entwarf die KI eine Loesung mit spekulativem
Caching — das Audio nach der letzten Sprechpause wird waehrend der Aufnahme
schon vorab dekodiert und gecacht. Beim Stop muss dann nicht mehr neu
dekodiert werden.

## Was die KI gebaut hat

Die KI baute eine deterministische Simulation der Streaming-Pipeline als
CLI-Tool, fuehrte einen automatisierten Parameter-Sweep ueber 40
Konfigurationen x 10 Testdateien durch (400 Einzellaeufe, ~3 Stunden
Laufzeit) und lieferte eine Pareto-Analyse mit konkreter Empfehlung. Die
Ergebnisse sahen hervorragend aus: StreamWait von 700ms auf 0ms reduziert.

## Was dann wirklich passierte

Die Optimierung wurde in die echte App eingebaut. Ergebnis: **Null
messbarer Nutzen.** StreamWait blieb bei ~1000ms.

Die Ursache: Die Simulation modellierte die Nebenlaefigkeit nicht. In der
echten App laeuft die Audioaufnahme WAEHREND Whisper dekodiert. Jeder
Decode dauert ~800ms — und in dieser Zeit kommen 800ms neues Audio dazu.
Wenn der Nutzer Stop drueckt, ist mit hoher Wahrscheinlichkeit gerade ein
Decode aktiv. Die App MUSS auf dessen Abschluss warten, weil das Ergebnis
den transkribierten Text enthaelt.

Die Simulation behandelte Decodes als waeren sie instant. Es gab keinen
Zustand "Decode laeuft waehrend neues Audio reinkommt". Deshalb zeigte die
Simulation falsche StreamWait-Werte — der Kern des Problems wurde nicht
modelliert.

## Das Learning

**Eine KI kann beeindruckende Tooling-Infrastruktur bauen — Simulationen,
Parameter-Sweeps, Pareto-Analysen — und trotzdem auf einem falschen Modell
der Realitaet aufbauen.** Die Ergebnisse sehen plausibel und professionell
aus, aber sie bilden nicht ab, was tatsaechlich passiert.

Die Loesung: **Nach dem Bauen einer Simulation muss ein automatisierter
Abgleich mit dem realen System stattfinden**, bevor Stunden in Sweeps und
Analysen investiert werden. Ein einzelner Vergleich — Simulation-Output
gegen echtes App-Log — haette den Fehler in Minuten aufgedeckt.

Das gilt nicht nur fuer KI-generierte Simulationen, sondern fuer jede
Modellbildung: Die billigste Pruefung ist immer "stimmt mein Modell mit
der Realitaet ueberein?" — und die sollte zuerst kommen.

## Was trotzdem funktioniert hat

Nicht alles war umsonst. Der zweite Optimierungsbereich (Insert-Delay:
Clipboard-Restore-Wartezeit) wurde mit einem simplen automatisierten Test
validiert — direkt am echten System, ohne Simulation. Ergebnis: 400ms
Einsparung, sofort verifiziert und produktiv.

Die Lektion: **Je naeher der Test am realen System ist, desto
zuverlaessiger die Ergebnisse.**
