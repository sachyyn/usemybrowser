"""Per-step breakdown of one traced run: turns, sizes, images, errors and dollars. Usage: analyze.py <trace.jsonl>"""
import json, sys, re, collections
f = sys.argv[1]; R, W, O = 0.10e-6, 4.0e-6, 10.0e-6
msgs = {}; order = []; results = {}; final = None
for line in open(f):
    try: e = json.loads(line)
    except Exception: continue
    if e.get('type') == 'assistant':
        m = e['message']; i = m['id']
        if i not in msgs: msgs[i] = {'usage': m.get('usage', {}), 'tools': [], 'text': 0, 'think': 0}; order.append(i)
        msgs[i]['usage'] = m.get('usage', msgs[i]['usage'])
        for c in m.get('content', []):
            if c['type'] == 'tool_use': msgs[i]['tools'].append((c['id'], c['name'], c.get('input', {})))
            elif c['type'] == 'text': msgs[i]['text'] += len(c.get('text', ''))
            elif c['type'] == 'thinking': msgs[i]['think'] += len(c.get('thinking', ''))
    elif e.get('type') == 'user':
        for c in e['message'].get('content', []) if isinstance(e['message'].get('content'), list) else []:
            if c.get('type') == 'tool_result':
                cont = c.get('content'); chars = 0; imgs = 0
                if isinstance(cont, str): chars = len(cont)
                else:
                    for p in cont or []:
                        if p.get('type') == 'text': chars += len(p.get('text', ''))
                        elif p.get('type') == 'image': imgs += 1
                results[c['tool_use_id']] = (chars, imgs, bool(c.get('is_error')))
    elif e.get('type') == 'result': final = e
def cat(name, inp):
    if name == 'Read': return 'Read ' + ('image' if re.search(r'\.(png|jpe?g)$', inp.get('file_path', '')) else 'file')
    cmd = inp.get('command', '')
    subs = re.findall(r'(?:umb|browse|helium)\s+([a-z_]+)', cmd)
    if not subs: return 'bash other'
    return '+'.join(sorted(set(subs))[:3]) if len(set(subs)) > 1 else subs[0]
turns = len(order); u0 = msgs[order[0]]['usage']
tot = collections.Counter(); cats = collections.defaultdict(lambda: collections.Counter())
prev_ctx = 0; cmd_chars = 0
for n, i in enumerate(order):
    m = msgs[i]; u = m['usage']
    r, w, o = u.get('cache_read_input_tokens', 0), u.get('cache_creation_input_tokens', 0), u.get('output_tokens', 0)
    tot['read'] += r; tot['write'] += w; tot['out'] += o
    names = [cat(a, b) for _, a, b in m['tools']] or ['(final/text)']
    key = names[0] if len(names) == 1 else 'multi'
    c = cats[key]; c['turns'] += 1; c['out'] += o; c['read'] += r
    for tid, name, inp in m['tools']:
        ch, im, er = results.get(tid, (0, 0, False)); c['res_chars'] += ch; c['imgs'] += im; c['err'] += er
        c['cmd_chars'] += len(inp.get('command', '') or json.dumps(inp)); c['calls'] += 1
print(f"turns {turns}; first turn: write {u0.get('cache_creation_input_tokens')} read {u0.get('cache_read_input_tokens')} (the fixed start: instructions + tools + task)")
ctx = [msgs[i]['usage'].get('cache_read_input_tokens', 0) + msgs[i]['usage'].get('cache_creation_input_tokens', 0) for i in order]
print('context size at turn 1 / 25% / 50% / 75% / last:', ctx[0], ctx[turns//4], ctx[turns//2], ctx[3*turns//4], ctx[-1])
print(f"totals: read {tot['read']} (${tot['read']*R:.3f})  write {tot['write']} (${tot['write']*W:.3f})  out {tot['out']} (${tot['out']*O:.3f})  reported ${final.get('total_cost_usd', 0):.3f}")
print(f"{'step type':28} {'turns':>5} {'calls':>5} {'cmd chars':>9} {'result chars':>12} {'imgs':>4} {'err':>3} {'out tok':>7} {'$out':>6} {'$reread':>7}")
for k, c in sorted(cats.items(), key=lambda kv: -kv[1]['out']):
    print(f"{k[:28]:28} {c['turns']:5} {c['calls']:5} {c['cmd_chars']:9} {c['res_chars']:12} {c['imgs']:4} {c['err']:3} {c['out']:7} {c['out']*O:6.3f} {c['read']*R:7.3f}")
big = sorted(((results.get(t, (0,0,0))[0], cat(a, b), len(b.get('command', ''))) for i in order for t, a, b in msgs[i]['tools']), reverse=True)[:6]
print('largest tool results (chars, type):', [(x, y) for x, y, _ in big])
bigc = sorted(((len(b.get('command', '')), cat(a, b)) for i in order for t, a, b in msgs[i]['tools']), reverse=True)[:6]
print('largest commands written by the agent (chars, type):', bigc)
print('thinking chars', sum(m['think'] for m in msgs.values()), ' visible text chars', sum(m['text'] for m in msgs.values()))
