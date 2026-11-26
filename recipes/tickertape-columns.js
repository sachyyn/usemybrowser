// purpose: add filters as columns to the TickerTape equity screener table and confirm they show
// args: columns (list of filter names, e.g. ["Debt to Equity","5Y Revenue Growth"])
// returns: lines "columns: ...", "already present: ...", "substituted: asked -> used", then up to 3 "row: ..." lines
// verified: 2026-11-26
// url: https://www.tickertape.in/screener/equity
// Never exports, saves or renames a screen. Clicking a selected filter removes it, so columns already in the table are skipped.
const step = async (name, fn) => { try { return await fn(); } catch (e) { throw Error(e.message.startsWith('step failed') ? e.message : `step failed: ${name}: ${e.message}`); } };
const lc = (s) => s.toLowerCase();
const headers = () => [...document.querySelectorAll('table th')].map((t) => norm(t.innerText).replace(/^[↑↓]\s*/, '')).filter(Boolean);
const has = (name) => headers().some((h) => lc(h) === lc(name));
const box = () => document.querySelector('input.filter-search');
const labels = () => [...document.querySelectorAll('.checkbox-root')].filter((e) => e.getClientRects().length).map((e) => norm(e.innerText));
const search = async (q) => { await umb.fill('css:"input.filter-search"', q); await umb.sleep(800); return labels(); };

if (!Array.isArray(args.columns) || !args.columns.length) throw Error('step failed: args: columns must be a non-empty list');
await step('load table', () => umb.wait(() => headers().length > 3, 20000));
const present = [], substituted = {}, added = [];
for (const want of args.columns) {
  if (has(want)) { present.push(want); continue; }
  await step(`open Add Filter for "${want}"`, async () => {
    if (!box()) { await umb.click('text:"Add Filter"'); await umb.wait(box, 5000); }
  });
  const used = await step(`find "${want}"`, async () => {
    let found = await search(want);
    // No hit: search the last two words and keep labels that contain every word asked for ("5Y Revenue Growth" finds "5Y Historical Revenue Growth").
    if (!found.length) found = await search(want.split(/\s+/).slice(-2).join(' '));
    const words = lc(want).split(/\s+/);
    const exact = found.filter((l) => lc(l) === lc(want));
    const near = found.filter((l) => words.every((w) => lc(l).split(/\s+/).includes(w)));
    if (exact.length === 1) return exact[0];
    if (near.length === 1) return near[0];
    throw Error(`${found.length ? 'no single closest match' : 'no match'}; candidates: ${found.slice(0, 6).join(' | ') || 'none'}`);
  });
  if (has(used)) { present.push(used); substituted[want] = used; continue; }
  await step(`click "${used}"`, () => umb.click(`text:"${used}"`));
  if (used !== want) substituted[want] = used;
  added.push(used);
  await umb.sleep(500);
}
if (box()) await step('click Done', () => umb.click('text:"Done"'));

const wanted = args.columns.map((c) => substituted[c] ?? c);
await step('verify columns', async () => {
  try { await umb.wait(() => wanted.every(has), 10000); }
  catch { throw Error(`missing from the table header: ${wanted.filter((w) => !has(w)).join(', ')}`); }
});
const rows = [...document.querySelectorAll('table tbody tr')].slice(0, 3).map((r) => 'row: ' + [...r.cells].map((c) => norm(c.innerText)).join(' | '));
return [`columns: ${headers().join(' | ')}`, present.length && `already present: ${present.join(', ')}`,
  ...Object.entries(substituted).map(([a, b]) => `substituted: ${a} -> ${b}`), ...rows].filter(Boolean).join('\n');
