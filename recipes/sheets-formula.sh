#!/bin/zsh
# purpose: read the formula (or typed value) of single cells in an open Google Sheets tab (run with --tab <id>)
# args: cells (list of cells, each optionally with a sheet, e.g. ["Sheet1!C2","Summary!B9"])
# returns: one line per cell: the cell, a tab, the formula bar text (a formula starts with =; a plain value is shown as typed; empty if the cell is empty)
# verified: 2026-11-26
# Read-only, but it moves the selected cell: each cell is reached with the name box and real keys (Escape first, so a cell being edited is left as it is).
# For many cells in one block, sheets-read returns the values in one call; this one is for the formulas behind them.
UMB=${UMB:-umb}
[ -n "$UMB_TAB" ] || { echo "step failed: tab: pass --tab <id> of an open spreadsheet" >&2; exit 1; }
CELLS=("${(@f)$(python3 -c 'import json,sys; [print(c) for c in json.loads(sys.argv[1]).get("cells", [])]' "$1")}")
[ -n "${CELLS[1]}" ] || { echo "step failed: args: cells must be a non-empty list" >&2; exit 1; }
for cell in "${CELLS[@]}"; do
  [[ "$cell" =~ '^[A-Za-z0-9_ .!$:-]+$' ]] || { echo "step failed: $cell: not a cell reference" >&2; exit 1; }
  out=$("$UMB" keys "$UMB_TAB" key:Escape 'click:css:#t-name-box' "type:$cell" key:Enter --read '#t-formula-bar-input' --read-max 500) \
    || { echo "step failed: $cell: ${out:0:200}" >&2; exit 1; }
  lines=("${(@f)out}")  # line 1 is keys' own summary; the rest is the formula bar
  printf '%s\t%s\n' "$cell" "${${(j: :)lines[2,-1]}//$'\t'/ }"
done
