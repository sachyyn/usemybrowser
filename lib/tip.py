#!/usr/bin/env python3
"""Close-time reminder. tip.py <host> <tab opened epoch> <stamp dir>
Prints one tip line when the usage log shows at least 12 umb commands on <host> since the tab was opened,
no `umb note` on that host in that time, and no tip for that host yet today. Prints nothing otherwise."""
import datetime, json, os, sys

host, opened, stamps = sys.argv[1], float(sys.argv[2]), sys.argv[3]
n, noted = 0, False
for line in open(os.path.expanduser("~/.local/state/umb/usage.jsonl")):
    try:
        r = json.loads(line)
        if r.get("host") != host or datetime.datetime.fromisoformat(r["ts"]).timestamp() < opened: continue
    except Exception:
        continue
    n += 1
    noted = noted or r.get("cmd") == "note"
today = datetime.date.today().isoformat()
stamp = os.path.join(stamps, "tip-" + host)
try: seen = open(stamp).read().strip() == today
except OSError: seen = False
if n >= 12 and not noted and not seen:
    print(f'tip: if something non-obvious worked on {host}, save it for next time: umb note {host} "<one command line and when to use it>"')
    os.makedirs(stamps, exist_ok=True)
    open(stamp, "w").write(today + "\n")
