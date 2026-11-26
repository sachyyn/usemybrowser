# Moving from v1 to v2

v2 replaces the `helium` command with `umb`. It uses the same daemon, the same pinned chrome-devtools-mcp (1.13.0 in `~/.local/share/helium-cdt`) and the same one Allow click per browser launch. Run `./install.sh`; it leaves an old `helium` script and the old `helium-browser` skill folder in place until you choose to switch (`./install.sh --force` points `helium` at `umb`).

## Command mapping

| v1 | v2 |
|---|---|
| `helium list_pages` | `umb tabs` |
| `helium new_page <url>` | `umb open <url> [--profile p]` (prints only the new tab) |
| `helium compact <id>` | `umb snap <tab>` |
| `helium find <id> '<regex>'` | `umb snap <tab> --find '<regex>'` |
| `take_snapshot` uids (`17_4`), new after every load | refs (`e12`), stable while the element is the same |
| `helium click <id> <uid>`, `fill` | `umb click <tab> <target>`, `umb fill`: a ref, `text:"..."` or `css:"..."`, checked for cover and ambiguity |
| `press_key` one at a time | `umb keys <tab> key:... type:... paste:...` in one command |
| `evaluate_script` with a long arrow function | `umb run <tab> <file or ->` with `umb.find/click/fill/wait` helpers |
| `evaluate_script --waitForStableDom` | `umb wait`, or `--expect` on the action |
| `take_screenshot` opened by the agent | `umb look`, `umb check`, or `umb shot --region` |
| `helium text`, `helium check` | `umb text`, `umb check` (same idea) |
| `LESSONS.md` site notes | `notes/<host>.md`, read with `umb notes <host>`; new lessons saved with `umb note <host> "<text>"` to `~/.config/umb/notes/` |
| `open -na Helium --args --profile-directory=...` | `umb open <url> --profile <folder or name>`, or `UMB_PROFILE` |

## Refused now

- Acting on a tab `umb` did not open. Click, fill, keys, run, `recipe --tab`, close and any pass-through command that can change a tab fail on the user's own tabs. Reads still work on every tab. To act on one of your tabs, run `umb lend <tab>` (and `umb unlend <tab>` after). Closing a lent tab needs `--force`.
- A click on a covered element, or on a target that matches more than one element. The error names what is on top or how many matched. `--force` skips the cover check.

## Same as before

- One daemon, one connection, one Allow per launch. Never start another debugging connection.
- Any `chrome-devtools` command still passes through: `umb <command> --help`.
- `decide` is unchanged.
- The ask-first rules in the skill: purchases, payments, email, posting, forms, deleting, account settings.
- macOS only, tested on Helium.
