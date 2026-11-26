"""Run one benchmark arm with a per-turn trace (stream-json). Same flags as run.py.
Usage: trace.py <arm> [task]. Writes results/<task>-<arm>-trace-<time>.jsonl; summarise with analyze.py."""
import os, subprocess, sys, time
from pathlib import Path
B = Path(__file__).resolve().parent; arm = sys.argv[1]; task = sys.argv[2] if len(sys.argv) > 2 else 'sheets-sales'
for f in (B/'work').glob('*'):
    if f.is_file() and f.name != '.gitkeep': f.unlink()  # leftovers from an earlier run must not help this one
rid = 'trace-' + time.strftime('%H%M%S'); t = B/'tasks'/task
src = t/'task.local.md' if (t/'task.local.md').exists() else t/'task.md'  # a private, uncommitted variant wins
tsv = (t/'data.tsv').read_text().rstrip('\n') if (t/'data.tsv').exists() else ''
body = src.read_text().replace('{{ARM}}', arm).replace('{{RUN_ID}}', rid).replace('{{TSV}}', tsv)
prompt = body + '\n\n---\n\n' + (B/'guides'/f'{arm}.md').read_text()
cmd = ['claude','-p','--model','sonnet','--output-format','stream-json','--verbose','--max-budget-usd','8','--tools','Bash,Read','--allowedTools','Bash Read','--permission-mode','dontAsk','--strict-mcp-config','--disable-slash-commands','--no-session-persistence','--setting-sources','']
env = dict(os.environ, UMB_PROFILE=os.environ.get('UMB_PROFILE', 'Default'), PATH=f"{B.parent/'bin'}:{os.environ['PATH']}", UMB_TASK=f'bench-{task}-{arm}-{rid}', CLAUDE_CODE_DISABLE_AUTO_MEMORY='1', OPENCODE_BROWSER_AUTO_UPDATE='off')
out = B/'results'/f'{task}-{arm}-{rid}.jsonl'
with open(out,'w') as fh:
    p = subprocess.run(cmd, input=prompt, stdout=fh, stderr=subprocess.PIPE, text=True, cwd=B/'work', env=env, timeout=int(os.environ.get('BENCH_TIMEOUT_SEC', '1800')))
print(arm, 'done', out.name, 'rc', p.returncode)
