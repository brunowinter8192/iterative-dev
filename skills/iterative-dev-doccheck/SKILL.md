---
name: iterative-dev-doccheck
description:
---

# Doc- und Struktur-Check

## Kernregeln

**§ Dokumentationshierarchie ist der einzige Standard, und er gewinnt gegen den aktuellen Stand des Projekts.**
- Eine bestehende Struktur ist nie eine Projektkonvention, die eine Abweichung entschuldigt.
   - Eine durchgängige Abweichung bleibt eine Abweichung.

**Die Menge ist nie ein Argument für den Scope.**
- Nie Stichproben, nie Abkürzungen, nie nur ein Teil, jeder regelgetriebene Fix wird vollständig durchgezogen.

**Jede Phase bearbeitet nur ihre eigene Oberfläche.**
- Phase 1 die process-docs, Phase 2 dev, Phase 3 die DOCS.md, Phase 4 die Skills, Phase 5 die Issues.
- Ein Befund, der zu einer anderen Oberfläche gehört, wartet auf deren Phase.

## Workflow

### Phase 0 — Prüfung der Kontaktschicht (nur Main, einmal)

**Stelle dem User vor Phase 1 eine einzige Frage.**
- Die Frage lautet: "Hat das Projekt neben diesem Chat eine Kontaktschicht für Nutzer?"

**Ein Nein heißt, jedes Verzeichnis ist im Scope.**

**Ein Ja heißt, das genannte Verzeichnis ist von jeder Phase ausgenommen.**
- Darin wird nie etwas verschoben, umbenannt, übersetzt, umformuliert oder umformatiert.

**Ein Worker stellt diese Frage nie.**
- Main gibt jeden ausgenommenen Pfad im Prompt des Workers mit.
- Der Worker nimmt genau das aus, was der Prompt nennt, und nicht mehr.

### Phase 1 — process-docs

**Prüfe jeden Ordner und jeden Eintrag unter `process-docs/` gegen jeden Block von § process-docs, und setze ihn durch.**
- Die Blöcke der Sektion sind die Checkliste, hier wird nichts davon wiederholt.
- Jeder Ordner `process-docs/<area>/` bekommt ein ausdrückliches Urteil.
   - Die Urteilsformen sind `valid: <leitende Frage>`, `folded into X`, `split into X+Y` und `dissolved`.
- Eine Umbenennung zieht nach `dev/<area>/` durch.

**Prüfe `.rag-docs.json` in der Projektwurzel.**
- `include` deckt jede `DOCS.md` und `process-docs/**/*.md` ab, und jedes Muster trifft mindestens eine Datei auf der Platte.
- `collection` folgt der Benennung `<Project>-docs`.
- Fehlt das Manifest, wird das im Bericht markiert und keines angelegt.
- `rag-cli update_docs` läuft hier nicht, der Abgleich des Index gehört zum Session-Recap.

### Phase 2 — dev

**Prüfe jeden Ordner und jede Datei unter `dev/` gegen jeden Block von § Konvention für das dev/-Verzeichnis, und setze sie durch.**
- Die Blöcke sind die Checkliste, hier wird nichts davon wiederholt.

**Ein Verstoß gegen § Konvention für das dev/-Verzeichnis (**In welchem dev/-Ordner du arbeitest richtet sich ausschließlich nach der Area, in der sich die Session bewegt.**) wird so behoben.**
- Ein dev-Verzeichnis ohne passende Area wird nach seiner Area umbenannt oder in deren dev-Verzeichnis eingegliedert.
- Unterhalb von Ebene 1 ist die Benennung frei, diese Ebene gehört zu § Phase 4 — Struktur der Doku des Skills iterative-dev-refactor.

**Ein Verstoß gegen § Konvention für das dev/-Verzeichnis (**dev/ hält Entwicklungsskripte für Experimente aller Art.**) wird so behoben.**
- Eine lose `.md` in `dev/`, die kein Skript erzeugt, kommt nach `process-docs/`, wenn sie noch relevant ist.
- Ist sie veraltet, wird sie gelöscht.

**Platzierungen, die die Regeln nicht abdecken.**
- Ein Wartungs- oder Hilfsskript kommt in sein thematisches `dev/<area>/`, einen ausgenommenen Sammelordner gibt es nicht.
- Ein Ordner, dessen Inhalt mehrere Areas umfasst, wird aufgeteilt, jeder Teil in sein eigenes `dev/<area>/`.

**Ob Report oder Daten, entscheidet der Inhalt.**
- Ein Report ist eine lesbare Analyse, auch eine Analyse-Ausgabe als JSON zählt dazu und kommt nach `md/`.
- Daten sind die Rohausgabe eines Laufs, etwa gescrapte Korpora, Roh-Dumps oder zwischengespeicherte Job-Daten.

**Kumulative Logs bleiben liegen.**
- Ein Log, das nur angehängt und über Läufe hinweg verfolgt und verglichen wird, ist kein Report und bleibt an seinem Platz.

**Eine in sich geschlossene Teil-Suite bekommt ihr eigenes `md/`.**
- Ordner wie `garbage_eval/` oder `browser_eval/` halten ihr eigenes `md/`, nicht das der übergeordneten Area.

### Phase 3 — DOCS

**Prüfe jede `DOCS.md` gegen jeden Block von § DOCS.md, und setze ihn durch.**
- Die Blöcke sind die Checkliste, hier wird nichts davon wiederholt.
- Nutze Heredocs oder Skripte unter `/tmp`, lies nicht jede `DOCS.md` von Hand.

**Dateien in der Projektwurzel.**
- Eine `README.md` in der Wurzel wird zum Entfernen markiert.
- Eine `DOCS.md` in der Wurzel, die einen Projektüberblick gibt, wird zum Entfernen markiert.
- Eine `CLAUDE.md` in der Wurzel, die projektinterne interaktive Arbeitsbereiche dokumentiert, ist erlaubt.

**Verweise lösen sich auf.**
- Jede Datei, die eine `DOCS.md` nennt, existiert auf der Platte.
- Ein Verweis auf eine nicht existierende Datei wird aus der `DOCS.md` gelöscht.

**Erst sichern, dann kürzen.**
- Alles, was gekürzt wird, um das Format zu erreichen, kommt vor dem Kürzen wörtlich in die eigene process-docs-Datei des Autors, unter je einer Überschrift `## Salvage from <path>` pro DOCS.md.
- Es gibt keine Prüfung der Abdeckung und keine Einzelbewertung pro Kürzung, RAG macht den gesicherten Inhalt auffindbar.

### Phase 4 — Skills (nur markieren)

**Prüfe jede `skills/*/SKILL.md` gegen jeden Block von § Artifact Density, und markiere.**
- Befunde werden hier nur gesammelt, nie behoben.

**Frontmatter: `description:` ist vorhanden und leer.**
- Eine nicht leere `description` wird markiert.

**Markiere Begründungen anhand ihrer Signatur.**

| Signatur | Beispiel | Aktion |
|---|---|---|
| Begründungsnebensatz | "roh und maximal, nicht erfasster Inhalt ist für immer weg" | Nebensatz streichen, Anweisung behalten |
| Ursache oder Mechanismus | "der Plugin-Cache hat KEIN venv, also scheitert ein plugin-relativer Pfad" | streichen |
| Begründungsabschnitt | ein Abschnitt "Warum X wichtig ist" | Abschnitt löschen |
| Historie oder Belegnotiz | "(geprüft an 278 Dateien)", "frühere Läufe sind hier gescheitert" | streichen |
| Ausmalen von "was sonst passiert" | "derselbe Anker liefert nur dieselben Top-Quellen" | streichen |
| `weil` / `damit` / `um zu` / `was bedeutet` | jeder Nebensatz, der damit beginnt | Nebensatz streichen |

**Nie markiert werden:**
- Befehle, Pfade, Schwellenwerte, Ausgabeformate, Parametertabellen, Regeln zur Reihenfolge, Verbote, Verhaltensfakten, auf denen das Vorgehen beruht, und Entscheidungsbeispiele.

### Phase 5 — Issues (nur Main)

**Ein Worker überspringt diese Phase komplett.**

**Bringe jedes offene Issue per `update_issue --body` in das Issue-Format von § Issues.**
- Die Zeile `Area:` nennt die Area nach der Ordnerstruktur, die nach dem Audit gilt.

### Phase 6 — Übergabe

**Berichte die Befunde.**
- Pro Ordner `process-docs/<area>/` sein Urteil und jeden Eintrag, der verschoben wurde.
- Jeden Fix aus den Phasen 1 bis 3, die Markierungen aus Phase 4 und die Neufassungen aus Phase 5.

**Main committet die Doc-Fixes, Worker werden nach Menge eingesetzt, nicht nach Dateityp.**
- Eine Oberfläche, die zu groß ist, um sie in einer Session in Ordnung zu bringen, geht an Worker, ein Worktree pro Block der Oberfläche.
- Jeder Worker bekommt die konkreten Befunde für seinen Block in seinen Prompt.
- Reviewe und merge den Branch jedes Workers.
- Den RAG-Abgleich gibt es hier nicht, er gehört zum Session-Recap auf dem endgültig gemergten Stand.

**Als Worker bist du fertig, du spawnst nichts.**
