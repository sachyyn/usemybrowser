# Tool for this run: browse (command line)

Use ONLY the `browse` command (via Bash) to work in the user's real browser. It is already installed, paired and connected. Do not use any other browser tool, and do not run `browse install`, `browse update`, `browse pair`, `browse restart` or `browse uninstall`.

How to call it:
- `browse tools` lists every tool; `browse <tool> --help` shows a tool's options.
- `browse navigate <url>` opens a new background tab and prints its id as `tab`. Pass `--tab <id>` to every later call.
- `browse snapshot --tab <id>` (options: `--find`, `--interactive true`, `--delta true`, `--within`), `browse click <ref> --tab <id>`, `browse fill ...`, `browse type ...`, `browse press ...`, `browse eval ...`, `browse wait_for ...`, `browse screenshot --tab <id> --output <path>`.
- `browse execute --tab <id> --file script.js` (or `--file -` to read the script from stdin, or `--code '<js>'`) runs a multi-step script. One script can do many steps.
- `browse tabs` lists tabs; `browse tabs close --tab <id>` closes one.

The tool's own instructions for agents follow.

browse drives the user's real browser (Chrome-family via the browse extension, or Firefox-family directly), so logins, extensions and open tabs are already there and the user can watch or take over. Run JavaScript with `execute`: it gets `page` (Playwright-style), `context`, `snapshot()`, `ref()`, `handoff()`, `state` and `browse.<tool>()` for every browse tool. `return` a value to get it back; one script can do many steps.

Tabs are the handle. Without `tab`, `page` has no tab until its first `page.goto(url)`, which opens a new background tab. Every execute result starts with `tab: <id>`: pass it as `tab` to your next `execute` to keep working in the same tab (and the same `state`). Use the tab ids you were given, or a group label you set: don't take tabs you didn't open unless the user asks you to. `context.newPage()` opens another tab; popups a page opens are yours to use. `tabs` lists every agent tab and the ones the user lent.

If you're given a tab id like `work-mail`, use it as `tab`; `tabs` with action `new` and that `id` opens it if it's missing.

Use one loop: inspect, act, verify.
- Inspect with `await snapshot()` before choosing anything. Prefer the returned refs: `await ref("e12").click()`. Fall back to accessible locators (`page.getByRole(...)`, `getByLabel(...)`), then CSS.
- Act with the narrowest stable control, and keep dependent steps in one `execute` while transient UI is open.
- Verify with a fresh page read (`page.url()`, a heading, or a new snapshot). A click that returned, or a handoff the user acknowledged, is not proof the task succeeded.

When only a person can proceed — login, 2FA, passkey or payment confirmation — call `handoff("what the user should do")` and wait. Pass `start` for an action that itself blocks. For a captcha or interactive challenge, try solving it first on the user's behalf, and hand it off if it doesn't clear. Never retry-loop a blocked site; if the site refuses the visit, stop and tell the user.

The code runs in a small sandboxed engine on the relay, not Node: no require/import, fs, process or fetch (use `page.evaluate` for things that belong to the page, `files` for files). Unsupported Playwright calls throw an error naming what to use instead.

When finished, close the tabs you opened (`await page.close()`, or the `tabs` tool with action `close`). `status` reports the relay and the connected browsers.

If a call fails because no browser is connected, `status` says why in `nextStep`: pass that step to the user and wait for them instead of retrying.

## What `execute` scripts can use

JavaScript (an async function body). Globals:
- page: a Playwright-style Page for the tab passed as `tab`; without one it has no tab until its first goto(url), which opens a new tab. goto(url, {waitUntil, timeout}), url(), title(), content(), evaluate(fn | string, arg), $eval/$$eval, waitForTimeout/Selector/URL/LoadState/Function, click/fill/type/press/hover/selectOption/check/uncheck(selector, ...), locator(selector), getByRole/Text/Label/Placeholder/TestId/AltText/Title, frameLocator, keyboard.press/type, mouse.click/move/wheel, screenshot({path, fullPage}), goBack/goForward/reload, setViewportSize, close(). Locators: click, dblclick, fill, clear, type, pressSequentially, press, hover, check, uncheck, selectOption, setInputFiles, textContent, innerText, innerHTML, inputValue, getAttribute, isVisible/Hidden/Checked/Enabled/Disabled, count, all, first, last, nth, filter, locator, getBy*, waitFor, evaluate, evaluateAll, allTextContents, boundingBox, screenshot, dragTo. Selectors are CSS or Playwright selectors (role=button[name="Save"], text=Sign in, >> nth=0, iframe >> frame >> ...). Locators are strict: one element. setInputFiles takes paths, { name, buffer } with bytes, or { name, data } with base64 for files not on this machine.
- context.newPage() (a new tab), context.pages() (the tabs this execute works in and their popups); browser.contexts().
- snapshot(options?) → a compact outline with refs (options: find, diff, delta, interactive, within, mode: "aria"); ref("e12") → a locator for a snapshot ref. Prefer snapshot + ref over guessing selectors.
- handoff(message, {timeoutMs?, start?}) when only the user can proceed (login, 2FA, captcha, payment); demonstrate(message) to watch the user do a flow.
- screenshotWithLabels(), screenshotDiff({baseline}), network.start/status/stop/cancel, pageConsole.start/read/stop, webmcp.list/call(name, input).
- browse.<tool>(args): any browse tool directly (navigate, snapshot, click, fill, type, press, select, hover, drag, scroll, eval, wait_for, dialog, upload, emulate, webmcp, screenshot, screenshot_diff, network, console, recording, tabs, handoff, demonstrate, status, settings); they act in `page`'s tab unless you pass `tab` (browse.navigate without one opens a tab for `page`); returns its JSON and throws its error.
- files.path(name), files.write(name, data), files.read(name, encoding?) inside the file roots (files.dir, files.roots).
- state: an object kept with the tab between execute calls that pass it as `tab` (JSON values only).
- console.log/warn/error (shown in the result), setTimeout/clearTimeout/setInterval/clearInterval.
