#!/bin/zsh
# purpose: run a Google Sheets menu command by name through the menu search box and report what opened (run with --tab <id>)
# args: cmd (search text, e.g. "freeze 1 row"), pick (optional: part of the result label to run when it is not the first result)
# returns: "ran: <result label>; side panel or dialog now: <title or none>" (a panel left open by an earlier command still shows)
# verified: 2026-11-26
# Acts on the current selection. Clicks the menu search button instead of pressing Alt+/ so the text can never land in a cell.
# Fails, without pressing Enter, when no result matches. Toggles (bold, number formats) show [checked] in: umb snap <tab> --find 'option "Bold'.
setopt extendedglob
UMB=${UMB:-umb}
[ -n "$UMB_TAB" ] || { echo "step failed: tab: pass --tab <id> of an open spreadsheet" >&2; exit 1; }
CMD=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("cmd",""))' "$1")
PICK=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("pick",""))' "$1")
[ -n "$CMD" ] || { echo "step failed: args: cmd is required" >&2; exit 1; }
js() { "$UMB" evaluate_script --pageId "$UMB_TAB" "$1" | python3 -c 'import json,sys; t=sys.stdin.read().strip(); print(json.loads(t) if t else "")'; }
fail() { "$UMB" keys "$UMB_TAB" key:Escape >/dev/null 2>&1; echo "step failed: $1: $2" >&2; exit 1; }

"$UMB" keys "$UMB_TAB" key:Escape click:css:button.assisted-actions-omnibox-button "type:$CMD" wait:500 >/dev/null || fail search "could not open the menu search; is this a Sheets tab?"
LABELS=$(js '() => [...document.querySelectorAll("[role=option]")].filter(e => e.getBoundingClientRect().width).map(e => (e.getAttribute("aria-label") || e.innerText).replace(/\s+/g, " ").trim()).join("\n")')
LABELS=("${(@f)LABELS}")
# The search always pads its list with unrelated items (Find in document, Font list): only a label with the command's first word counts.
STEM=${${(L)${CMD%% *}}[1,4]}
IDX=${LABELS[(i)(#i)*${STEM}*]}
(( IDX <= ${#LABELS} )) || fail search "no menu command matches \"$CMD\""
if [ -n "$PICK" ]; then
  IDX=${LABELS[(i)(#i)*${PICK}*]}
  (( IDX <= ${#LABELS} )) || fail pick "no result contains \"$PICK\"; results: ${(j: | :)LABELS[1,6]}"
fi
# Some panels (Chart editor) need over a second to load: after Enter, wait until the title changes, at most 2.4 s.
TITLE='() => { const v = (s) => [...document.querySelectorAll(s)].find((e) => e.getBoundingClientRect().width); const t = v(".waffle-sidebar-title-text") || v("[role=dialog] [role=heading], [role=dialog] h1, [role=dialog] h2, .modal-dialog-title-text"); return t ? t.innerText.trim() : "" }'
BEFORE=$(js "$TITLE")
steps=(); for ((i = 1; i < IDX; i++)); do steps+=(key:ArrowDown); done
"$UMB" keys "$UMB_TAB" "${steps[@]}" key:Enter wait:300 >/dev/null || fail run "Enter was not accepted"
for i in 1 2 3 4 5 6 7 8; do OPENED=$(js "$TITLE"); [ -n "$OPENED" ] && [ "$OPENED" != "$BEFORE" ] && break; sleep 0.3; done
echo "ran: ${LABELS[$IDX]}; side panel or dialog now: ${OPENED:-none}"
