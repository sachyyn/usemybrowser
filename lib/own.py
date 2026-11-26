#!/usr/bin/env python3
"""Tab ownership records for umb. A record is a file <dir>/own-<id> (umb opened the tab) or <dir>/lend-<id>
(the user lent it) holding "<daemon pid> <epoch>". A record counts only while the daemon that wrote it is the
one running now and the tab still exists; anything else is stale and removed.
  own.py <dir> <daemon pid> prune   < list_pages json
  own.py <dir> <daemon pid> tabs    < list_pages json    prints: id "title" host [+|~]
  own.py <dir> <daemon pid> adopt <before json> < after json   marks tabs that appeared in between as owned
"""
import json, os, re, sys, time
from urllib.parse import urlparse

d, pid, cmd = sys.argv[1:4]
pages = json.load(sys.stdin)["pages"]
live = {p["id"] for p in pages}

def kinds():  # {id: set of kinds}, after dropping stale records
    out = {}
    for f in os.listdir(d):
        m = re.fullmatch(r"(own|lend)-(\d+)", f)
        if not m: continue
        try: rec_pid = open(os.path.join(d, f)).read().split()[0]
        except (OSError, IndexError): rec_pid = None
        if rec_pid != pid or int(m[2]) not in live:
            try: os.remove(os.path.join(d, f))
            except OSError: pass
        else: out.setdefault(int(m[2]), set()).add(m[1])
    return out

k = kinds()
if cmd == "tabs":
    for p in pages:
        mark = " +" if "own" in k.get(p["id"], ()) else " ~" if "lend" in k.get(p["id"], ()) else ""
        print('%d "%s" %s%s' % (p["id"], p["title"][:40], urlparse(p["url"]).hostname or p["url"][:30], mark))
elif cmd == "adopt":
    before = {p["id"] for p in json.loads(sys.argv[4])["pages"]}
    for i in live - before:
        open(os.path.join(d, "own-%d" % i), "w").write("%s %d\n" % (pid, time.time()))
