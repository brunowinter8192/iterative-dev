# measure_viewer_focus.sh report (2026-10-11 15:37:48, windows=20)

- PASS: frontmost app unchanged (com.coteditor.CotEditor)
- PASS: main Ghostty front window and focused terminal unchanged (tab-group-aaa55b020|D5A80D57-00F0-4E53-81AB-D4F822206785)
- PASS: samples differing from the start between open begin and 2 s after open end (total samples 199) (0)
- PASS: viewer window count (20)
- PASS: viewer windows attached and found by the OSC2 marker (20)
- PASS: activates swallowed by the shim (22, expected at least 20)

Baseline frontmost bundle: com.coteditor.CotEditor
Open phase (start end seconds, epoch): 1791725857 1791725861 4
All distinct samples (count epoch-free ASN):  199 ASN:0x0-0x3e03e:;
Visibility: 0 viewer windows above every other app window, 20 with another app window above them

## Probe (index|tty|terminal id)
1|/dev/ttys057|4E98043D-8E8F-4A94-87AB-16A059478A21
2|/dev/ttys058|A2109EB2-A45E-4FB8-8B26-096357595CC0
3|/dev/ttys075|0C3ECD83-8D79-445B-89CF-41B9B6260DC1
4|/dev/ttys074|B4643405-1B1C-4E4B-9B3D-8441F9377326
5|/dev/ttys059|6242941E-D938-45D8-AF89-CF0611F1F2C0
6|/dev/ttys065|72BE3A51-8793-4442-A581-A4CE1DED577F
7|/dev/ttys063|49C7442E-441B-4B54-9371-0343F21A4841
8|/dev/ttys071|978F53FC-E70B-4157-A72D-F371330047A7
9|/dev/ttys069|9A0E1978-D7FE-4513-A5A4-6E7475987338
10|/dev/ttys066|EBB65FA7-4A52-4C91-B90B-75A97C27D979
11|/dev/ttys068|6CAA3E81-6135-45F2-9F9C-562C954E0E61
12|/dev/ttys073|06F81D3D-DA79-462A-B642-6AB0F6CE1559
13|/dev/ttys060|E1CA77F6-71DC-4AC0-9CB5-5DF21D41217D
14|/dev/ttys062|392C5146-2E34-4E7D-AA0A-B5F336BACE76
15|/dev/ttys067|96961771-0F13-43D3-8F32-957C5D70DA57
16|/dev/ttys076|8480D2AF-67A9-4107-9864-116E6987618E
17|/dev/ttys061|7FE21E3A-AC2E-44B5-9B4D-D3D3FC17D388
18|/dev/ttys064|EBD57AC0-D173-4889-9ED6-142EE2FCAE71
19|/dev/ttys072|AB2F15F4-0797-454A-BB5E-B69A9D8DEF83
20|/dev/ttys070|618A1478-AC21-45DB-8551-B3FB6FE822CA

## Onscreen layer-0 windows front to back (pid|owner|x|y|w|h), viewer pid=36823
1076|CotEditor|0|33|1728|992
36823|Ghostty Viewer|188|61|800|632
36823|Ghostty Viewer|159|395|800|632
36823|Ghostty Viewer|130|366|800|632
36823|Ghostty Viewer|101|337|800|632
36823|Ghostty Viewer|72|308|800|632
36823|Ghostty Viewer|43|279|800|632
36823|Ghostty Viewer|14|250|800|632
36823|Ghostty Viewer|928|221|800|632
36823|Ghostty Viewer|899|192|800|632
36823|Ghostty Viewer|870|163|800|632
36823|Ghostty Viewer|841|134|800|632
36823|Ghostty Viewer|812|105|800|632
36823|Ghostty Viewer|783|76|800|632
36823|Ghostty Viewer|754|47|800|632
36823|Ghostty Viewer|725|386|800|632
36823|Ghostty Viewer|696|357|800|632
36823|Ghostty Viewer|667|328|800|632
36823|Ghostty Viewer|638|299|800|632
36823|Ghostty Viewer|609|270|800|632
36823|Ghostty Viewer|580|241|800|632
864|Ghostty|0|33|1728|998
70765|Firefox|0|33|1728|998
637|Finder|0|505|920|525
864|Ghostty|2|35|1728|998
1076|CotEditor|0|33|1728|992
637|Finder|0|33|920|471
52091|Google Chrome|0|35|1725|996
30787|canvas|0|33|1728|898
85199|monitor-cc-menubar|1004|37|439|460

## Shim log tail
1791725857 pid=36823 installed activateIgnoringOtherApps:
1791725857 pid=36823 installed activate
1791725857 pid=36823 swallowed activateIgnoringOtherApps:
1791725857 pid=36823 swallowed activateIgnoringOtherApps:
1791725857 pid=36823 swallowed activateIgnoringOtherApps:
1791725858 pid=36823 swallowed activateIgnoringOtherApps:
1791725858 pid=36823 swallowed activateIgnoringOtherApps:
1791725858 pid=36823 swallowed activateIgnoringOtherApps:
1791725858 pid=36823 swallowed activateIgnoringOtherApps:
1791725858 pid=36823 swallowed activateIgnoringOtherApps:
1791725859 pid=36823 swallowed activateIgnoringOtherApps:
1791725859 pid=36823 swallowed activateIgnoringOtherApps:
1791725859 pid=36823 swallowed activateIgnoringOtherApps:
1791725859 pid=36823 swallowed activateIgnoringOtherApps:
1791725859 pid=36823 swallowed activateIgnoringOtherApps:
1791725860 pid=36823 swallowed activateIgnoringOtherApps:
1791725860 pid=36823 swallowed activateIgnoringOtherApps:
1791725860 pid=36823 swallowed activateIgnoringOtherApps:
1791725860 pid=36823 swallowed activateIgnoringOtherApps:
1791725861 pid=36823 swallowed activateIgnoringOtherApps:
1791725861 pid=36823 swallowed activateIgnoringOtherApps:
1791725861 pid=36823 swallowed activateIgnoringOtherApps:
