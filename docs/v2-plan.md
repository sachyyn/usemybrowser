# usemybrowser v2 plan

## Goal

Make browser tasks cost fewer agent turns and fail less often, while the tool stays small and stays ours.

v1 is cheap at reading pages. It is expensive at acting on them: each step is a separate command, the agent has to re-read the page to find what to click, clicks can land on covered elements, and it takes another call to see what a click did.

## Approach

Keep the v1 engine (one chrome-devtools daemon, one Allow click, every profile visible). Take ideas and code from [browse](https://github.com/anomalyco/browse) where they solve those problems, and copy them into this repo.

browse is a parts shelf, not a dependency. v2 does not install its relay, its extension or its updater.

What that keeps from v1: no browser extension, no pairing, no debugging bar, no third-party binary with access to a logged-in browser, and a tool small enough to read.

## Success condition

Measured on the same three tasks, v2 against v1:

- at least 40% fewer agent turns
- no more page text entering the agent's context than v1
- zero clicks that report success but did nothing
- the wrapper and its helpers stay readable in one sitting (target: under 300 lines of our own code, vendored files not counted)

## Rules for borrowed code

- Source: browse at commit `27bdfbb` (v0.1.5), MIT.
- Each copied file goes in `vendor/browse/` with its licence notice, and `vendor/README.md` records the file, source path, commit and any local change.
- browse's `injected-script.js` is Playwright's code under Apache-2.0. Avoid it unless a phase proves it is needed; if used, keep its notice.
- Copy only what a phase needs. Prefer taking an idea and writing ten lines over vendoring a thousand.
- Rust code is read for its logic and rewritten as shell or page JavaScript. Nothing in v2 needs a compiler.

## What we take

| Problem in v1 | Idea from browse | How it lands here | Borrow |
|---|---|---|---|
| `compact` cuts at 150 lines blindly and drops plain text | Snapshot that scopes to the open dialog or main area, collapses nav menus, keeps the most important lines | `helium snap` runs browse's page capture script through `evaluate_script --sourcePath` and prints one short line per element | Code: `capture.js` (self-contained page function, returns entries with CSS selectors) |
| Element ids change, so the agent re-reads the page | Refs that stay the same while the element does | Refs like `e12` map to the selectors the capture returns, saved per tab in `~/.cache/helium` | Idea |
| Re-reading the whole page after each step | Changed-only snapshot | `helium snap --delta` diffs against the last saved snapshot for that tab | Idea |
| One command per step | One script per task | `helium run <file> [json args]` runs a script in the page with a small helper set: find by role or text, wait, click, fill | Idea, plus parts of `helpers.js` if they save work |
| Click reports success but lands on an overlay | Refuse a covered click and name what is on top | Helper checks the element at the click point before clicking | Idea (logic in `helpers.js`) |
| A second call to see what a click did | Every action reports what changed | The wrapper prints one line after each action: URL, title, navigated or not, dialog, new tabs | Idea (`aftermath.rs`) |
| No `wait_for` | Wait for text, a URL or an element | A polling helper in the page, exposed as `helium wait` and inside `run` | Idea |
| Agent retries a blocked site in a loop | Detect bot checks and block pages | A short selector and phrase list checked after navigation, reported in the action line | Code: the selector list and rules from `challenge.rs`, rewritten in JS |
| Clicking through a page to get data that is one JSON call | Use the site's own API | Recipe step: list network requests with the existing CLI, then fetch from inside the page | Idea |
| "Don't touch my tabs" is only an instruction | Agents act only on tabs they opened or were lent | The wrapper records tabs it opened and refuses actions on others without `--lend` | Idea |
| Login, 2FA and payment stop the task in chat | Handoff card with a Continue button on the page | `helium handoff <tab> "<message>"` injects a small card and waits for a real click | Idea (`handoff_card.rs`), last phase, only if cheap |

## What we do not take

Relay and extension, pairing, the embedded script engine, the Playwright-style `page` object, stealth and human-like input, screen recording, Firefox support, auto-update, and the installer for thirty agents.

## Kept from v1

`text`, `check`, `decide`, the skill, the lessons log, the ask-first list for irreversible actions, and `helium` as a command alias.

## Any Chromium browser, not only Helium

The engine attaches to a running browser through the remote debugging switch at `chrome://inspect/#remote-debugging`. Helium is one browser that has it; Chrome and other Chromium browsers do too.

- Docs and the skill say "your browser" and name Helium as the one this was built and tested on.
- The browser's profile folder becomes a setting (`USEMYBROWSER_DIR`, default: Helium's folder if present, else Chrome's). It is the only Helium-specific line in the wrapper.
- The `helium` command name stays as an alias; the main command is named after the repo, `umb`.
- The README lists which browsers were actually tested. Untested ones are listed as untested, not as supported.

## Open design question: how far page scripts go

`helium run` executes inside the page. Two limits follow:

1. Clicks made by page JavaScript are synthetic. Some sites ignore them.
2. A navigation ends the script, so a flow across pages is several `run` calls.

Phase 0 tests both on the benchmark tasks. The answers pick one of:

- **A. Page scripts only.** Smallest. Chosen if synthetic clicks work on the benchmark sites and multi-page flows chain fine.
- **B. Page script finds, daemon clicks.** The script returns the element's position and the wrapper sends a real click through the daemon (`click_at`, which needs one daemon flag and so one extra Allow click, once).
- **C. Our own daemon on puppeteer-core.** Replaces the chrome-devtools CLI, still one connection. Scripts get a real `page` that survives navigation. About 300 more lines and a new dependency. Chosen only if A and B fail the benchmark.

## Phases

### Phase 0: baseline and spikes

No install and nothing new in the browser.

1. Run the three tasks on v1 in a fresh session each: TickerTape screener (add 15 columns, export), Gmail (search, open, read the body), shopping search across Amazon.in, Flipkart and Meesho. Record turns, characters returned, wall time, failures, user prompts.
2. Spike: run `capture.js` through `evaluate_script --sourcePath` on Gmail, TickerTape and a docs page. Record output size against `compact` and whether its selectors resolve.
3. Spike: synthetic click and fill on the benchmark sites. Note where they fail.
4. Pick A, B or C. Write the numbers to `docs/benchmark.md`.

### Phase 1: snapshot and refs

- `helium snap <tab> [--find re] [--interactive] [--within css] [--delta] [--max n]`
- Ref table per tab in `~/.cache/helium`; cleared when the tab navigates.
- `compact` and `find` become aliases of `snap`, then go.

### Phase 2: acting

- `helium click|fill <tab> <ref>` resolve the ref, check nothing covers the element, act, then print the what-changed line.
- `helium wait <tab> --text|--gone|--url|--ref`.
- Bot-check detection in the what-changed line.
- Update notices from the upstream CLI are filtered out of all output.

### Phase 3: scripts and recipes

- `helium run <file|-> [json args]` and `helium recipe <name> [json args]`.
- `recipes/<site>-<task>.js`, each with a header: purpose, args, returns, date last verified.
- First three: `gmail-search`, `tickertape-export`, `shop-search`. Where a site has a JSON call behind the page, the recipe fetches that.
- A failing recipe names the step that failed.

### Phase 4: safety

- Tab ownership with `--lend`.
- `helium handoff`, if it fits in about 40 lines.

### Phase 5: skill, install, docs

- `SKILL.md` rewritten, shorter, around two rules. Reading, cheapest first: recipe or API call, `text`, `snap --find`, `snap --delta`, `check`, screenshot. Acting: recipe first, else one `run` script that inspects, acts and verifies.
- Site lessons that became recipes leave `LESSONS.md`.
- Installer copies `vendor/` and `recipes/`. Move to the current chrome-devtools-mcp version after testing it.
- README updated with the benchmark table and the list of borrowed code.

### Phase 6: verify and release

- Rerun the three tasks through the finished tool in the real browser.
- Checks: covered click fails with the blocker named; action on a tab the wrapper did not open is refused; a ref survives a re-snapshot; a recipe runs in one turn.
- One task each through two other agents.
- Tag `v2`, release notes with the numbers.

## Risks

| Risk | Handling |
|---|---|
| `capture.js` does not run cleanly through `evaluate_script` | Phase 0 spike. Fallback: write a smaller capture of our own using the same three ideas (scope, collapse, rank). |
| Synthetic clicks fail on key sites | Options B and C above |
| Vendored code drifts from upstream | We do not track upstream. The copy is ours; the commit is recorded in case we want to compare later. |
| The wrapper grows past readable | Line budget in the success condition; anything over it has to replace something |
| Recipes rot when sites change | Date-stamped, fail at a named step, agent repairs them |

## Order of work

Phase 0 needs nothing from the user. Phases 1 to 5 can be built and tested against the running browser without interrupting them, as long as the daemon is not restarted. Option B's daemon flag and the final real-browser run are the only points that need the user.
