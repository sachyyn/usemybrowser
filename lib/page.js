// Page-side helpers for bin/umb. bin/umb builds one script per call:
//   async () => { <vendor/browse/capture.js> <this file> return await umbMain(op, argv, state) }
// Every op returns {out, state?, done?} or throws; umbMain turns a throw into {error}.

const norm = (s) => (s || '').replace(/\s+/g, ' ').trim();
const unquote = (s) => s.replace(/^(["'])(.*)\1$/s, '$2');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const VALUE_FLAGS = ['find', 'within', 'max', 'text', 'gone', 'url', 'ref', 'css', 'timeout'];
const BOOL_FLAGS = ['interactive', 'delta', 'force'];

function parse(argv) {
  const pos = [], flags = {};
  for (let i = 0; i < argv.length; i++) {
    const name = argv[i].replace(/^--/, '');
    if (argv[i].startsWith('--') && VALUE_FLAGS.includes(name)) flags[name] = argv[++i] ?? '';
    else if (argv[i].startsWith('--') && BOOL_FLAGS.includes(name)) flags[name] = true;
    else pos.push(argv[i]);
  }
  return { pos, flags };
}

const visible = (el) =>
  el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true }) && el.getBoundingClientRect().width > 0;

function describe(el) {
  const cls = el.classList[0] ? '.' + el.classList[0] : '';
  const text = norm(el.innerText).slice(0, 40);
  return `<${el.localName}${el.id ? '#' + el.id : ''}${cls}${text ? ` "${text}"` : ''}>`;
}

// css selectors from capture() may cross shadow roots with " >> ".
function byCss(selector) {
  const parts = selector.split(' >> ');
  let scopes = [document];
  parts.forEach((p, i) => {
    scopes = scopes.flatMap((s) => [...s.querySelectorAll(p)]);
    if (i < parts.length - 1) scopes = scopes.map((e) => e.shadowRoot).filter(Boolean);
  });
  return scopes;
}

// Exact visible text. Of nested matches keep the innermost, so <button><span>Save</span></button> is one match.
function byText(text) {
  const all = [...document.querySelectorAll('body *')]
    .filter((e) => e.textContent.includes(text) && visible(e) && norm(e.innerText) === text);
  return all.filter((e) => !all.some((o) => o !== e && e.contains(o)));
}

// Resolve a target (ref, text:"..." or css:"...") to exactly one element, or throw saying how many matched.
function pick(target, state) {
  let els, label, what;
  const m = /^(text|css):(.*)$/s.exec(target);
  if (/^e\d+$/.test(target)) {
    const known = state.sel?.[target.slice(1)];
    if (!known) throw Error(`unknown ref ${target}; run umb snap first`);
    els = byCss(known.selector);
    label = `${target} ${known.label}`;
    what = `ref ${target} (${known.label})`;
  } else if (m) {
    const v = unquote(m[2]);
    els = m[1] === 'text' ? byText(v) : byCss(v);
    label = what = target;
  } else {
    throw Error('target must be a ref like e12, text:"Exact text" or css:"selector"');
  }
  if (els.length !== 1) {
    const some = els.slice(0, 4).map(describe).join(', ');
    throw Error(`${what} matched ${els.length} elements${some ? ': ' + some : '; the page may have changed, run umb snap again'}`);
  }
  return { el: els[0], label };
}

function topAt(x, y) {
  let t = document.elementFromPoint(x, y);
  for (let n; t?.shadowRoot && (n = t.shadowRoot.elementFromPoint(x, y)) && n !== t; ) t = n;
  return t;
}

// Visible, enabled, scrolled into view, and nothing covers its centre.
function ready(el) {
  if (!visible(el)) throw Error(`${describe(el)} is not visible`);
  if (el.disabled || el.closest('[aria-disabled=true]')) throw Error(`${describe(el)} is disabled`);
  el.scrollIntoView({ block: 'center', inline: 'center' });
  const r = el.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
  if (x < 0 || y < 0 || x > innerWidth || y > innerHeight) throw Error(`${describe(el)} is outside the viewport`);
  const top = topAt(x, y);
  if (top && top !== el && !el.contains(top))
    throw Error(`${describe(el)} is covered by ${describe(top)}; dismiss it first, or pass --force`);
}

// Resolves with true if the DOM changed within ms after fn() ran.
async function domChangedAfter(fn, ms = 250) {
  let changed = false;
  const mo = new MutationObserver(() => (changed = true));
  mo.observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
  fn();
  await sleep(ms);
  mo.disconnect();
  return changed;
}

async function click(a, state) {
  const { el, label } = pick(a.pos[0] ?? '', state);
  if (a.flags.force) el.scrollIntoView({ block: 'center', inline: 'center' });
  else ready(el);
  const r = el.getBoundingClientRect();
  const at = { bubbles: true, cancelable: true, view: window, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 };
  const changed = await domChangedAfter(() => {
    el.dispatchEvent(new PointerEvent('pointerdown', at));
    el.dispatchEvent(new MouseEvent('mousedown', at));
    el.focus?.();
    el.dispatchEvent(new PointerEvent('pointerup', at));
    el.dispatchEvent(new MouseEvent('mouseup', at));
    el.click();
  });
  return { out: `clicked ${label}; page ${changed ? 'changed' : 'did not change'}` };
}

function setValue(el, value) {
  el.focus();
  const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  if (el.value !== value) throw Error(`${describe(el)} did not keep the value (now "${el.value}")`);
}

function fill(a, state) {
  const [target, value] = a.pos;
  if (value === undefined) throw Error('usage: umb fill <tab> <target> <value>');
  const { el, label } = pick(target, state);
  const isToggle = el.matches('input[type=checkbox], input[type=radio]');
  if (!isToggle && !visible(el)) throw Error(`${describe(el)} is not visible`);
  if (el.disabled || el.readOnly) throw Error(`${describe(el)} is disabled or read-only`);
  el.scrollIntoView({ block: 'center', inline: 'center' });
  if (isToggle) {
    if (!['true', 'false'].includes(value)) throw Error(`${label} is a ${el.type}; value must be true or false`);
    const want = value === 'true';
    if (el.checked === want) return { out: `${label} already ${want ? 'checked' : 'unchecked'}; left alone` };
    if (!want && el.type === 'radio') throw Error(`${label} is a radio; select another one in its group instead`);
    el.click();
    if (el.checked !== want) throw Error(`${label} did not become ${want ? 'checked' : 'unchecked'}`);
    return { out: `${label} now ${want ? 'checked' : 'unchecked'}` };
  }
  if (el instanceof HTMLSelectElement) {
    const opt = [...el.options].find((o) => o.value === value) ?? [...el.options].find((o) => norm(o.label) === value);
    if (!opt) throw Error(`${label} has no option "${value}"; options: ${[...el.options].map((o) => o.label).join(' | ')}`);
    el.value = opt.value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return { out: `${label} set to "${norm(opt.label)}"` };
  }
  if (el.isContentEditable) {
    el.focus();
    document.execCommand('selectAll');
    document.execCommand('insertText', false, value);
    return { out: `${label} typed` };
  }
  setValue(el, value);
  return { out: `${label} filled` };
}

// One poll of the conditions; bin/umb repeats it until done or timeout. Run from the wrapper so a navigation cannot kill it.
function wait(a, state) {
  const f = a.flags, body = document.body?.innerText ?? '', pending = [];
  if (f.text !== undefined && !body.includes(f.text)) pending.push(`text "${f.text}" is not on the page`);
  if (f.gone !== undefined && body.includes(f.gone)) pending.push(`text "${f.gone}" is still on the page`);
  if (f.url !== undefined && !location.href.includes(f.url)) pending.push(`url does not contain "${f.url}" (now ${location.href})`);
  if (f.ref !== undefined || f.css !== undefined) {
    const sel = f.css ?? state.sel?.[(f.ref || '').slice(1)]?.selector;
    if (!sel) throw Error(`unknown ref ${f.ref}; run umb snap first`);
    if (!byCss(sel).some(visible)) pending.push(`no visible element for ${f.css !== undefined ? 'css ' + f.css : 'ref ' + f.ref}`);
  }
  return pending.length ? { done: false, out: pending.join('; ') } : { done: true, out: 'ok' };
}

const lineOf = (e, min) =>
  '  '.repeat(Math.min(e.depth - min, 6)) + (e.ref ? e.ref + ' ' : '') + e.role +
  (e.unnamed ? '' : ` "${e.name}"`) + (e.details ? ` [${e.details}]` : '');

function snap(a, state) {
  const f = a.flags, max = Number(f.max) || (f.find ? 1000 : 80);
  const r = capture({ compact: true, expandNavigation: false, depth: 10, interactive: !!f.interactive, maxCandidates: 1600,
    maxItems: max, rootSelector: f.within || null, rootRole: null, rootName: null, reportRootFallback: true });
  // Refs are keyed by selector+role+name and reset when the tab's URL changes.
  const st = state.url === location.href ? state : { url: location.href, next: 1, ids: {}, sel: {}, snaps: {} };
  const min = Math.min(...r.entries.map((e) => e.depth), 99);
  for (const e of r.entries) {
    if (!e.selector) continue;
    const key = [e.selector, e.role, e.name].join('|');
    const n = (st.ids[key] ??= st.next++);
    e.ref = 'e' + n;
    st.sel[n] = { selector: e.selector, label: e.role + (e.unnamed ? '' : ` "${e.name}"`) };
  }
  const lines = r.entries.map((e) => lineOf(e, min));
  const sig = JSON.stringify([!!f.interactive, f.within, max]);
  let shown = lines, delta = false;
  st.snaps ??= {};
  const prev = st.snaps[sig];
  if (f.delta && prev) {
    const old = new Set(prev.map((l) => l.trim())), now = new Set(lines.map((l) => l.trim()));
    shown = [...lines.filter((l) => !old.has(l.trim())).map((l) => '+ ' + l.trim()),
             ...prev.filter((l) => !now.has(l.trim())).map((l) => '- ' + l.trim())];
    delta = true;
  }
  st.snaps[sig] = lines;  // delta compares with the last snap that used the same settings
  let total = shown.length;
  if (f.find) {
    const re = new RegExp(f.find, 'i');
    shown = shown.filter((l) => re.test(l));
  }
  const notes = [...(r.notes || [])];
  if (delta && !total) notes.push('no changes since the last snap');
  else if (f.find && !shown.length) notes.push(`no lines match /${f.find}/i (of ${total})`);
  if (r.truncated) notes.push(`truncated at ${max} elements; use --find, --within or --max`);
  if (r.needsSettle) notes.push('page still loading; snap again');
  return { out: [...shown, ...notes.map((n) => '-- ' + n)].join('\n'), state: st };
}

async function umbMain(op, argv, state) {
  try {
    return await { snap, click, fill, wait }[op](parse(argv), state);
  } catch (e) {
    return { error: e.message };
  }
}
