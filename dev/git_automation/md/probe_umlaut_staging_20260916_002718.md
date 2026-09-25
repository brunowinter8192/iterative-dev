# gcommit / git-check non-ASCII staging probe

Run: 20260916_002718

| Result | Case |
|---|---|
| PASS | umlaut file inside an existing tracked anhaenge/ folder |
| PASS | path with a space |
| PASS | brand-new umlaut folder (directory status entry, not a file entry) |
| PASS | staged rename (git mv) commits the new path |
| PASS | plain ASCII modification (regression) |
| PASS | loud failure: unreadable file blocks git add, no commit made |
| PASS | git-check --auto-stage inherits the fix |

## Details

### umlaut file inside an existing tracked anhaenge/ folder — PASS

rc=0 files=['dokumente/wollpflege/anhänge/2026-08-28_troyer-zustandsfotos.pdf'] stdout='staged: dokumente/wollpflege/anhänge/2026-08-28_troyer-zustandsfotos.pdf\n[master 9687fb6] add troyer photos\n 1 file changed, 1 insertion(+)\n create mode 100644 "dokumente/wollpflege/anh\\303\\244nge/2026-08-28_troyer-zustandsfotos.pdf"'

### path with a space — PASS

rc=0 files=['meeting notes.md']

### brand-new umlaut folder (directory status entry, not a file entry) — PASS

rc=0 files=['anhänge_neu/foto.pdf']

### staged rename (git mv) commits the new path — PASS

rc=0 files=['new_name.txt', 'sidecar.txt']

### plain ASCII modification (regression) — PASS

rc=0 files=['README.md']

### loud failure: unreadable file blocks git add, no commit made — PASS

rc=1 before=b6b50473015f8dd0bc2798a22832d430c915c5bf after=b6b50473015f8dd0bc2798a22832d430c915c5bf output='staged: (nothing new)\n\nstage errors:\n  secret.bin: error: open("secret.bin"): Permission denied\nerror: unable to index file \'secret.bin\'\nfatal: adding files failed\naborting: staging failed, no commit made'

### git-check --auto-stage inherits the fix — PASS

rc=0 cached=['anhänge/schäden.pdf', 'spaced file.txt']
