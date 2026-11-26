#!/usr/bin/env python3
"""Browser profiles for umb, read from the browser's data dir (argv[1]).
  profiles.py <dir> list              folder<TAB>display name<TAB>flags   (flags: last-used, active)
  profiles.py <dir> resolve <x>       folder for a folder name or display name; exit 1 and list the choices if none
  profiles.py <dir> active-count      how many profiles the browser last had windows open in
"""
import json, os, re, sys

d, cmd = sys.argv[1], sys.argv[2]

def load(path):
    try:
        with open(path) as f: return json.load(f)
    except (OSError, ValueError): return {}

state = load(os.path.join(d, "Local State")).get("profile", {})
cache = state.get("info_cache", {})
folders = [f for f in sorted(os.listdir(d)) if re.fullmatch(r"Default|Profile \d+", f) and os.path.isdir(os.path.join(d, f))]
folders.sort(key=lambda f: (f != "Default", int(f.split()[-1]) if f != "Default" else 0))

def name(f):  # Local State holds the name the user sees; Preferences is the fallback
    return cache.get(f, {}).get("name") or load(os.path.join(d, f, "Preferences")).get("profile", {}).get("name") or f

if cmd == "list":
    for f in folders:
        flags = ["last-used"] * (f == state.get("last_used")) + ["active"] * (f in state.get("last_active_profiles", []))
        print("%s\t%s\t%s" % (f, name(f), ",".join(flags)))
elif cmd == "resolve":
    want = sys.argv[3].strip().lower()
    hit = [f for f in folders if f.lower() == want] or [f for f in folders if name(f).strip().lower() == want]
    if len(hit) != 1:
        sys.exit("umb: %s profile \"%s\"; choose one of: %s" % ("ambiguous" if hit else "no", sys.argv[3], ", ".join(folders)))
    print(hit[0]); print(name(hit[0]))
elif cmd == "active-count":
    print(len(state.get("last_active_profiles", [])))
