#!/usr/bin/env python3
"""umb note <host> "<text>": append one learned line to <user notes dir>/<host>.md.
  note.py <dir> <host> <text>
Prints one result line (and a second one when the file passes 40 lines). Exit 1 with a message on stderr to refuse."""
import datetime, os, sys

d, host, text = sys.argv[1:4]
MAX, WARN = 300, 40
if not text.strip() or "\n" in text or "\r" in text:
    sys.exit("umb: a note is one non-empty line")
if len(text) > MAX:
    sys.exit(f"umb: note is {len(text)} characters (max {MAX}). Keep it to one command line and when to use it; "
             "anything longer belongs in the repo's notes/ file, not here.")
text = text.strip()
path = os.path.join(d, host + ".md")
try:
    lines = [l.rstrip("\n") for l in open(path) if l.strip()]
except FileNotFoundError:
    lines = []
# A line is "- YYYY-MM-DD <text>"; compare on the text only.
if any(l[13:] == text for l in lines if l.startswith("- ") and l[12:13] == " "):
    print(f"already noted for {host} ({len(lines)} learned lines)")
    sys.exit(0)
os.makedirs(d, exist_ok=True)
with open(path, "a") as f:
    f.write(f"- {datetime.date.today().isoformat()} {text}\n")
n = len(lines) + 1
print(f"noted for {host} ({n} learned lines)")
if n > WARN:
    print(f"umb: {host} has {n} learned lines (over {WARN}); merge or delete stale ones in {path}")
