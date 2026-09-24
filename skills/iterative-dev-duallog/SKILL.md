---
name: iterative-dev-duallog
description: 
---

# Dual-Log Reading — Skill

**Die abschließende Textantwort eines Turns ist nur im Delta des NÄCHSTEN Requests sichtbar.**
- Der erste Request von Turn N+1 listet die Schlussantwort von Turn N unter seinem Separator.
- Ein Turn, der die Session beendet, hat keinen nächsten Request, seine Schlussantwort fehlt im Dual-Log also vollständig.

**Eine Untersuchung läuft ausschließlich über die duallog-Commands.**
- Eigene Skripte oder grep auf Logs und Code ersetzen keinen Command.
- Eine Zeitlücke wird mit `reqs --gap` gefunden und mit `expand --req` erklärt.

## Commands

| Vorgang | Command |
|---|---|
| Sessions listen | `sessions [project] [--since D] [--until D]` |
| Requests mit ihren Cache-Zahlen pro Turn ansehen | `reqs [scope] [--since D] [--until D] [--main \| --worker] [--turn N] [--gap MIN] [--merged] [--rebuild] [--drop]` |
| Die Msgs einer Session ansehen | `msgs <session> [from] [to]` |
| Die Msgs einer Session über einen REQ-Bereich ansehen | `msgs <session> --req F [T]` |
| Eine Msg mit allen ihren Blocks ausklappen | `expand <session> <msg> [--before N] [--after N] [--only classifier]` |
| Ausklappen, was ein REQ erzeugt hat | `expand <session> --req N [--before N] [--after N] [--only classifier]` |
| Über Sessions hinweg nach einem Literal suchen | `search <term> [scope] [--since D] [--until D] [--only classifier] [--case-sensitive]` |

### sessions

#### Input args

- `project` — Substring des Projektpfads oder des Stems, also zum Beispiel `trading`, `ai/trading` oder ein Worker-Name. Lässt du es weg, werden alle Sessions gelistet.
- `--since D` und `--until D` — Starttag im Format `YYYY-MM-DD`, jeweils einschließlich.

#### Output

```
START                PROJECT                                      SESSION
2026-09-06 22:27:49  /Users/brunowinter2000/Documents/ai/trading  api_requests_worker_reldist-power_1788726467
2026-09-06 14:47:46  /Users/brunowinter2000/Documents/ai/trading  api_requests_worker_k-ratio_1788698865
2026-09-06 10:10:25  /Users/brunowinter2000/Documents/ai/trading  api_requests_opus_trading_1788682222

3 sessions
```

### reqs

#### Input args

- `scope` — Substring des Projektpfads oder des Stems. Lässt du es weg, sind alle Sessions abgedeckt.
- `--since D` und `--until D` — Starttag im Format `YYYY-MM-DD`, jeweils einschließlich.
- `--main` und `--worker` — behalten nur die Main-Sessions, also opus, beziehungsweise nur die Worker-Sessions.
- `--turn N` — behält nur Turn N jeder Session.
- `--gap MIN` — zeigt REQ x und Folge-REQ y desselben Turns einer Session, wenn dazwischen mindestens MIN Minuten vergangen sind.
- `--merged` — eine chronologische Kette über alle Sessions im Scope, jede Zeile mit ihrem Worker getaggt. Das ist die Sicht auf die Cache-Gesundheit, denn alle Worker eines Projekts teilen sich den Prompt-Cache.
- `--rebuild` — behält nur REQs mit `CC > CR`, bei denen der Prefix also neu aufgebaut wurde.
- `--drop` — behält nur REQs, die weniger zurückgelesen haben als der vorherige REQ gecacht hatte, bei denen der Cache also dazwischen abgelaufen ist.
- Die Flags lassen sich kombinieren, und keines fügt eine Spalte hinzu.

#### Output

```
session api_requests_worker_1dda1c81_k-ratio_1788698865
── turn 4  14:57:29  50s  recap ──
REQ 46  14:58:19  CR 149,518  CC 228
── turn 5  18:02:18  8m18s  NEW TASK (same worktree, same area). Read this fully before doing anything. ──
REQ 47  18:02:18  CR 0        CC 152,851
REQ 48  18:02:23  CR 152,851  CC 7,889
```

- Ein Turn läuft von einem getippten Prompt bis zur idle Textantwort des Modells, wobei der Prompt vom Menschen oder über `worker-cli send` vom Orchestrator kommt. Der Separator zeigt den ersten Send, die Spanne und den Prompt.
- REQ-Nummer und Uhrzeit sind dieselben wie im Token-Pane und im Proxy-Window, die Uhrzeit ist das Ende der Antwort.
- `REQ ?` ist ein Request ohne Gegenstück im Transkript, etwa ein 404, er gehört zu keinem Turn.
- Eine Zeile auf stderr nennt den Weg, ohne auflösbares Transkript zeigt reqs nur die vollen Requests mit eigenen Nummern und Sendezeiten.
- `CR` steht für cache_read_input_tokens und `CC` für cache_creation_input_tokens dieses Requests. Ein `?` erscheint, wenn der Join mit dem Transkript fehlgeschlagen ist.
- Unter `--merged` folgt der Session-Tag auf einer REQ-Zeile der Uhrzeit und auf einem Separator der Spanne.

### msgs

#### Input args

- `session` — ein SESSION-Wert aus sessions oder ein eindeutiger Substring davon.
- `from` und `to` — Msg-Indizes, jeweils einschließlich. Lässt du sie weg, wird die ganze Session gedruckt.
- `--req F [T]` — nimmt stattdessen einen REQ-Bereich, jeweils einschließlich, wobei `T` auf `F` zurückfällt. Das ist nicht mit `from` und `to` kombinierbar.
   - Die Ausgabe reicht bis einschließlich zur Gruppe des Folge-REQs, damit die Antwort auf `T` sichtbar ist.

#### Output

```
── REQ 2  22:27:58  CR 13,267  CC 7,006 ──
[  2] assi  3 blocks              460c
        thinking                  149c
        tool_use[Read]            157c
        tool_use[Bash]            154c
[  3] user  2 blocks            14,886c
        tool_result             14,490c
        tool_result               396c
[  4] syst  system                 86c  −86 +1 → 1c
```

- Der Separator ist der Request, der die Msgs darunter HINZUGEFÜGT hat, mit seiner Sende-Uhrzeit und, wo auflösbar, mit CR und CC. Die Msgs unter REQ 2 sind die Antwort auf REQ 1 plus die Tool-Results, die REQ 2 daraufhin geschickt hat.
- `−N +M → Wc` heißt, dass der Proxy N Zeichen gestrippt und M injected hat und dass W über die Leitung gingen.
- Zeilen mit `sys[i]` oder `tool[Name]` direkt unter einem Separator sind System-Blocks und Tool-Definitionen, die dieser Request geändert hat.

### expand

#### Input args

- `session` — ein SESSION-Wert aus sessions oder ein eindeutiger Substring davon.
- `msg` — ein Msg-Index aus msgs oder search.
- `--req N` — ersetzt `msg` und zeigt, was REQ N erzeugt hat, also seine Antwort mit dem tool_use und das zurückgekommene tool_result.
   - Das beantwortet, welcher Befehl in einer Lücke von `reqs --gap` lief.
   - Folgt auf REQ N ein Turn-Start oder ein nicht aufgezeichneter Request, nennt expand den Grund statt einer Ausgabe.
- `--before N` und `--after N` — verbreitern das Fenster um N Msgs auf der jeweiligen Seite.
- `--only classifier` — behält nur Msgs, die auf eine Rolle passen (`user`), auf einen Block-Typ (`tool_result`) oder auf beides (`user/text`). Eine Msg passt, wenn ihre Rolle passt und IRGENDEIN Block auf den Typ passt, und sie zeigt dann immer ALLE ihre Blocks.

#### Output

```
▶ ═══ msg #231 23:10:14 user 5 chars, 1 block(s) ═══
── block 0  text  5 chars ──
recap
```

- Ein Header pro Msg mit Index, Uhrzeit, Rolle, Größe und Block-Anzahl, wobei `▶` den Anker markiert.
- Ein Header `── block i ──` pro Block, danach der rohe Inhalt.
- `── stripped by REQ n ──` und `── injected by REQ n ──` folgen auf einen Block, den der Proxy geändert hat, und zeigen was er entfernt und was er hingeschrieben hat.

### search

#### Input args

- `term` — ein wörtlicher Substring, keine Regex. Die Suche ignoriert Groß- und Kleinschreibung, außer bei `--case-sensitive`.
- `scope` — Substring des Projektpfads oder des Stems. Lässt du es weg, werden alle Sessions durchsucht.
- `--since D` und `--until D` — Starttag im Format `YYYY-MM-DD`, jeweils einschließlich.
- `--only classifier` — funktioniert wie bei expand.

#### Output

```
term      "recap"  (case-insensitive)

session   api_requests_worker_1dda1c81_reldist-power_1788726467
#231  user      text  5c
```

## Block Types

| Block Type | Was es ist |
|---|---|
| text | Sichtbare Prosa, also die getippte Nachricht des Menschen unter der Rolle user und die Antwort des Agents unter der Rolle assistant |
| thinking | Das interne Nachdenken des Agents |
| tool_use | Ein Tool-Aufruf mit Tool-Name plus Input-JSON, hier steht das ausgeführte Command |
| tool_result | Die Ausgabe des Tools, zurückgegeben unter der Rolle user, wobei `tool_result!err` Fehler markiert |
| image | Ein eingebettetes Bild |
| system | Ein zur Laufzeit injecteter Block, etwa Token-Zähler oder Listen aufgeschobener Tools |
| system-reminder | Von CC injecteter Kontext, verpackt als user-Msg, also CLAUDE.md-Inhalte und Env-Kontext |
| task-notification | Der Wake-up eines Background-Tasks mit Task-ID, Output-Pfad und Status, immer automatisch und nie echter User-Input |
