# measure_viewer_focus.sh report (2026-10-11 15:30:33, windows=3)

- PASS: frontmost app unchanged (com.coteditor.CotEditor)
- PASS: main Ghostty front window and focused terminal unchanged (tab-group-aaa55b020|D5A80D57-00F0-4E53-81AB-D4F822206785)
- PASS: samples differing from the start between open begin and 2 s after open end (total samples 87) (0)
- PASS: viewer window count (3)
- PASS: viewer windows attached and found by the OSC2 marker (3)
- PASS: activates swallowed by the shim (5, expected at least 3)

Baseline frontmost bundle: com.coteditor.CotEditor
Open phase (start end seconds, epoch): 1791725429 1791725430 1
All distinct samples (count epoch-free ASN):   87 ASN:0x0-0x3e03e:;
Visibility: 0 viewer windows above every other app window, 3 with another app window above them

## Probe (index|tty|terminal id)
1|/dev/ttys041|DECE259A-66B8-428D-A1E0-DE94D9965C25
2|/dev/ttys039|5FD4EA6C-F9E3-43DA-8867-8453EAEB20FF
3|/dev/ttys040|E4AEEF6D-6F27-4809-AECC-B8D6E2269952

## Onscreen layer-0 windows front to back (pid|owner|x|y|w|h), viewer pid=70189
1076|CotEditor|0|33|1728|992
70189|Ghostty Viewer|580|241|800|632
70189|Ghostty Viewer|551|212|800|632
70189|Ghostty Viewer|522|183|800|632
864|Ghostty|0|33|1728|998
637|Finder|0|505|920|525
864|Ghostty|2|35|1728|998
1076|CotEditor|0|33|1728|992
637|Finder|0|33|920|471
70765|Firefox|0|33|1728|998
52091|Google Chrome|0|35|1725|996
30787|canvas|0|33|1728|898
85199|monitor-cc-menubar|1004|37|439|460

## Shim log tail
1791725429 pid=70189 installed activateIgnoringOtherApps:
1791725429 pid=70189 installed activate
1791725430 pid=70189 swallowed activateIgnoringOtherApps:
1791725430 pid=70189 swallowed activateIgnoringOtherApps:
1791725430 pid=70189 swallowed activateIgnoringOtherApps:
