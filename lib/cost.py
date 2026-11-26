# umb cost [--task name] [--since YYYY-MM-DD]: totals per task from the usage log.
import json, os, sys
from collections import defaultdict

args = sys.argv[1:]
task = args[args.index("--task") + 1] if "--task" in args else None
since = args[args.index("--since") + 1] if "--since" in args else ""
rate = os.environ.get("UMB_USD_PER_MTOK")
path = os.path.expanduser("~/.local/state/umb/usage.jsonl")
rows = []
if os.path.exists(path):
    for line in open(path):
        try: rows.append(json.loads(line))
        except ValueError: pass
rows = [r for r in rows if r["ts"][:10] >= since and (task is None or r.get("task") == task)]
if not rows: sys.exit("umb: no usage lines" + (f" for task {task}" if task else "") + " (UMB_TASK=<name> tags a task)")
by = defaultdict(list)
for r in rows: by[r.get("task", "(none)")].append(r)
for name, rs in by.items():
    repeats = sum(1 for a, b in zip(rs, rs[1:]) if (a["cmd"], a.get("tab")) == (b["cmd"], b.get("tab")))
    chars = sum(r["chars"] for r in rs)
    line = (f"{name}: {len(rs)} commands, {sum(1 for r in rs if r['exit'])} failures, {repeats} repeats, "
            f"{chars} chars, ~{chars // 4} tokens, {sum(r['ms'] for r in rs) / 1000:.1f}s")
    if rate: line += f", ~${chars / 4 / 1e6 * float(rate):.4f}"
    print(line)
