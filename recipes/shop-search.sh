#!/bin/zsh
# purpose: search shopping sites and list the top non-sponsored results as "site | title | price"
# args: query; sites (default ["amazon.in","flipkart","meesho"]); limit per site (default 3)
# returns: one line per result; a line "step failed: <site>: <why>" per site that failed (exit 1 if any did). Meesho cards often have no real title: those show "[no real title]".
# verified: 2026-11-26
# Opens one background tab per site, one after the other with a pause between, and closes each. A bot check is reported, never retried.
UMB=${UMB:-umb}
read_arg() { python3 -c 'import json,sys; a=json.loads(sys.argv[1]); v=a.get(sys.argv[2], json.loads(sys.argv[3])); print("\n".join(v) if isinstance(v, list) else v)' "$1" "$2" "$3"; }
QUERY=$(read_arg "$1" query null); [[ "$QUERY" == None ]] && { echo "step failed: args: query is required" >&2; exit 1; }
LIMIT=$(read_arg "$1" limit 3)
SITES=(${(f)"$(read_arg "$1" sites '["amazon.in","flipkart","meesho"]')"})
ENC=$(python3 -c 'import sys,urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$QUERY")

js_head() { cat <<'JS'
const site = args.site;
const fail = (why) => { throw Error(`step failed: ${site}: ${why}`); };
const blocked = () => /captcha|not a robot|access denied|unusual traffic|verify you are human/i.test(document.title + ' ' + document.body.innerText.slice(0, 600));
const price = (s) => (/₹\s?[\d,]+(\.\d+)?/.exec(s) || [''])[0].replace(/\s/g, '');
JS
}
js_tail() { cat <<'JS'
try { await umb.wait(() => rows().length || blocked(), 20000); } catch { fail('no results appeared within 20s'); }
if (blocked()) fail('blocked by a bot check; not retrying');
const seen = new Set(), items = rows().filter((r) => r.title && !seen.has(r.title) && seen.add(r.title)).slice(0, args.limit);
if (!items.length) fail('results had no readable titles');
return items.map((r) => `${site} | ${r.title.slice(0, 80)}${r.note || ''} | ${r.price || '(no price)'}`).join('\n');
JS
}
js_amazon() { cat <<'JS'
const rows = () => [...document.querySelectorAll('div[data-component-type=s-search-result]')]
  .filter((c) => !c.querySelector('.puis-sponsored-label-text'))
  .map((c) => ({ title: c.querySelector('h2')?.innerText.trim(), price: price(c.querySelector('.a-price .a-offscreen')?.textContent || '') }));
JS
}
js_flipkart() { cat <<'JS'
const rows = () => [...new Set([...document.querySelectorAll('a[href*="/p/"]')].map((a) => a.closest('div[data-id]')).filter(Boolean))]
  .filter((c) => !/(^|\n)Ad(\n|$)/.test(c.innerText))
  .map((c) => ({ title: c.querySelector('a[title]')?.title.trim(), price: price(c.innerText) }));
JS
}
js_meesho() { cat <<'JS'
const rows = () => [...document.querySelectorAll('a[href*="/p/"]')].map((a) => {
  const title = (a.querySelector('img')?.alt || '').trim();
  return { title, price: price(a.innerText), note: title.split(/\s+/).length < 3 ? ' [no real title]' : '' };
});
JS
}

rc=0
for site in $SITES; do
  case $site in
    amazon.in) url="https://www.amazon.in/s?k=$ENC"; fn=amazon ;;
    flipkart)  url="https://www.flipkart.com/search?q=$ENC"; fn=flipkart ;;
    meesho)    url="https://www.meesho.com/search?q=$ENC"; fn=meesho ;;
    *) echo "step failed: $site: unknown site" ; rc=1; continue ;;
  esac
  [[ $site != $SITES[1] ]] && sleep 4
  tab=$($UMB open "$url") || { echo "step failed: $site: could not open the page"; rc=1; continue; }
  tab=${tab%% *}
  { js_head; js_$fn; js_tail; } | $UMB run $tab - "{\"site\":\"$site\",\"limit\":$LIMIT}" --max 3000 | sed '$d'
  [[ ${pipestatus[2]} -eq 0 ]] || rc=1
  $UMB close $tab >/dev/null
done
exit $rc
