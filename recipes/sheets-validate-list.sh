#!/bin/zsh
# purpose: make a range of an open Google Sheets spreadsheet a dropdown limited to a list of values, and prove the list before saving (run with --tab <id>)
# args: range (A1 notation on the active tab, e.g. "E2:E5"), options (list of values, at least 2, no empty strings)
# returns: "dropdown on <range>: <value>, <value>, ..."
# verified: 2026-11-26
# Why a recipe: the option boxes shift as items are added, and typing by position put text into the wrong boxes. This fills each box by its own ref,
# reads every box back from the page before Done, and fails (rule not saved) when they differ. Remove an older rule on the range first.
UMB=${UMB:-umb}
[ -n "$UMB_TAB" ] || { echo "step failed: tab: pass --tab <id> of an open spreadsheet" >&2; exit 1; }
RANGE=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("range",""))' "$1")
OPTS=("${(@f)$(python3 -c 'import json,sys; [print(o) for o in json.loads(sys.argv[1]).get("options", [])]' "$1")}")
[[ "$RANGE" =~ '^[A-Za-z0-9_ .!$:-]+$' ]] || { echo "step failed: args: range must be an A1 range" >&2; exit 1; }
(( ${#OPTS} >= 2 )) && [ -n "${OPTS[1]}" ] || { echo "step failed: args: options needs at least 2 values" >&2; exit 1; }
SIDE='.waffle-datavalidation-sidebar'
fail() { "$UMB" keys "$UMB_TAB" key:Escape >/dev/null 2>&1; echo "step failed: $1: $2" >&2; exit 1; }
boxes() { "$UMB" snap "$UMB_TAB" --within "$SIDE" --interactive 2>&1 | sed -n 's/.*\(e[0-9][0-9]*\) textbox "Value".*/\1/p'; }
ref_of() { "$UMB" snap "$UMB_TAB" --within "$SIDE" --interactive 2>&1 | sed -n "s/.*\(e[0-9][0-9]*\) button \"$1\".*/\1/p" | head -1; }

"$UMB" keys "$UMB_TAB" key:Escape click:css:#t-name-box "type:$RANGE" key:Enter >/dev/null || fail range "could not select $RANGE"
"$UMB" recipe sheets-menu '{"cmd":"data validation"}' --tab "$UMB_TAB" >/dev/null || fail menu "could not open the Data validation panel"
sleep 0.5
add=$(ref_of "Add rule"); [ -n "$add" ] || fail panel "no Add rule button; is the Data validation panel open?"
"$UMB" click "$UMB_TAB" "$add" >/dev/null || fail panel "could not add a rule"
sleep 0.6
for ((n = 1; n <= ${#OPTS}; n++)); do
  refs=($(boxes))
  while (( ${#refs} < n )); do
    more=$(ref_of "Add another item"); [ -n "$more" ] || fail options "no Add another item button"
    "$UMB" click "$UMB_TAB" "$more" >/dev/null || fail options "could not add item $n"
    refs=($(boxes))
  done
  "$UMB" fill "$UMB_TAB" "${refs[$n]}" "${OPTS[$n]}" >/dev/null || fail "option $n" "could not fill ${OPTS[$n]}"
done
got=("${(@f)$("$UMB" text "$UMB_TAB" "$SIDE" 2000 | sed -n 's/^\[\(.*\)\]$/\1/p')}")
[[ "${got[1]}" == *"$RANGE" ]] || fail readback "range box shows \"${got[1]}\", wanted $RANGE"
[[ "${(j:|:)got[2,-1]}" == "${(j:|:)OPTS}" ]] || fail readback "options are \"${(j:, :)got[2,-1]}\", wanted \"${(j:, :)OPTS}\""
"$UMB" click "$UMB_TAB" 'text:Done' >/dev/null || fail done "could not press Done"
sleep 0.6
"$UMB" text "$UMB_TAB" '.waffle-sidebar-container' 600 | grep -q "${RANGE##*!}" || fail check "the rule for $RANGE is not in the rule list"
echo "dropdown on $RANGE: ${(j:, :)OPTS}"
