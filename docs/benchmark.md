# Benchmark

## Phase 0: v1 baseline and spikes (2026-11-26)

One Mac, Helium, chrome-devtools-mcp 1.13.0. Each task ran once, in a fresh agent session on a mid-size model, with the v1 skill and lessons file read first. Single runs: treat the numbers as rough.

### v1 baseline

| Task | Agent tool calls | `helium` commands | Failed or repeated | Tokens | Time |
|---|---|---|---|---|---|
| Gmail: find the newest email from one sender, read its body | 8 | 6 | 3 redundant | 68k | 63 s |
| Shopping: top 3 results on three sites | 7 | 8 | 1 redundant | 67k | 70 s |
| Screener: add 8 filter columns, read the table | 19 | about 85 (agent's own count) | about 20 | 74k | 238 s |

What cost the most:

- **Screener.** A click closed the filter dialog, element ids went stale, and the agent redid filters one at a time. Two filters were added twice. This is the stale-id and no-feedback problem.
- **Gmail.** Search results were not in date order. Three calls went to finding the newest row.
- **Shopping.** One call went to finding the id of the tab the agent had just opened, because opening a tab prints the whole tab list.
- **Every task.** The upstream "update available" notice adds about 150 characters per command. Opening and closing a tab each print every open tab.

v1 is already lean on read tasks, because the lessons file holds working selectors. The big cost is multi-step action tasks.

### Spike: browse's page capture script

`capture.js` from browse (commit `27bdfbb`) ran unchanged through `evaluate_script --sourcePath`.

| Page | Raw snapshot | v1 `compact` | Capture script | Refs that point at exactly one element | Time in page |
|---|---|---|---|---|---|
| Chrome DevTools docs overview | 21,251 chars | 5,444 | 3,737 | 50 of 54 | 11 ms |
| TickerTape screener | 11,333 | 1,829 | 4,394 | 43 of 43 | 13 ms |

- On the docs page it scoped to the main area and said what it left out.
- On the screener it is larger than `compact` because it keeps the table rows. `compact` drops them. A controls-only mode would be smaller.
- It did not scope to the screener's filter dialog, which is not marked as a dialog.
- Clickable plain-text items in that dialog got no ref. A find-by-text helper is needed next to refs.

### Spike: clicks and typing from a page script

- A scripted click opened the screener's filter dialog. Scripted typing into its search box filtered the list. The screener is a React app.
- The Gmail baseline agent opened an email with a scripted click.
- The whole 8-column screener task ran as one script in one command. It reported "added" for all eight filters, but only five became columns: two were already on, so the click turned them off, and one did not appear.

### Decision

**Option A: page scripts only.** Scripted clicks and typing work on all three benchmark sites, so no real-input path and no new daemon for now. Options B and C stay in the plan as fallbacks.

Two requirements follow from the spikes:

1. Every action and every recipe verifies the result. "The click ran" is not "it worked".
2. Helpers need find-by-text, and toggles need a check of the current state before clicking.

## After phases 1 and 2: screener task rerun (2026-11-26)

Same task, same model size, fresh session, using `umb snap`, `click`, `fill`, `wait` and `evaluate_script`. No `run` command and no recipes yet. One run.

| Measure | v1 | v2 so far | Change |
|---|---|---|---|
| Agent tool calls | 19 | 12 | 37% fewer |
| Wrapper commands | about 85 (agent's estimate) | 36 (usage log) | about 58% fewer |
| Failed commands | about 20 | 0 | |
| Repeats | not counted | 4 | |
| Tokens (session total) | 74k | 66k | 11% fewer |
| Time | 238 s | 164 s | 31% fewer |
| Page text returned | 6,000 to 7,000 chars (estimate) | 13,934 chars (usage log) | more |
| Result correct | yes, after redoing 5 filters | yes, first pass, verified from the table | |

Reading it:

- Failures went from about 20 to 0. Stable refs and the checks in `click` and `fill` removed the redo loop.
- Tool calls are 37% down, just under the 40% bar, before recipes exist.
- Page text returned went up, not down. The agent read the dialog's search results with `evaluate_script` because `snap` did not show them. This fails the "no more page text than v1" condition for now.
- Session tokens barely moved, because most of a short session is the fixed prompt and instructions, not page text.

Problems this run found in v2:

1. `snap` shows no line for clickable plain text, such as the filter dialog's search results. `--find` cannot find them either. `click text:"..."` does work on them.
2. `snap --delta` after a plain `snap` printed the whole page. A plain snap did not count as the baseline.
3. The "no lines match" message does not say what was searched.
4. A text target that matches nothing gives no near-miss hint.

## Google Sheets task, three tools, in dollars (2026-11-26)

Harness in `bench/`. Task `sheets-sales`: build a sales workbook in a new Google Sheet through the web UI only (40 data rows, formula columns, formatting, a conditional format, a dropdown validation, a named range, a formula-driven summary tab with four blocks, a column chart). Apps Script, the Sheets API and uploads are not allowed.

Every arm: a fresh headless agent on the same mid-size model, the same task text, personal instruction files off, an $8 cap and a 30-minute limit. Only the tool and its usage guide differ. Dollars are the agent's own reported cost at API prices. A script downloads the finished sheet and checks it; no model judges the result. One run per arm.

| Measure | v1 (`helium`) | v2 (`umb`) | browse 0.1.5 |
|---|---|---|---|
| Cost | $0.64 | $0.57 | $0.41 |
| Agent turns | 70 | 78 | 43 |
| Time | 5.5 min | 5.6 min | 9.4 min |
| Output tokens | 16.6k | 14.4k | 12.4k |
| Cache re-read tokens | 2.19M | 1.69M | 0.85M |
| Checker | all passed | all passed | all passed |

The checker counted 27 items for v1 and v2 and 26 for browse, because it could not read the fill colour in browse's file. All counted items passed in every arm.

Reading it:

- All three tools finished a hard task correctly for well under a dollar.
- browse was cheapest because it took the fewest turns. Its scripts can send real keystrokes, so one call can type a block of cells. It was slowest because it types at human-like speed by default.
- v2 was 11% cheaper than v1 but took more turns, not fewer. Sheets draws its grid on a canvas that page scripts cannot type into, so the v2 agent fell back to one real key command at a time.
- Cost follows turns: the conversation is re-read on every turn, and that re-reading is most of the bill.

v2 usage log for its run: 187 commands, 10 failed, 26 repeats, 30,490 characters returned.

| Command | Count | Failed | Seconds | Characters |
|---|---|---|---|---|
| `click` | 47 | 6 | 58.8 | 2,237 |
| `press_key` | 33 | 0 | 14.0 | 3,959 |
| `type_text` | 25 | 0 | 14.7 | 1,545 |
| `run` | 23 | 0 | 34.3 | 2,252 |
| `snap` | 21 | 0 | 10.1 | 10,873 |
| `take_screenshot` | 14 | 0 | 3.4 | 1,293 |
| `fill` | 10 | 4 | 9.1 | 267 |
| `tabs` | 6 | 0 | 1.1 | 7,514 |

What this says v2 needs:

1. A way to send a sequence of real keys and text in one command, and from inside a `run` script. This is the largest gap against browse.
2. `click` averages 1.25 s. Find out why.
3. `press_key` prints about 120 characters per call and `tabs` about 1,250. Both should be near silent.
4. Relative file paths for screenshots resolve against the daemon's start folder, not the caller's. Make them absolute in the wrapper.

Limits: one run per arm, so differences of this size are suggestive. browse ran with default settings. The checker does not test whether the dropdown rejects bad input or how the chart looks.

## Sheets task: where the money goes, and v2 after acting on it (2026-11-26)

Prices worked out from the bills: $4.00 per million tokens for new material entering the conversation, $0.10 per million for re-reading earlier turns, $10.00 per million for what the agent writes.

A per-turn trace of a v2 run ($0.495, 46 turns) showed 12 screenshots of about 3,000 tokens each: $0.147 entering plus $0.069 re-read, about 40% of the bill. All text returned by the tool was about 3,600 tokens ($0.014). The agents screenshot because Sheets draws cells on a canvas.

Changes made in response: `look` (a small vision model answers, the agent never gets the image), `shot` (small cropped image), `sheets-read` and `sheets-formula` recipes (cells as text), proof flags (`--expect`, `--read`), and `keys` (real input steps in one command, with `paste` for blocks).

A first attempt that typed blocks cell by cell did worse ($0.71, 79 turns, 21.8 min): typing 246 cells passed the agent's 2-minute command limit, typed formulas were corrupted by the app's suggestions, and `look` misread dense grids. Replaced by a one-step paste (41 x 8 cells in 2.6 s) and a guide rule that `look` is for coarse visuals only.

Three runs per tool, same model and task. Screenshot counts are from traced runs.

| Tool | Run 1 | Run 2 | Run 3 | Average | Turns | Screenshots seen by the agent | Checker |
|---|---|---|---|---|---|---|---|
| v1 (`helium`) | $0.64 | $0.51 | $0.61 | $0.59 | 70, 54, 50 | 7 to 12 | all passed |
| browse 0.1.5 | $0.41 | $0.37 | $0.42 | $0.40 | 43, 24, 28 | 15 to 17 | all passed |
| v2 before these changes | $0.57 | $0.50 | | $0.53 | 78, 46 | 12 | passed (one run not scored) |
| v2 with `look`, readers, `keys paste` | $0.38 | $0.40 | $0.35 | $0.38 | 58, 59, 45 | 2, 0, 0 | 27/27, 27/27, 26/27 |

The v2 figures exclude the small vision model's own charge, which was $0.003 to $0.008 per run (10 to 20 calls).

The one failed check: in run 3 the Region dropdown's options were wrong ("EastNorth", "NorthSouth", ...), so text went into the wrong option fields. The run reported success.

Bill split for the three new v2 runs: entering $0.11, re-read $0.10 to $0.13, agent's writing $0.15. Entering cost halved (it was $0.23 to $0.26). The agent's own writing is now the largest part, and turns are still about double browse's.

Reading it:

- v2 went from $0.53 to $0.38 on average, 36% below v1 and level with browse within the noise of three runs.
- browse is still better on turns and had no failed check. v2 had one in three runs.
- Next levers for v2: fewer and shorter commands (app macros such as "go to range", "open menu item"), and a verification step for dialogs with several fields.

## Sheets task with site notes (2026-11-26)

After the runs above, turns were the main cost: about half a cent each, and the agent spent them rediscovering how Sheets works (23 snapshots and 19 clicks through menus, 24 separate range navigations in one run).

Added: `umb notes <host>` with a 47-line notes file for Google Sheets (verified one-line idioms), three small recipes (`sheets-menu`, `sheets-tab-rename`, `sheets-validate-list`), `umb text` reading input values, `umb` on the agent's PATH, and a guide rule to take fewer, bigger turns.

| Tool | Run 1 | Run 2 | Run 3 | Average | Turns | Time | Screenshots | Checker |
|---|---|---|---|---|---|---|---|---|
| v1 (`helium`) | $0.64 | $0.51 | $0.61 | $0.59 | 70, 54, 50 | 3 to 6 min | 7 to 12 | all passed |
| browse 0.1.5 | $0.41 | $0.37 | $0.42 | $0.40 | 43, 24, 28 | 3 to 9 min | 15 to 17 | all passed |
| v2 with `look`, readers, paste | $0.38 | $0.40 | $0.35 | $0.38 | 58, 59, 45 | about 5 min | 0 to 2 | one check failed in one run |
| v2 with site notes | $0.12 | $0.12 | $0.11 | $0.12 | 10, 9, 8 | 2.5 min | 0 | 27/27 in all three |

Bill split per run with notes: entering $0.05 to $0.06, re-read about $0.01, agent's writing about $0.05. No failed commands in any of the three runs (108 to 119 commands each).

Reading it:

- Site notes cut the cost by about 70% against the previous v2 and against browse, and by about 80% against v1, with every check passing.
- This is a result about knowledge, not mechanics. The notes were written for Sheets by testing jobs close to this task's steps. The other arms had no such notes. A fair test of the tools themselves would give browse the same knowledge in its own commands.
- It says nothing yet about a site with no notes. That needs a second task on a different site.

Found during these runs: `umb open` puts a new tab in whichever browser profile window was used last. Two of these three runs created their spreadsheet in a different Google account from the first because the active window changed. The tool needs a way to choose the profile.

## Shoe research task (2026-11-26)

Task `shoe-deal`: recommend 3 to 5 running shoes for a described runner and find genuine, size-specific deals on Indian sites, with links, sellers, delivery, coupons, returns and warranty. Research through the browser tool only; read-only. v2 has no site notes for any site in this task. One run per tool.

| Measure | v2 (`umb`) | v1 (`helium`) | browse 0.1.5 |
|---|---|---|---|
| Cost | $0.27 | $0.43 | $0.54 |
| Turns | 29 | 38 | 46 |
| Time | 4.4 min | 7.9 min | 7.8 min |
| Page text returned | 34k chars | 67k chars | 63k chars |
| Non-browser fetching | none | none | none |
| Quality, graded blind against the brief (of 27) | 21.5 | 23.5 | 22.5 |
| Links that load the named shoe | 5 of 5 | 4 of 4 | 3 of 3 |
| Stated prices that match the page | 4 of 5 | 3 of 3 | 3 of 3 |
| Grader's rank | 3rd | 1st | 2nd |

Quality was graded by a separate agent that did not know which tool wrote which answer. It opened every link in the browser and compared prices, then scored a 12-item checklist taken from the brief. The checklist score is a model's judgment; the link and price checks are facts.

Reading it:

- v2 was cheapest and fastest but ranked last on quality. Its headline deal price (Rs 9,359) did not match the live page (Rs 11,699), and it separated tested findings from maker claims less clearly.
- v1 cost 60% more than v2 and gave the best answer: every checked price matched, and it found cheaper official-site deals the others missed.
- The quality gap is small (2 points of 27) and this is one run per tool. Neither the cost order nor the quality order is established yet.
- v2 read half as much page text. That saved money and may be why it missed things. Reading less is only a saving when the answer stays as good.

During grading, a script bug in the grading agent closed a tab that was already open in the browser. Nothing in the tool stops an agent from acting on a tab it did not open. Tab ownership moves to the top of the list.

### Shoe research task, three runs per tool

Two more runs per tool, graded blind by a second grading session with the same checklist (so scores from the two sessions may not be on exactly the same scale).

| Tool | Cost per run | Average | Turns | Checklist score (of 27) | Average | Links loading the named shoe | Stated prices matching the page |
|---|---|---|---|---|---|---|---|
| v2 (`umb`) | $0.27, $0.22, $0.35 | $0.28 | 29, 22, 32 | 21.5, 21.5, 23.5 | 22.2 | 14 of 14 | 13 of 14 |
| v1 (`helium`) | $0.43, $0.26, $0.27 | $0.32 | 38, 23, 21 | 23.5, 21, 22.5 | 22.3 | 11 of 11 | 10 of 10 |
| browse 0.1.5 | $0.54, $0.42, $0.31 | $0.42 | 46, 33, 28 | 22.5, 24.5, 22.5 | 23.2 | 10 of 11 | 10 of 10 |

Reading it:

- Quality is level across the three tools within the spread of single runs (each tool's own scores range over 2 to 2.5 points). v2's last place in the first round was noise.
- browse scored about one point higher on average and cost about 50% more than v2. v2 and v1 are within 13% on cost, which is inside the run-to-run spread.
- On a research task with no site notes, the tool makes little difference to cost or quality. The large saving measured on the Sheets task came from site notes.
- Weaknesses the grader found were about research habits, not tools: rankings from memory with no source opened, evidence borrowed from a different shoe model, and a top pick that ignored a cheaper deal on the same site.

### Not tested

- Sites that reject scripted input (some banking and checkout pages).
- Pages with iframes or shadow DOM.
- Any browser other than Helium.
