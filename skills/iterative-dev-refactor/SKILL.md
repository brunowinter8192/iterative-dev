---
name: iterative-dev-refactor
description:
---

# Refactor-Scan

**Die Regeln aus deinem Systemprompt sowie aus diesem Skill überschrieben die des Projekts.**
- Eine Projektkonvention die vom Regelkonformen Standard abweicht ist inakzeptabel.
    - im Zweifel muss die Projektkonvention auf den Standard der Rules angepasst werden. 

### Phase 0 — Prüfung der Kontaktschicht (nur Main, einmal)

**Stelle dem User vor Phase 1 eine einzige Frage.**
- Die Frage lautet: "Hat das Projekt neben diesem Chat eine Kontaktschicht für Nutzer?"

**Ein Nein heißt, jedes Verzeichnis ist im Scope.**

**Ein Ja heißt, das genannte Verzeichnis ist von jeder Phase ausgenommen.**
- Darin wird nie etwas verschoben, umbenannt, übersetzt, umformuliert oder umformatiert.

**Ein Worker stellt diese Frage nie.**
- Main gibt jeden ausgenommenen Pfad im Prompt des Workers mit.
- Der Worker nimmt genau das aus, was der Prompt nennt, und nicht mehr.

## Workflow

### Phase 1

#### Step 1 — Scan

**Main scannt jedes Modul gegen die zwei Größen-Schwellenwerte.**
- Dateigröße: über 400 LOC ist ein Split.
- Funktionsgröße: ab 50 LOC wird ein Helper extrahiert, ab 100 LOC ist es ein hartes Ziel.

#### Step 2 — Dispatch

**Der Worker teilt entlang der Verantwortungen auf, die er findet, und Main benennt keine Zielmodule.**
- Nach dem Merge folgt die Gegenprüfung durch einen frischen Worker.

### Phase 2 — Konformität mit den Modul-Standards

#### Step 1 — Den Standard lesen

**Der Code-Standard für Worker wird bei jedem Lauf gelesen.**
- Main liest `shared-rules/global/code-standards`, zieht die konkreten Standards heraus und prüft jedes Modul.

#### Step 2 — Scan

**Main scannt pro Datei, und jeder Docstring und jeder Kommentar ist ein Verstoß.**
- `ast.get_docstring` auf dem Modul-Knoten und auf jedem `FunctionDef`, `AsyncFunctionDef` und `ClassDef`.
- `tokenize.COMMENT` für jedes Kommentar-Token, ohne den Shebang und die drei Section Marker.
   - Ein `#` in einem String-Literal ist kein Kommentar, ein einfacher Test auf den Zeilenanfang meldet es aber als einen.

#### Step 3 — Triage

**Main prüft jeden Treffer gegen die process-docs und die `DOCS.md`.**
- Ein Treffer, der dort schon abgedeckt ist, wird gelöscht.
- Jeder andere Treffer wird in die eigene datierte Datei des Autors unter `process-docs/<area>/` verschoben und dann gelöscht.

#### Step 4 — Dispatch

**Der Worker verschiebt und löscht, und er entscheidet nichts.**
- Der Prompt enthält im selben Lauf auch die Überarbeitung der `DOCS.md` des Verzeichnisses nach § DOCS.md-Format.
   - Alles, was gekürzt wird, um das Format zu erreichen, kommt wörtlich in dieselbe process-docs-Datei, unter einer einzigen Überschrift `## Salvage from <path>`.
- Nach dem Merge folgt die Gegenprüfung durch einen frischen Worker.

### Phase 3 — Struktur der Tests

**Die Tests des Projekts tragen die Testing-Regel, sonst zeigt die Regel keine Wirkung.**
- Ein neuer Test kopiert das Muster der Tests, die schon im Projekt liegen.
- Eine sequentielle Test-Suite im Projekt erzeugt deshalb die nächste sequentielle Test-Suite.

#### Step 1 — Den Standard lesen

**Der Testing-Standard wird bei jedem Lauf gelesen.**
- Main liest `shared-rules/global/testing`, § Aufbau von Tests, und zieht die konkreten Standards heraus.

### Step 2 — Scan

**Main scannt jede Testdatei und jeden Test-Runner im Scope.**
- Zu den Test-Runnern gehören das Runner-Modul, das eine Testdatei importiert, und jedes Skript, das Testdateien startet, etwa ein Skript in `package.json` oder eine Shell-Schleife.

**Jeder Verstoß gegen einen dieser Kernsätze ist ein Treffer.**
- § Aufbau von Tests (**Unabhängige Testfälle laufen parallel.**)
   - Typische Fundstelle ist eine Schleife, die jeden Fall abwartet, oder ein `for f in verify-*.mjs`.
- § Aufbau von Tests (**Ein Strang bricht beim ersten Fehlschlag automatisch ab.**)
- § Aufbau von Tests (**Die Zahl der Wiederholungen steht vor dem Lauf fest.**)

### Step 3 — Dispatch

**Der Worker baut die Tests und Runner nach dem Standard um.**
- Der Prompt enthält § Aufbau von Tests als Standard und die Trefferliste Datei für Datei.
- Der Worker belegt, dass die umgebauten Tests weiter bestehen, und zeigt die Laufzeit vorher und nachher.
- Nach dem Merge folgt die Gegenprüfung durch einen frischen Worker.

## Phase 4 — Struktur der Doku

### Step 1 — Prüfung

**Phase 3 ist gemergt, bevor die Prüfung läuft, und wird jetzt gemergt, falls nicht.**

**Jede `DOCS.md` im Scope wird gegen den Schwellenwert von 400 Zeilen geprüft.**
- Ab 400 Zeilen wird ihr Verzeichnis in Unterordner pro Einheit aufgeteilt.
- Unter 400 Zeilen bleibt das Verzeichnis flach.

**Eine Einheit ist ein Einstiegsskript plus die Module, die nur über die Import-Hülle dieses Skripts erreicht werden.**
- Ein Einstiegsskript ist ein Modul, das kein anderes Modul im Verzeichnis importiert.
- Ein Modul, das von zwei oder mehr Import-Hüllen erreicht wird, ist geteilt.
- Ein Modul, das von keiner Import-Hülle erreicht wird, hat keinen Besitzer, und der User entscheidet darüber.
- `__init__.py` wird übersprungen.

### Step 2 — Plan

**Main plant den Split, bevor irgendeine Datei verschoben wird.**
- Eine Einheit mit einem oder mehr exklusiven Modulen wandert nach `<unit>/`, benannt nach ihrem Einstiegsskript ohne das Nummern-Präfix.
- Eine Einheit ohne exklusives Modul bleibt als einzelne Datei in der Area-Wurzel, ebenso jedes geteilte Modul.
- Das Einstiegsskript behält seine Nummer.

**Ausgabeverzeichnisse bleiben in der Area-Wurzel und wandern nie.**
- `md/`, `png/`, `csv/`, `data/` und `npz/` sind der Bus der Area und werden über Einheiten hinweg gelesen.

**Pfadauflösung, die von der Tiefe abhängt, wird vor jedem Verschieben entfernt.**
- Jeder `parents[N]`-Walk auf `__file__` wird durch eine Auflösung ersetzt, die unabhängig von der Tiefe des Moduls ist.
- Jeder Ausgabepfad ist an der Area-Wurzel verankert, nie am eigenen Verzeichnis des Moduls.

**Jeder neue Unterordner bekommt seine eigene `DOCS.md`.**
- Die `DOCS.md` der Area behält Role, Flow, die geteilten Module, die Einheiten aus einer einzelnen Datei und eine Zeile pro Unterordner.

### Step 3 — Dispatch

**Der Worker führt den Plan aus.**
- Nach dem Merge prüft Main erneut. Jede `DOCS.md` unter 400 Zeilen schließt den Step.

### Step 4 — Doc-Drift-Check

**Worker aktualisieren die berührte DOCS.md zusammen mit ihrer Änderung.**

**Ein einziger Drift-Check schließt den autonomen Teil ab.**
- Nachdem Step 3 gemergt ist, läuft `docs-drift-check` einmal im cwd.
- Verbleibender Drift geht an einen Worker, danach geht die konsolidierte Zusammenfassung an den User, und Phase 5 beginnt.

**Die Drift-Befunde gehören Datei für Datei in den Worker-Prompt.**

## Phase 5 — Integrität des Kontrollflusses

### Step 1 — Main scannt

**Main findet jeden Zweig, den § Fallback und Tripwire abdeckt, und klassifiziert nichts.**

### Step 2 — Der Worker scannt

**Der Worker scannt denselben Scope unabhängig.**
- Der Prompt enthält § Fallback und Tripwire als Standard und die Vorgabe "nichts klassifizieren, nichts beheben".

### Step 3 — Bericht

**Die zusammengeführte Liste geht an den User.**
- Jeder weitere Schritt ab hier wird mit dem User entschieden.
