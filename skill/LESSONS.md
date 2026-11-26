# Helium runs: lessons and improvement guide

Read this before a browser task. After a task, add one dated line under "Log" only if something
new was learned (a failure, a faster path, a wrong assumption). Keep it short. Every ~10 entries,
fold repeated lessons into "Rules learned" and delete the folded log lines.

## How to review a run (2 minutes)

1. Did it need the user to click or answer anything avoidable? Fix the cause, note it here.
2. How many browser commands did it take? Look for a shorter path (a search URL beats clicking).
3. How much page text entered context? Save snapshots to a file and grep; never print whole pages.
4. Was `decide` used? Check `~/.local/state/decide/usage.jsonl`. Was it worth it versus judging
   the items directly (see "When decide pays off")?
5. Was anything hard to undo done without asking? That is a failure even if it went well.

## Rules learned

- Every new connection to Helium triggers an "Allow remote debugging" prompt. Only use the
  `helium` daemon. Never spawn chrome-devtools-mcp or another MCP server for Helium.
- Most commands need a `pageId` from `helium list_pages`; the `[selected]` tab is the user's tab.
- Gmail: open a search URL directly, e.g. `helium new_page "https://mail.google.com/mail/u/0/#search/<query>"`.
  Result rows appear in snapshots as `row "sender , subject , date , preview"`;
  `grep 'row "'` on the saved snapshot gives a compact list.
- An email body in a snapshot starts after `heading "<subject>"`; grep from there, the sidebar is noise.
- A subject search for meeting invitations misses invites with other subjects and calendar-only events.
- Other profiles: `open -na Helium --args --profile-directory="<dir>" "<url>"` adds a window to
  the running Helium; its tabs appear in `helium list_pages` after a few seconds. No new Allow prompt.
- Screenshots via `filePath` only save inside the current project folder.
- Sandboxed agents (Codex) cannot reach the daemon socket. Run `helium`/`decide` outside the
  sandbox (Codex: approve "always" for the `helium` prefix). Never make
  `/tmp/chrome-devtools-mcp-<uid>` writable inside a sandbox: the CLI then silently starts a
  plain daemon that is not attached to Helium. `helium` detects and repairs that (one Allow).
- Hermes only trusts skills from its own folder or `skills.external_dirs`; a symlink in
  `~/.hermes/skills` is flagged untrusted and the model may fall back to its own browser.
  List `~/.agents/skills` in `external_dirs` instead.

## When decide pays off

- Small lists (under ~10 short rows) already printed in context: judge directly. `decide` adds a
  step and saves nothing because the rows are already read.
- Large or heavy inputs: many pages, long email bodies, or screenshots. Send them to `decide`
  and only print the confident matches, so the content never enters context.
- Rough costs per item: `decide` ~100-200 tokens of text or ~350 per low-res screenshot at
  $0.10/M (about $0.00002-0.00004). Reading the same item in this session costs context.

## Measured read costs (2026-11-12)

| Read | Gmail list (tab) | AI Studio docs page |
|---|---|---|
| `take_snapshot` | 8,561 chars | 34,109 chars |
| `helium compact` | 3,421 | 5,369 |
| `helium find` (rows only) | ~600 | n/a |
| `helium text` (main content) | 1,745 (open email page) | 4,031 (capped; 4,793 compact) |
| `helium text .a3s` (email body only) | 1,419 | n/a |
| `evaluate_script` extraction | 289 | n/a |
| `helium check` (screenshot, Gemini) | ~350 Gemini tokens, 0 in context | |

## Site notes

Selectors and limits seen on real sites in November 2026. Sites change; re-check one before
relying on it.

- X (x.com) search: six tabs searching in parallel got 'Something went wrong' / ScriptLoadFailure after ~10 loads each. One tab with ~25 s between loads ran 18 searches cleanly. Tweet extraction: evaluate_script over article[data-testid=tweet] (url via a[href*=/status/], time[datetime], [data-testid=tweetText], [role=group] aria-label).
- Shopping search across Amazon.in/Flipkart/Meesho in one tab via navigate_page + evaluate_script loop. Selectors: Amazon `div[data-component-type=s-search-result]` (skip `.puis-sponsored-label-text`); Flipkart `a[href*="/p/"]` closest `div[data-id]`; Meesho `a[href*="/p/"]`. Return `.join("\n")` strings, not arrays, so grep parsing works. Meesho stopped rendering results after ~10 rapid searches; space them out.
- TickerTape screener export. Add Filter dialog: fill its search box, then click the uid whose text equals the filter name; each filter becomes an export column. Smallcap and Midcap buttons replace each other, so set the market-cap min spinbutton to 0 instead. Filling the market-cap max spinbutton + Enter also works as a cap filter. Sub-sectors: expand a sector with `.sector-top [class*=icon-chevron]` via evaluate_script, then click the sub-sector names to untick. Export dialog has a file-name textbox; the CSV lands in ~/Downloads.
- TickerTape columns: loop of take_snapshot -> fill 'Search for Filters' textbox -> click last uid with exact text; 15 columns took ~1 min and the row count stayed the same (adding columns does not drop blank rows). Default PE/1M Return rows are columns, not active filters.
- Vercel preview URLs (`*.vercel.app` with Vercel Authentication on) answer curl with a 302. If Helium is signed in to Vercel: `new_page` the preview, then one `evaluate_script` on `document.body.innerText` confirms the text. The preview first loads a 'Vercel' auth page; poll document.title for a few seconds before reading. A profile that is not a member of the Vercel team sees 'You Need Access'; check which profile is the team member first.
- Emulate: `helium emulate <id> --viewport 390x844` works; reset with `--viewport 0x0`. window.scrollTo needs behavior:'instant' (smooth scroll leaves the screenshot at the top).

## Log

Add entries here, newest last: `- YYYY-MM-DD: what happened and what to do next time.`
