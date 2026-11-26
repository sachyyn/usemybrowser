#!/usr/bin/env python3
"""Run one benchmark arm: build prompt, run a fresh headless agent, save JSON, run the checker."""
import json, os, re, subprocess, sys, time
from pathlib import Path

BENCH = Path(__file__).resolve().parent
ARMS = ("v1", "v2", "browse")


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ARMS:
        sys.exit("usage: run.sh <v1|v2|browse> <task> [run_id]")
    arm, task = sys.argv[1], sys.argv[2]
    run_id = sys.argv[3] if len(sys.argv) > 3 else time.strftime("%m%d-%H%M%S")
    tdir = BENCH / "tasks" / task
    guide = (BENCH / "guides" / f"{arm}.md").read_text()
    if "TODO" in guide:
        sys.exit(f"guide for {arm} is still a TODO stub")
    body = (tdir / "task.md").read_text()
    body = (body.replace("{{ARM}}", arm).replace("{{RUN_ID}}", run_id)
            .replace("{{TSV}}", (tdir / "data.tsv").read_text().rstrip("\n")))
    prompt = body + "\n\n---\n\n" + guide

    work = BENCH / "work"
    work.mkdir(exist_ok=True)
    results = BENCH / "results"
    results.mkdir(exist_ok=True)
    out = results / f"{task}-{arm}-{run_id}.json"
    budget = os.environ.get("BENCH_BUDGET_USD", "8")
    timeout = int(os.environ.get("BENCH_TIMEOUT_SEC", "1800"))
    model = os.environ.get("BENCH_MODEL", "sonnet")

    # Same for every arm. --setting-sources "" skips user/project/local settings, hooks and CLAUDE.md files.
    cmd = ["claude", "-p", "--model", model, "--output-format", "json",
           "--max-budget-usd", budget,
           "--tools", "Bash,Read", "--allowedTools", "Bash Read",
           "--permission-mode", "dontAsk",
           "--strict-mcp-config", "--disable-slash-commands",
           "--no-session-persistence", "--setting-sources", ""]
    env = dict(os.environ, UMB_TASK=f"bench-{task}-{arm}-{run_id}",
               CLAUDE_CODE_DISABLE_AUTO_MEMORY="1")
    print("cmd:", " ".join(cmd), "(prompt on stdin)", file=sys.stderr)
    t0 = time.time()
    try:
        p = subprocess.run(cmd, input=prompt, capture_output=True, text=True,
                           cwd=work, env=env, timeout=timeout)
        raw, err = p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        raw, err = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), "timeout"
    wall = time.time() - t0
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = {"error": "no json", "stdout": raw[:2000], "stderr": (err or "")[:2000]}
    data["bench"] = {"arm": arm, "task": task, "run_id": run_id, "wall_sec": round(wall, 1),
                     "model_flag": model, "budget_usd": budget}
    out.write_text(json.dumps(data, indent=1))

    u = data.get("usage", {})
    ans = data.get("result") or ""
    print(f"{arm} {task} {run_id}: ${data.get('total_cost_usd', 0):.2f}, {data.get('num_turns')} turns, "
          f"{data.get('duration_ms', wall * 1000) / 60000:.1f} min, in {u.get('input_tokens')} / out "
          f"{u.get('output_tokens')} / cache-read {u.get('cache_read_input_tokens')} / cache-write "
          f"{u.get('cache_creation_input_tokens')}, answer {len(ans)} chars")

    m = re.search(r"https://docs\.google\.com/spreadsheets/d/[\w-]+", ans)
    if not m:
        data["check"] = {"error": "no spreadsheet URL in final answer"}
        out.write_text(json.dumps(data, indent=1))
        print("check: no spreadsheet URL in the final answer")
        return
    c = subprocess.run([sys.executable, str(BENCH / "check.py"), m.group(0), task,
                        "--title", f"umb-bench {arm} {run_id}"], capture_output=True, text=True)
    print(c.stdout, end="")
    if c.returncode:
        print(c.stderr, end="")
    data["check"] = {"url": m.group(0), "exit": c.returncode, "output": c.stdout,
                     "score": (re.search(r"score: (\d+/\d+)", c.stdout) or [None, None])[1]}
    out.write_text(json.dumps(data, indent=1))


main()
