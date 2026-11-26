# Benchmark

## Phase 0: v1 baseline and spikes (2026-11-26)

One Mac, Helium, chrome-devtools-mcp 1.13.0. Each task ran once, in a fresh agent session on a mid-size model, with the v1 skill and lessons file read first. Single runs: treat the numbers as rough.

### v1 baseline

| Task | Agent tool calls | `helium` commands | Failed or repeated | Tokens | Time |
|---|---|---|---|---|---|
| Gmail: find the newest email from one sender, read its body | 8 | 6 | 3 redundant | 68k | 63 s |
| Shopping: top 3 results on three sites | 7 | 8 | 1 redundant | 67k | 70 s |
| Screener: add 8 filter columns, read the table | not recorded | about 85 (agent's own count) | about 20 | not recorded | not recorded |

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

### Not tested

- Sites that reject scripted input (some banking and checkout pages).
- Pages with iframes or shadow DOM.
- Any browser other than Helium.
