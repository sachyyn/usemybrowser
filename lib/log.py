# Appends one usage line for a umb call. Records the subcommand name, tab, exit code, size of the
# output and time, plus the site host (and, for look, the model's token counts). Never page content, URLs, arguments or typed values.
import datetime, json, os, re, sys
from urllib.parse import urlparse

cmd, tab, rc, ms, out_path, cache = sys.argv[1:7]
out = open(out_path, errors="replace").read()
host = None
if cmd == "open":
    m = re.match(r"(\d+) .* (https?://\S+)$", out.strip().split("\n")[-1])
    tab, host = (m.group(1), urlparse(m.group(2)).hostname) if m else ("", None)
elif tab.isdigit():
    try:
        host = urlparse(json.load(open(f"{cache}/state-{tab}.json")).get("url", "")).hostname
    except Exception:
        pass
rec = {"ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"), "cmd": cmd,
       "tab": int(tab) if tab.isdigit() else None, "exit": int(rc), "chars": len(out), "ms": int(float(ms))}
if host: rec["host"] = host
if os.environ.get("UMB_TASK"): rec["task"] = os.environ["UMB_TASK"]
try:  # umb look: model id and token counts, from the side file (no page content)
    rec.update(json.load(open(os.environ["UMB_EXTRA"])))
except Exception:
    pass
d = os.path.expanduser("~/.local/state/umb")
os.makedirs(d, exist_ok=True)
with open(d + "/usage.jsonl", "a") as f:
    f.write(json.dumps({k: v for k, v in rec.items() if v is not None}) + "\n")
