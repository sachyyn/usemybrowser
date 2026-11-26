# usemybrowser v2 plan

## Goal

Make browser tasks cost fewer agent turns and fail less often, without growing the tool.

v1 is cheap at reading pages. It is expensive at acting on them: each step is a separate command, element ids expire, clicks can land on covered elements, and the agent must make another call to see what a click did.

v2 keeps the v1 reading tricks and swaps the engine underneath for [browse](https://github.com/anomalyco/browse) (MIT, reviewed at commit `27bdfbb`, v0.1.5), used as a command-line tool only.

## Success condition

Measured on the same three tasks, v2 against v1:

- at least 40% fewer agent turns
- no more page text entering the agent's context than v1
- zero clicks that report success but did nothing
- works in all browser profiles the user has paired

If phase 0 does not show this, v2 stops being an engine swap and becomes "port two ideas into the v1 wrapper" (see Fallback).

## Decisions already made

| Decision | Choice | Why |
|---|---|---|
| Engine | browse relay + its browser extension | One script per task, stable element refs, covered-click checks, results that say what changed |
| How agents call it | Shell command, not an MCP server | No tool descriptions sitting in every session's context |
| Command name | `helium` stays as an alias; new name `umb` | Existing skills and habits keep working; browse supports more browsers than Helium |
| Reading helpers | Keep `text`, `check`, `decide` | browse has no equivalent of `check`/`decide` |
| Recipes | Script files in `recipes/`, not prose | A repeat task becomes one turn |
| browse updates | Notify only, never auto-install | It has debugger access to a logged-in browser |
| Human-like input | Off by default | Speed; turn on per site if a site blocks fast input |
| Version pin | Install a named browse version, bump on purpose | browse ships daily |

## Not doing

- No fork of browse and no copy of its code.
- No MCP server of our own.
- No second engine running beside it. One connection, one ref system.
- No Windows or Linux support work in v2 (browse supports them; we only test macOS).
- No new abstraction layer. The wrapper stays a short shell script.

## Phase 0: trial and measurement (go / no-go)

1. Install browse at a pinned version with `--agent none` (no agent configs touched), updates set to notify.
2. Add the extension to one Helium profile and pair it.
3. Run three tasks on v1 and on browse, same model, fresh session each:
   - TickerTape screener: add 15 columns and export
   - Gmail: search, open the right email, read the body
   - Shopping search across Amazon.in, Flipkart, Meesho
4. Record per run: agent turns, characters returned to the agent, wall time, failures, user prompts.
5. Answer the open questions below.
6. Write the numbers into `docs/benchmark.md`. Decide go or fallback.

Open questions phase 0 must answer:

- Does browse run cleanly in Helium (pairing, tab groups, the debugging bar)?
- Do three paired profiles work through one relay, and how is a profile picked per call?
- How long does `browse execute` take to start for a one-line script?
- Does the debugging bar get in the way in daily use? (User's call.)
- Do recipes behave with human-like input off on Gmail and the shopping sites?

## Phase 1: the wrapper

`bin/umb` (zsh, target under 120 lines), with `helium` as a symlink.

| Command | Does | Built on |
|---|---|---|
| `umb run <file\|-> [json args]` | Run a whole task as one script | `browse execute --file -`; the wrapper prepends `const args = <json>;` because execute has no argument input |
| `umb recipe <name> [json args]` | Run a saved recipe | `umb run recipes/<name>.js` |
| `umb snap <tab> [--find re] [--delta] [--interactive]` | Page outline with refs | `browse snapshot` |
| `umb text <tab> [css] [max]` | Plain text of one part of the page | `browse eval`, same JS as v1 |
| `umb check <tab> "<question>"` | Visual yes/no, image never enters context | `browse screenshot --output` piped to `decide` |
| `umb tabs`, `umb open <url> [--profile name]` | List and open tabs | `browse tabs`, `browse navigate` |
| anything else | Passed through | `browse <tool>` |

Rules for the wrapper:

- Never starts a second relay or connection.
- Prints only the result. No banners, no update notices.
- Caps output size and says when it cut something, like v1's `text`.
- Removed from v1: `compact`, `find`, uid handling.

## Phase 2: recipes

- `recipes/<site>-<task>.js`, each with a header comment: purpose, args, what it returns, date last verified.
- First three, converted from v1's lessons: `gmail-search`, `tickertape-export`, `shop-search`.
- Recipes return short strings or small JSON, never whole pages.
- Where a site has a JSON call behind the page, the recipe fetches that from inside the page instead of clicking. Found with browse's network capture.
- New recipes come from two places: an agent saving a script that worked, or `demonstrate` recording the user doing the flow once.
- A recipe that fails says which step failed, so the agent falls back to `snap` and fixes the recipe.

## Phase 3: the skill

Rewrite `skill/SKILL.md`, shorter than v1, around two rules:

- **Reading, cheapest first:** recipe or API call, `text`, `snap --find`, `snap --delta`, `check`, screenshot.
- **Acting:** look for a recipe; otherwise one `umb run` script that inspects, acts and verifies.

Also in the skill:

- Profiles as named browsers.
- Handoff for login, 2FA and payment, replacing "ask in chat".
- Tab ownership: own tabs and lent tabs only. Open read tasks as read-only tabs.
- The ask-first list for irreversible actions stays word for word.
- `LESSONS.md` keeps its format. Site lessons that become recipes are deleted from it.
- Removed: uid rules, the overlays section, the wait workaround.

## Phase 4: install and migration

- `install.sh` installs the pinned browse, sets updates to notify, installs wrapper, recipes and skill, then prints the two manual steps (add the extension, pair each profile).
- `install.sh --engine cdt` installs the v1 engine instead, for anyone who cannot use the extension.
- v1 users: the old daemon keeps working until they run the v2 installer. `docs/migrating.md` lists the command changes.
- README rewritten for v2, with the benchmark table.

## Phase 5: verify and release

- Rerun the three benchmark tasks through the finished wrapper and skill, in the real browser.
- Cross-agent check: Claude Code, Codex and one other agent each list tabs and run one recipe.
- Safety checks: a read-only tab refuses a click; an agent cannot touch a tab it did not open; a covered click fails with the blocker named; a handoff waits for a real click.
- Tag `v2`, GitHub release with the benchmark numbers and the migration note.

## Fallback if phase 0 says no

Stay on the v1 engine and port only:

1. Network discovery plus in-page fetch recipes (the v1 engine already lists network requests).
2. A better `compact`: scope to the main area or open dialog, and a changed-only mode that diffs against the saved snapshot.
3. Silence the upstream update banner.

## Risks

| Risk | Handling |
|---|---|
| browse changes or breaks often | Pinned version, notify-only updates, v1 engine kept as an install option |
| Extension has wide access to the browser | Documented plainly in the README; pairing is local; user reviews the store listing before installing |
| The debugging bar annoys the user | Phase 0 decides; fallback path exists |
| Recipes rot when sites change | Date-stamped, fail loudly at a named step, agent repairs them |
| Per-profile pairing is clumsy | Phase 0 measures it; if bad, document one profile as the default |

## Order of work

Phase 0 is the only step that needs the user (installing an extension and pairing). Everything after it can be built and tested without interrupting them, except the final real-browser run.
