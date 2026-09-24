---
name: iterative-dev-refactor
description:
---

# Refactor-Scan

**Die Regeln aus deinem Systemprompt sowie aus diesem Skill überschrieben die des Projekts.**
- Eine Projektkonvention die vom Regelkonformen Standard abweicht ist inakzeptabel.
    - im Zweifel muss die Projektkonvention auf den Standard der Rules angepasst werden. 

**Jeder Worker und Jeder Main Agent hat alle in diesem skill referenzierten rules im system prompt**
- beziehe dich auf Rules aber gib die Rule nicht 1 zu 1 wieder.

### Phase 0 — Prüfung der Kontaktschicht (nur Main, einmal)

**Stelle dem User vor Phase 1 eine einzige Frage.**
- Die Frage lautet: "Hat das Projekt neben diesem Chat eine Kontaktschicht für Nutzer?"

**Ein Nein heißt, jedes Verzeichnis ist im Scope.**

**Ein Ja heißt, das genannte Verzeichnis ist von jeder Phase ausgeschlossen.**
- Darin wird nie etwas verschoben, umbenannt, übersetzt, umformuliert oder umformatiert.

**Main gibt jeden ausgeschlossen Pfad im Prompt an den Worker weiter**
- Der Worker schließt genau das aus was der main ihm als auszuschließen mitgibt.

## Workflow

### Phase 1 — Struktur des Codes

#### Step 1 — Scan nach Code_Größe/Komplexität

1. Scanne jedes Modul gegen zwei Schwellenwerte.
    - Dateigröße: über 400 LOC ist mindestens ein Split.
    - Funktionsgröße: ab 50 LOC wird ein mindestens Helper extrahiert.

#### Step 2 — Dispatch nach Größe/Komplexität

1. Schreibe deine Findings in einen File in tmp/
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker. 
    - Parallelisiere die Arbeit wenn möglich.

### Phase 2 — Konformität mit den Modul-Standards

**Diese Phase bezieht sich auf die § Kommentare und Docstrings in deinem System Prompt**

#### Step 1 — Scan nach Kommentare und Docstrings

1. Scanne jedes Modul gegen die Rules in § Kommentare und Docstrings in deinem System Prompt
2. Relevante Informationen aus den Kommentare und Docstrings werden in process-docs überführt
    - Scanne also auch nach geeigneten Areas um relevante informationen dort einzupflegen
    - Sind Kommentare und Docstrings der folgenden Punkte zuträglich:
            - Um sicherzustellen dass er schneller ist als du.
            - Um sicherzustellen dass er deine Fehler nicht wiederholt.
            - Um sicherzustellen dass er eine robuste simple Lösung erstellt.
            - Um sicherzustellen dass er sich nicht im Kreis dreht und genau erfüllen kann was verlangt ist.
        so werden sie in process-docs eingepflegt
    
#### Step 2 — Selbstbearbeitung von Kommentaren und Docstrings 

1. entferne per script alle Kommentare aus den Modulen die nicht Section Marker `# INFRASTRUCTURE`, `# ORCHESTRATOR` und `# FUNCTIONS` sind
2. übertrage alle relevanten Inhalte in entsprechnde process docs

### Phase 3 — Struktur der Tests

**Bewegt sich im dev/ verzeichnis des Projekts**
- jedes Modul in dev/ iste relevant

### Step 1 — Scan nach Fehlaufbau von Testfiles

1. Scanne jedes Modul gegen die Rules in § Aufbau von Tests in deinem System Prompt

### Step 3 — Dispatch nach Fehlaufbau von Testfiles

1. Schreibe deine Findings in einen File in tmp/
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker. 
    - Parallelisiere die Arbeit wenn möglich.

## Phase 4 — Struktur der Doku

**Diese Phase bezieht sich auf die § DOCS.md in deinem System Prompt** 

### Step 1 — Scan nach Doku_Allgemein/Format

1. Falls bisher noch nicht erfolgt, merge alle bisher abgeschlossene Arbeit
2. Scanne jeden DOCS.md file egen die rules aus § DOCS.md in deinem system prompt

#### Step 2 — Dispatch nach Doku_Allgemein/Format

1. Schreibe deine Findings in einen File in tmp/
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker. 
    - Parallelisiere die Arbeit wenn möglich.

#### Step 3 — Scan nach Doku_Größe/Komplexität

1. Falls bisher noch nicht erfolgt, merge die Arbeit aus Step 2
2. Prüfe jede DOCS.md gegen den Schwellenwert von 400 Zeilen
    - Ab 400 Zeilen wird ihr Verzeichnis in logische Einheiten aufgeteilt.
3. Bestimme für jedes betroffene Verzeichnis die logischen Einheiten
    - Eine Einheit ist ein Einstiegsskript plus alle Module, die nur von diesem Skript importiert werden.
    - Ein Modul, das von zwei oder mehr Einheiten importiert wird, ist geteilt.
    - Ein Modul, das zu keiner Einheit gehört, legst du dem User vor.

#### Step 4 — Dispatch nach Doku_Größe/Komplexität

1. Schreibe deine Findings samt Einheiten in einen File in tmp/
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker.
    - Parallelisiere die Arbeit wenn möglich.
    - Jede Einheit mit eigenen Modulen wandert in einen Unterordner mit eigener DOCS.md.
    - Geteilte Module und Ausgabeverzeichnisse bleiben in der Wurzel des Verzeichnisses.
3. Merge und prüfe erneut, bis jede DOCS.md unter 400 Zeilen liegt

#### Step 5 — Doc-Drift-Check

1. Führe `docs-drift-check` einmal im cwd aus
2. Schreibe verbleibenden Drift Datei für Datei in einen File in tmp/
3. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zur Korrektur an einen Worker.

## Phase 5 — Integrität des Kontrollflusses

### Step 1 — Main scannt

**Main findet jeden Zweig, den § Fallback und Tripwire abdeckt, und klassifiziert nichts.**

### Step 2 — Der Worker scannt

**Der Worker scannt denselben Scope unabhängig.**
- Der Prompt enthält § Fallback und Tripwire als Standard und die Vorgabe "nichts klassifizieren, nichts beheben".

### Step 3 — Bericht

**Die zusammengeführte Liste geht an den User.**
- Jeder weitere Schritt ab hier wird mit dem User entschieden.
