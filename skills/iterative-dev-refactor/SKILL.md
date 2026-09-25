---
name: iterative-dev-refactor
description:
---

# Refactor-Scan

**Fachbegriffe geben nur Kontext, sie begründen nie eine Abweichung von den Rules.**
- Die Rules aus diesem Skill und aus deinem Systemprompt gelten immer vorrangig.
- Ein Fachbegriff hilft dir nur, einen Step gedanklich sinnvoll einzuordnen.
    - Widerspricht dein Trainingswissen zu einem Fachbegriff einer Rule, dann gilt die Rule.

**Die Regeln aus deinem Systemprompt sowie aus diesem Skill überschreiben die des Projekts.**
- Eine Projektkonvention, die vom regelkonformen Standard abweicht, ist inakzeptabel.
    - Im Zweifel muss die Projektkonvention an den Standard der Rules angepasst werden.

**Jedes Refactoring ist eine verhaltenserhaltende Transformation im Sinne von Fowler.**
- Die Struktur ändert sich, das beobachtbare Verhalten nicht.

**Jeder Worker und jeder Main Agent hat alle in diesem Skill referenzierten Rules im Systemprompt.**
- Beziehe dich auf die Rules, aber gib die Rules nicht eins zu eins wieder.

### Phase 0 — Prüfung der Kontaktschicht (nur Main, einmal)

**Stelle dem User vor Phase 1 eine einzige Frage.**
- Die Frage lautet: "Hat das Projekt neben diesem Chat eine Kontaktschicht für Nutzer?"

**Ein Nein heißt, jedes Verzeichnis ist im Scope.**

**Ein Ja heißt, das genannte Verzeichnis ist von jeder Phase ausgeschlossen.**
- Das Verzeichnis gilt als Published Interface.
- Darin wird nie etwas verschoben, umbenannt, übersetzt, umformuliert oder umformatiert.

**Main gibt jeden ausgeschlossenen Pfad im Prompt an den Worker weiter.**
- Der Worker schließt genau das aus, was Main ihm als auszuschließen mitgibt.

## Workflow

### Phase 1 — Struktur des Codes

**Diese Phase folgt dem Single Responsibility Principle.**
- Sie beseitigt die Code Smells Large Module und Long Function über Extract Module und Extract Function.

#### Step 1 — Scan nach Code_Größe/Komplexität

1. Scanne jedes Modul gegen zwei Thresholds.
    - Dateigröße: Über 400 LOC ist mindestens ein Split fällig.
    - Funktionsgröße: Ab 50 LOC wird mindestens ein Helper extrahiert.

#### Step 2 — Dispatch nach Größe/Komplexität

1. Schreibe deine Findings in eine Datei in tmp/.
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker.
    - Parallelisiere die Arbeit, wenn möglich.

### Phase 2 — Konformität mit den Modul-Standards

**Diese Phase bezieht sich auf § Kommentare und Docstrings, § Modulaufbau und § Import-Konvention in deinem Systemprompt.**
- Der Code folgt dem Prinzip Self-documenting Code.
- Die process-docs übernehmen die Rolle von Architecture Decision Records.
- Der Modulaufbau folgt Functional Core, Imperative Shell und der Stepdown Rule.

#### Step 1 — Scan nach Kommentaren und Docstrings

1. Scanne jedes Modul gegen die Rules in § Kommentare und Docstrings in deinem Systemprompt.
2. Relevante Informationen aus den Kommentaren und Docstrings werden in die process-docs überführt.
    - Scanne also auch nach geeigneten Areas, um relevante Informationen dort einzupflegen.
    - Kommentare und Docstrings werden in die process-docs eingepflegt, wenn sie einem der folgenden Punkte dienen:
        - Um sicherzustellen, dass er schneller ist als du.
        - Um sicherzustellen, dass er deine Fehler nicht wiederholt.
        - Um sicherzustellen, dass er eine robuste, simple Lösung erstellt.
        - Um sicherzustellen, dass er sich nicht im Kreis dreht und genau erfüllen kann, was verlangt ist.

#### Step 2 — Selbstbearbeitung von Kommentaren und Docstrings

1. Entferne per Skript alle Kommentare aus den Modulen, die nicht die Section Marker `# INFRASTRUCTURE`, `# ORCHESTRATOR` und `# FUNCTIONS` sind.
2. Übertrage alle relevanten Inhalte in die entsprechenden process-docs.

#### Step 3 — Scan nach Modulaufbau und Imports

1. Scanne jedes Modul gegen die Rules in § Modulaufbau in deinem Systemprompt.
    - Ein typisches Finding ist ein Orchestrator, der selbst rechnet oder filtert, statt nur Funktionen aufzurufen.
2. Scanne jedes Modul gegen die Rules in § Import-Konvention in deinem Systemprompt.
3. Scanne jedes Modul gegen die Rules in § Abhängigkeiten zwischen Modulen in deinem Systemprompt.

#### Step 4 — Dispatch nach Modulaufbau und Imports

1. Schreibe deine Findings in eine Datei in tmp/.
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker.
    - Parallelisiere die Arbeit, wenn möglich.

### Phase 3 — Struktur der Tests

**Diese Phase bewegt sich im dev/-Verzeichnis des Projekts.**
- Jedes Modul in dev/ ist relevant.
- Die Tests folgen den FIRST-Prinzipien und laufen hermetisch.

### Step 1 — Scan nach Fehlaufbau von Testfiles

1. Scanne jedes Modul gegen die Rules in § Aufbau von Tests in deinem Systemprompt.

### Step 2 — Dispatch nach Fehlaufbau von Testfiles

1. Schreibe deine Findings in eine Datei in tmp/.
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker.
    - Parallelisiere die Arbeit, wenn möglich.

## Phase 4 — Struktur der Doku

**Diese Phase bezieht sich auf § DOCS.md in deinem Systemprompt.**

### Step 1 — Scan nach Doku_Allgemein/Format

1. Falls noch nicht erfolgt, merge alle bisher abgeschlossene Arbeit.
2. Scanne jede DOCS.md gegen die Rules aus § DOCS.md in deinem Systemprompt.

#### Step 2 — Dispatch nach Doku_Allgemein/Format

1. Schreibe deine Findings in eine Datei in tmp/.
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker.
    - Parallelisiere die Arbeit, wenn möglich.

#### Step 3 — Scan nach Doku_Größe/Komplexität

1. Falls noch nicht erfolgt, merge die komplette bisherige Arbeit.
2. Prüfe jede DOCS.md gegen den Threshold von 400 Zeilen.
    - Ab 400 Zeilen wird ihr Verzeichnis in separate Ordner aufgeteilt.
3. Bestimme für jedes betroffene Verzeichnis die logischen Einheiten nach Package by Feature, die sich in den separaten Ordnern widerspiegeln.
    - Jede Einheit bekommt einen eigenen Ordner mit ihrem Entry Point und allen Modulen, die nur dieser Entry Point importiert.
    - Ein Modul, das von zwei oder mehr Einheiten importiert wird, bleibt im Root des Verzeichnisses.
    - Ein Modul, das zu keiner Einheit gehört, legst du dem User zur Entscheidung vor.
    - Die Einheiten ergeben sich aus der transitiven Hülle im Import-Graph.
    - Der Split folgt High Cohesion, Low Coupling und dem Common Closure Principle.

#### Step 4 — Dispatch nach Doku_Größe/Komplexität

1. Schreibe deine Findings samt Einheiten in eine Datei in tmp/.
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker.
    - Parallelisiere die Arbeit, wenn möglich.
    - Jeder neue Ordner bekommt eine eigene DOCS.md.
    - Output-Verzeichnisse bleiben im Root des Verzeichnisses.
3. Merge und prüfe erneut, bis jede DOCS.md unter 400 Zeilen liegt.

#### Step 5 — Doc-Drift-Check

**Dieser Step beseitigt Documentation Drift.**

1. Führe `docs-drift-check` einmal im cwd aus.
2. Schreibe den verbleibenden Drift Datei für Datei in eine Datei in tmp/.
3. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zur Korrektur an einen Worker.

### Phase 5 — Integrität des Kontrollflusses

**Diese Phase bezieht sich auf § Fallback und Tripwire in deinem Systemprompt.**
- Diese Phase folgt Fail Fast und YAGNI.
- Das Anti-Pattern ist Error Swallowing hinter einem stillen Fallback.

#### Step 1 — Scan nach Fallbacks und Tripwires

1. Scanne jedes Modul gegen die Rules in § Fallback und Tripwire in deinem Systemprompt.

#### Step 2 — Dispatch nach Fallbacks und Tripwires

1. Schreibe deine Findings in eine Datei in tmp/.
2. Gib den Pfad zu deinen Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker.
    - Parallelisiere die Arbeit, wenn möglich.

### Phase 6 — Vier-Augen-Prinzip

**Diese Phase lässt Phase 1 bis 5 von einem unabhängigen Worker nachprüfen.**
- Diese Phase folgt dem Vier-Augen-Prinzip.

#### Step 1 — Scan durch einen Worker

1. Falls noch nicht erfolgt, merge die komplette bisherige Arbeit.
2. Spawne einen Worker, der diesen Skill von Phase 1 bis 5 vollständig durchgeht.
    - Der Prompt weist den Worker an, den Skill iterative-dev:iterative-dev-refactor zu aktivieren.
    - Der Prompt enthält jeden ausgeschlossenen Pfad aus Phase 0.
    - Der Worker führt nur die Scan-Steps aus, er behebt nichts und spawnt nichts.
3. Der Worker reportet seine Findings nach Ende von Phase 5 an Main.

#### Step 2 — Einschätzung durch Main

1. Prüfe jedes Finding des Workers gegen die Rules aus diesem Skill und aus deinem Systemprompt.
2. Verwirf jedes Finding, das keinen Regelverstoß zeigt.

#### Step 3 — Dispatch nach den Findings des Workers

1. Schreibe die bestätigten Findings in eine Datei in tmp/.
2. Gib den Pfad zu den Findings zusammen mit einem Prompt zum Refactor an einen oder mehrere Worker.
    - Parallelisiere die Arbeit, wenn möglich.
