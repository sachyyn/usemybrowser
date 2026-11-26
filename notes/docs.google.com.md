# Google Sheets (docs.google.com/spreadsheets)
Every line below was run on a real sheet and read back. <t> = tab id, `--tab <t>` for recipes.
The grid is a canvas: read it with sheets-read / sheets-formula, not `snap`. Take `look` only for pure looks.

## Cells
- Go to / select: `umb keys <t> key:Escape click:css:#t-name-box type:C2:C5 key:Enter`. `Sheet2!A1` also switches tab. Read the selection: `umb text <t> '#t-name-box'`.
- Paste a block (tab = next cell, newline = next row, `=...` stays a formula): `umb keys <t> key:Escape click:css:#t-name-box type:A1 key:Enter paste:@/abs/block.tsv`. Never `type:` formulas or blocks (suggestions corrupt them, slow).
- Values: `umb recipe sheets-read '{"sheet":"Sheet1","range":"A1:C5"}' --tab <t>` (shows formatting, e.g. $10.00; text inside a numeric column can come back empty).
- Formulas: `umb recipe sheets-formula '{"cells":["C3"]}' --tab <t>`.

## Spreadsheet and tabs
- Rename spreadsheet: `umb keys <t> click:css:input.docs-title-input clear "type:New name" key:Enter` (the output says `title -> "New name - Google Sheets"`).
- Add tab (becomes active): `umb keys <t> key:Escape key:Shift+F11 wait:700`.
- Rename the active tab: `umb recipe sheets-tab-rename '{"name":"Data"}' --tab <t>` (needs a right click; prints all tab names, active one marked *).
- Switch tab: `umb keys <t> key:Escape key:Alt+ArrowDown` (next) or `key:Alt+ArrowUp`. Or `umb click <t> text:Sheet3 --read '.docs-sheet-active-tab'`; it fails with "matched 2" when the tab is named like a menu (Data, View, Format).
- List tabs: `umb evaluate_script --pageId <t> '() => [...document.querySelectorAll(".docs-sheet-tab")].map(t=>t.innerText.trim()+(t.classList.contains("docs-sheet-active-tab")?"*":"")).join(",")'`.

## Menu search (acts on the current selection)
`umb recipe sheets-menu '{"cmd":"freeze 1 row"}' --tab <t>`. Add `"pick":"rounded"` to run a result that is not first.
- One step, done: `bold` (toggle), `freeze 1 row` / `freeze no rows`, `format as currency`, `number format: automatic`, `clear formatting`, `insert chart` (creates and selects the chart).
- Opens a panel, you finish it: `conditional formatting`, `data validation`, `named ranges` ("Define named range" form; the name box is shorter, see below).
- Careful: the first word is matched loosely. `delete ...` runs "Delete values" on the selection. Never guess a destructive command.
- The recipe reads "side panel now" from the page; a panel opened earlier stays listed, so `freeze` says the old title.

## Named range
- `umb keys <t> key:Escape click:css:#t-name-box type:A2:C5 key:Enter click:css:#t-name-box type:sales key:Enter wait:500`, then `umb text <t> '#t-name-box'` prints `sales`.
- Typing a name that does not exist CREATES one on the selection. Typing a new name over an already named range RENAMES it. The name box also jumps to a name.
- All names with ranges: `umb recipe sheets-menu '{"cmd":"named ranges"}' --tab <t>` then `umb text <t> .waffle-sidebar-container 600`; close the form with `umb click <t> text:Cancel`.

## Conditional format: greater than N, green fill
The default fill is already green (#b7e1cd). Select the range first (`#t-name-box` line above), then one command:
`umb keys <t> click:css:button.assisted-actions-omnibox-button "type:conditional formatting" wait:500 key:Enter wait:900 'click:text:"Is not empty"' 'click:text:"Greater than"' click:css:input.waffle-conditionalformat-arg1 type:15 --read .waffle-sidebar-container`
Read it back before saving (inputs show in brackets): `[C2:C5]` `[15]` and "Greater than". Then save and read the rule list: `umb keys <t> click:text:Done wait:500` and `umb snap <t> --find 'Value is'` gives `option "Background #b7e1cd ... Value is greater than 15 C2:C5"`.
If the range already has rules, the panel opens on the rule list: click `'text:+Add another rule'` first. Remove a rule: `umb click <t> 'css:[aria-label^="Remove rule"]' --force`.

## Dropdown limited to a list
`umb recipe sheets-validate-list '{"range":"E2:E5","options":["East","North","West","South"]}' --tab <t>`. It fills each option box by its own ref, compares all boxes with your list before Done, and fails without saving on a mismatch. Remove an old rule first: open `data validation` and `click text:"Remove all"`.
Proof after saving: type a wrong value in one cell: `umb keys <t> click:css:#t-name-box type:E2 key:Enter type:bogus key:Enter`, then `umb text <t> '[role=alertdialog]'` lists the allowed values; `umb click <t> text:OK`.

## Chart
Select the range, `umb recipe sheets-menu '{"cmd":"insert chart"}' --tab <t>` (opens "Chart editor"; a header row and a label column give a column chart). Confirm: `umb evaluate_script --pageId <t> '() => document.querySelectorAll(".waffle-objwrap-gvizchart").length'` goes up by one, and `umb snap <t> --find 'Chart Type'` says `Column chart`. Each run adds a chart; there is no cheap delete.

## Check formatting without a screenshot
- Bold, number format: `umb keys <t> click:css:button.assisted-actions-omnibox-button type:bold wait:500 >/dev/null; umb snap <t> --find 'option "Bold'` shows `[checked]` or `[unchecked]` for the active cell; then `key:Escape`.
- Currency: sheets-read shows `$10.00`; plain numbers show `10`.
- Frozen rows: `umb evaluate_script --pageId <t> '() => Math.round(document.querySelector(".freezebar-horizontal-handle").getBoundingClientRect().top)'`: 161 none, 187 one row, 208 two (default row height, 100% zoom; taller rows shift it).
- Fill colour of a rule: the rule list line above (`Background #hex`). Colour of plain cells, borders, column widths: only `umb look`.
