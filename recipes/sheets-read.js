// purpose: read the cell values of a range in an open Google Sheets tab as compact tab-separated lines (run with --tab <id>)
// args: sheet (tab name, e.g. "Sheet1"), range (A1 notation, e.g. "A1:C20"), headers (optional number of header rows; pass 0 to keep every row as data)
// returns: one line per row, cells separated by a tab; tabs and line breaks inside a cell become spaces
// verified: 2026-11-26
// Read-only: one same-origin GET to /spreadsheets/d/<id>/gviz/tq (works on private sheets, uses the signed-in account). It returns values as shown,
// so a formula cell gives its result. Quirk: gviz types each column, and a text cell in a mostly numeric column can come back empty.
const step = async (name, fn) => { try { return await fn(); } catch (e) { throw Error(e.message.startsWith('step failed') ? e.message : `step failed: ${name}: ${e.message}`); } };
const id = /\/spreadsheets\/d\/([\w-]+)/.exec(location.pathname)?.[1];
if (!id) throw Error('step failed: tab: not a Google Sheets tab; pass --tab <id> of an open spreadsheet');
if (!args.sheet || !args.range) throw Error('step failed: args: sheet and range are required');

const csv = await step('fetch', async () => {
  const q = `tqx=out:csv&sheet=${encodeURIComponent(args.sheet)}&range=${encodeURIComponent(args.range)}` + (args.headers === undefined ? '' : `&headers=${Number(args.headers)}`);
  const r = await fetch(`/spreadsheets/d/${id}/gviz/tq?${q}`, { credentials: 'include' });
  const t = await r.text();
  if (!r.ok || /^\s*</.test(t)) throw Error(`HTTP ${r.status}; is the sheet "${args.sheet}" there and the range valid?`);
  return t;
});

// Minimal CSV reader: quoted cells, doubled quotes, line breaks inside quotes.
const rows = [[]];
for (let i = 0, cell = '', quoted = false; i <= csv.length; i++) {
  const c = csv[i], row = rows[rows.length - 1];
  if (i === csv.length) { if (cell || row.length) row.push(cell); break; }
  if (quoted) { if (c === '"' && csv[i + 1] === '"') { cell += '"'; i++; } else if (c === '"') quoted = false; else cell += c; }
  else if (c === '"') quoted = true;
  else if (c === ',') { row.push(cell); cell = ''; }
  else if (c === '\n') { row.push(cell); cell = ''; rows.push([]); }
  else if (c !== '\r') cell += c;
}
if (!rows[rows.length - 1].length) rows.pop();
return rows.map((r) => r.map((c) => c.replace(/[\t\r\n]+/g, ' ')).join('\t')).join('\n');
