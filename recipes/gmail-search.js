// purpose: search Gmail, list the matches newest first; with open: true also read the newest match
// args: query (Gmail search), account (index, default 0), limit (default 10), open (default false; opening marks the mail read)
// returns: lines "date | from | subject | unread|read", newest first, then "-- showing N of M rows"; with open, a blank line and the first 1500 chars of the newest body
// verified: 2026-11-26
// url: https://mail.google.com/mail/u/{account|0}/#search/{query}
// Read-only: never sends, archives, deletes or labels. Rows come from the first page of results only.
const step = async (name, fn) => { try { return await fn(); } catch (e) { throw Error(`step failed: ${name}: ${e.message}`); } };

await step('wait for results', () =>
  umb.wait(() => /#search/.test(location.hash) && (document.querySelector('tr.zA') || /No messages matched/.test(document.body.innerText)), 25000));
if (!document.querySelector('tr.zA')) return '0 rows';

const rows = await step('read rows', () => [...document.querySelectorAll('tr.zA')].map((r) => {
  const title = r.querySelector('.xW span')?.title, t = Date.parse(title);
  const from = r.querySelector('.yW span')?.innerText, subject = r.querySelector('.bog')?.innerText;
  if (isNaN(t) || !from || !subject) throw Error(`row has date "${title}", from "${from}", subject "${subject}"`);
  const d = new Date(t), p = (n) => String(n).padStart(2, '0');
  return { r, t, line: `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())} | ${from} | ${subject} | ${r.classList.contains('zE') ? 'unread' : 'read'}` };
}));
rows.sort((a, b) => b.t - a.t);
const limit = args.limit ?? 10;
let out = rows.slice(0, limit).map((x) => x.line).join('\n') + `\n-- showing ${Math.min(limit, rows.length)} of ${rows.length} rows`;

if (args.open) {
  rows[0].r.querySelector('.bog').setAttribute('data-umb', 'newest');
  await step('open newest', () => umb.click('css:"[data-umb=newest]"'));
  await step('wait for body', () => umb.wait(() => document.querySelector('.a3s')?.innerText.trim(), 15000));
  out += '\n\n' + await step('read body', () => umb.text('.a3s', 1500));
}
return out;
