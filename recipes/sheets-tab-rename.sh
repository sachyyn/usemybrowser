#!/bin/zsh
# purpose: rename the active tab of an open Google Sheets spreadsheet and check the new name (run with --tab <id>)
# args: name (the new tab name)
# returns: the tab names, the active one marked with *
# verified: 2026-11-26
# Why a recipe: the tab menu only opens on a right click, which umb click cannot send; the page script sends the mouse events, then keys do the rest.
UMB=${UMB:-umb}
[ -n "$UMB_TAB" ] || { echo "step failed: tab: pass --tab <id> of an open spreadsheet" >&2; exit 1; }
NAME=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("name",""))' "$1")
[ -n "$NAME" ] || { echo "step failed: args: name is required" >&2; exit 1; }
"$UMB" keys "$UMB_TAB" key:Escape >/dev/null
"$UMB" run "$UMB_TAB" - >/dev/null <<'JS' || { echo "step failed: menu: no active tab found; is this a Sheets tab?" >&2; exit 1; }
const t = document.querySelector('.docs-sheet-active-tab'); if (!t) throw Error('no active tab');
const r = t.getBoundingClientRect(), o = { bubbles: true, cancelable: true, button: 2, buttons: 2, clientX: r.left + 20, clientY: r.top + 10 };
for (const type of ['mousedown', 'mouseup', 'contextmenu']) t.dispatchEvent(new MouseEvent(type, o));
JS
out=$("$UMB" keys "$UMB_TAB" 'click:text:Rename' clear "type:$NAME" key:Enter wait:300 2>&1) || { "$UMB" keys "$UMB_TAB" key:Escape >/dev/null 2>&1; echo "step failed: rename: ${out:0:200}" >&2; exit 1; }
tabs=$("$UMB" evaluate_script --pageId "$UMB_TAB" '() => [...document.querySelectorAll(".docs-sheet-tab")].map((t) => t.innerText.trim() + (t.classList.contains("docs-sheet-active-tab") ? "*" : "")).join(",")' | python3 -c 'import json,sys; print(json.loads(sys.stdin.read().strip()))')
[[ ",$tabs," == *",$NAME*,"* ]] || { echo "step failed: check: expected the active tab to be \"$NAME\", got: $tabs" >&2; exit 1; }
echo "$tabs"
