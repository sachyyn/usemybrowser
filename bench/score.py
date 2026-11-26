"""Summarise the last N traced runs of an arm: dollars, turns, images, tool usage and checker score. Usage: score.py <arm> [n]"""
import collections, glob, json, os, re, subprocess, sys
from pathlib import Path
B = Path(__file__).resolve().parent; arm = sys.argv[1]; n = int(sys.argv[2]) if len(sys.argv) > 2 else 3
logp = Path.home() / '.local/state/umb/usage.jsonl'
log = [json.loads(l) for l in open(logp)] if logp.exists() else []
for f in sorted(glob.glob(str(B / f'results/*-{arm}-trace-*.jsonl')), key=os.path.getmtime)[-n:]:
    rid = f.split(f'{arm}-')[-1][:-6]; raw = open(f).read(); fin = None; turns = set(); imgs = 0
    for l in raw.splitlines():
        try: e = json.loads(l)
        except Exception: continue
        if e.get('type') == 'result': fin = e
        elif e.get('type') == 'assistant': turns.add(e['message']['id'])
        elif e.get('type') == 'user' and isinstance(e['message'].get('content'), list):
            for c in e['message']['content']:
                if c.get('type') == 'tool_result' and isinstance(c.get('content'), list):
                    imgs += sum(p.get('type') == 'image' for p in c['content'])
    if not fin: print(rid, 'no result'); continue
    ids = collections.Counter(re.findall(r'spreadsheets/d/([\w-]{30,})', raw)).most_common(1); score = 'no sheet id'
    if ids:
        p = subprocess.run([sys.executable, str(B / 'check.py'), f'https://docs.google.com/spreadsheets/d/{ids[0][0]}/edit', 'sheets-sales'], capture_output=True, text=True, timeout=300)
        s = re.findall(r'score: (\d+/\d+)', p.stdout); fails = [x[6:100] for x in p.stdout.splitlines() if x.startswith('FAIL')]
        score = (s[-1] if s else 'checker error') + (' FAILED: ' + ' ; '.join(fails) if fails else '')
    L = [x for x in log if x.get('task', '').endswith(rid)]; looks = [x for x in L if x['cmd'] == 'look']
    lk = sum(x.get('model_in', 0) for x in looks) * 0.3e-6 + sum(x.get('model_out', 0) for x in looks) * 2.5e-6
    u = fin['usage']; top = collections.Counter(x['cmd'] for x in L).most_common(6)
    print(f"{rid}: ${fin['total_cost_usd']:.3f} turns {len(turns)} min {fin['duration_ms']/60000:.1f} images {imgs} | enter ${u['cache_creation_input_tokens']*4e-6:.3f} reread ${u['cache_read_input_tokens']*0.1e-6:.3f} write ${u['output_tokens']*10e-6:.3f} | umb cmds {len(L)} failed {sum(x['exit'] != 0 for x in L)} look {len(looks)} (${lk:.4f}) {top}\n   score {score}")
