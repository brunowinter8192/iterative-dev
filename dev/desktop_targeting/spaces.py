# INFRASTRUCTURE
import sys
from typing import Dict, List, Optional, Tuple

from objc_bridge import _CG, _cf_at, _cf_count, _dict_long, _dict_str, _dict_val


# FUNCTIONS

def build_space_map(cid: int) -> Tuple[Dict[int, Tuple[str, int]], int, Dict[str, List[int]]]:
    active = _CG.CGSGetActiveSpace(cid)
    dsp_arr = _CG.CGSCopyManagedDisplaySpaces(cid)
    n_disp = _cf_count(dsp_arr)
    space_map: Dict[int, Tuple[str, int]] = {}
    display_spaces: Dict[str, List[int]] = {}

    for di in range(n_disp):
        d = _cf_at(dsp_arr, di)
        disp_id = (
            _dict_str(d, 'Display Identifier') or
            _dict_str(d, 'DisplayIdentifier') or
            f'display_{di}'
        )
        spaces_val = _dict_val(d, 'Spaces') or _dict_val(d, 'spaces')
        if not spaces_val:
            continue
        ids: List[int] = []
        for si in range(_cf_count(spaces_val)):
            sp = _cf_at(spaces_val, si)
            sid = (
                _dict_long(sp, 'ManagedSpaceID') or
                _dict_long(sp, 'id') or
                _dict_long(sp, 'ID')
            )
            if sid is not None:
                space_map[sid] = (disp_id[:12], si + 1)
                ids.append(sid)
        display_spaces[disp_id] = ids

    return space_map, active, display_spaces


def choose_target_space(cid: int, override: Optional[int]) -> Tuple[int, int]:
    space_map, active, display_spaces = build_space_map(cid)

    print(f"\n── Space-Übersicht ──────────────────────────────────────────")
    for disp, ids in display_spaces.items():
        for sid in ids:
            marker = " ← aktiv" if sid == active else ""
            no = space_map[sid][1]
            print(f"  space_id={sid:6}  desktop={no}  display={disp[:20]}{marker}")

    if override is not None:
        if override not in space_map:
            sys.exit(f"ERROR: --space {override} nicht in bekannten Spaces {list(space_map.keys())}")
        return active, override

    active_display = next(
        (disp for disp, ids in display_spaces.items() if active in ids), None
    )
    if active_display is None:
        sys.exit(f"ERROR: aktiver Space {active} nicht in CGSCopyManagedDisplaySpaces")

    candidates = [s for s in display_spaces[active_display] if s != active]
    if not candidates:
        sys.exit(
            f"ERROR: kein zweiter Space auf Display '{active_display[:20]}'. "
            "Bitte in Mission Control einen zweiten Desktop anlegen."
        )
    return active, candidates[0]
