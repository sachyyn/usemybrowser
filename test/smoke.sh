#!/bin/zsh
# Smoke test: runs umb against test/fixture.html in a new background tab of the running browser.
# Needs the chrome-devtools daemon already attached (it never starts one). Closes its tab when done.
HERE=${0:A:h}; UMB=${HERE:h}/bin/umb
cd "$HERE" || exit 1
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 & SRV=$!
export UMB_TASK="smoke-$$" UMB_RECIPES="$HERE/recipes"; unset UMB_NO_LOG
PASS=0; FAIL=0; TAB=""; CALLS=1  # umb open is call 1
TMPD=$(mktemp -d)
cleanup() { [ -n "$TAB" ] && "$UMB" close "$TAB" >/dev/null 2>&1; kill $SRV 2>/dev/null; rm -rf "$TMPD"; }
trap cleanup EXIT

# ok <name> <expected exit> <expected output substring> -- <umb args>; also leaves output in $OUT
ok() {
  local name=$1 want_rc=$2 want=$3; shift 4; CALLS=$((CALLS+1))
  OUT=$("$UMB" "$@" 2>&1); local rc=$?
  if [[ $rc -eq $want_rc && "$OUT" == *"$want"* ]]; then PASS=$((PASS+1)); echo "ok   $name"
  else FAIL=$((FAIL+1)); echo "FAIL $name (exit $rc, wanted $want_rc, wanted output containing: $want)"; echo "$OUT" | sed 's/^/     | /'; fi
}
absent() { if [[ "$OUT" == *"$2"* ]]; then FAIL=$((FAIL+1)); echo "FAIL $1 (found: $2)"; else PASS=$((PASS+1)); echo "ok   $1"; fi }

sleep 0.5
for i in 1 2 3 4 5 6 7 8 9 10; do curl -s "http://127.0.0.1:$PORT/fixture.html" >/dev/null && break; sleep 0.3; done
OPENED=$("$UMB" open "http://127.0.0.1:$PORT/fixture.html?delay=3000"); TAB=${OPENED%% *}
[[ "$TAB" == <-> ]] || { echo "FAIL open: $OPENED"; exit 1; }
echo "ok   open -> $OPENED"; PASS=$((PASS+1))

ok "snap shows refs (delta baseline, full)" 0 'e1 button "Save"' -- snap $TAB --delta
REF_SAVE=$(print -r -- "$OUT" | sed -n 's/^ *\(e[0-9]*\) button "Save".*/\1/p')
REF_COVERED=$(print -r -- "$OUT" | sed -n 's/^ *\(e[0-9]*\) button "Covered".*/\1/p')
REF_NAME=$(print -r -- "$OUT" | sed -n 's/^ *\(e[0-9]*\) textbox "Name".*/\1/p')
REF_BOX=$(print -r -- "$OUT" | sed -n 's/^ *\(e[0-9]*\) checkbox.*/\1/p')
REF_SEL=$(print -r -- "$OUT" | sed -n 's/^ *\(e[0-9]*\) combobox.*/\1/p')
ok "ref unchanged on re-snap" 0 "$REF_SAVE button \"Save\""   -- snap $TAB
ok "snap --find"              0 'button "Covered"'            -- snap $TAB --find covered
ok "snap --find --interactive" 0 'textbox "Name"'             -- snap $TAB --find name --interactive
ok "snap --within"            0 'checkbox "Subscribe"'        -- snap $TAB --within '#agree'
ok "wait for late element"    0 ok                            -- wait $TAB --text Appeared
ok "snap --delta only new"    0 '+ e'                         -- snap $TAB --delta
[[ "$OUT" == *'button "Appeared"'* && "$OUT" != *'"Save"'* ]] && { PASS=$((PASS+1)); echo "ok   delta shows only the new button"; } || { FAIL=$((FAIL+1)); echo "FAIL delta content: $OUT"; }

ok "click by ref"             0 "clicked $REF_SAVE button \"Save\"; page changed; url unchanged" -- click $TAB $REF_SAVE
ok "click covered fails"      1 'covered by <div#overlay.cookie-banner "Cookie banner">'     -- click $TAB $REF_COVERED
ok "click covered --force"    0 'clicked'                     -- click $TAB $REF_COVERED --force
ok "click text target"        0 'clicked text:"Plain span"'     -- click $TAB 'text:"Plain span"'
ok "click css target"         0 'clicked css:#plain'          -- click $TAB 'css:#plain'
ok "text, two matches fails"  1 'matched 2 elements'          -- click $TAB 'text:Twin'
ok "text, zero matches fails" 1 'matched 0 elements'          -- click $TAB 'text:No such text'

ok "fill input"               0 'filled'                      -- fill $TAB $REF_NAME 'hello world'
ok "input value kept"         0 'hello world'                 -- evaluate_script --pageId $TAB '() => document.getElementById("name").value'
ok "text reads an input's value" 0 'hello world'           -- text $TAB '#name'
absent "evaluate_script has no wrapper" 'Script ran on page'
ok "fill select by label"     0 'set to "Green"'              -- fill $TAB $REF_SEL Green
ok "fill select bad option"   1 'has no option'               -- fill $TAB $REF_SEL Purple
ok "checkbox already checked" 0 'already checked; left alone' -- fill $TAB $REF_BOX true
ok "checkbox uncheck"         0 'now unchecked'               -- fill $TAB $REF_BOX false
ok "checkbox no toggle"       0 'already unchecked; left alone' -- fill $TAB $REF_BOX false

ok "wait timeout fails"       1 'wait timed out after 800ms: text "Never" is not on the page' -- wait $TAB --text Never --timeout 800
ok "wait gone"                0 ok                            -- wait $TAB --gone Never
ok "tabs lists ours"          0 "$TAB"                        -- tabs
absent "no update notice"     'Update available'

ok "text near miss"           1 'near misses: text:"Debt to Equity"' -- click $TAB 'text:"debt to"'
ok "find lists plain text"    0 'text "Debt to Assets"'       -- snap $TAB --find 'debt to'
ok "find nothing says what was searched" 0 'no match for /zzzq/i: searched' -- snap $TAB --find zzzq
ok "plain snap is a delta baseline" 0 'button "Save"'         -- snap $TAB
ok "delta after plain snap"   0 'no changes since the last snap' -- snap $TAB --delta

ok "run: args, fill, click, return" 0 '{"who":"ann","log":"span clicked"}' -- run $TAB - '{"who":"ann"}' <<'JS'
umb.fill('css:"#name"', args.who);
await umb.click('text:"Plain span"');
await umb.wait({ text: 'span clicked' }, 2000);
return { who: umb.find('css:"#name"').value, log: umb.text('#log', 100) };
JS
ok "run: what changed line"   0 'url unchanged'                -- run $TAB - <<<'return "plain string"'
ok "run: error exits 1"       1 'umb: run failed: boom'       -- run $TAB - <<<'throw new Error("boom")'
ok "run: output cap"          0 '-- cut at 20 of 300 chars'   -- run $TAB - --max 20 <<<'return "x".repeat(300)'
ok "recipe list shows purpose" 0 'fixture-echo       fixture recipe:' -- recipe
ok "recipe runs in its own tab" 0 '{"title":"UMB fixture","name":"smoke","log":"span clicked"}' -- recipe fixture-echo "{\"port\":$PORT,\"name\":\"smoke\"}"
ok "recipe missing arg fails" 1 'step failed: url: missing arg port' -- recipe fixture-echo
ok "recipe tab was closed"    0 "$TAB" -- tabs
absent "recipe left no tab open" "v=smoke"

# keys: real input steps in one command; failure names the step; type:@file fills a grid (tab = next cell, newline = Enter).
ok "keys: click, type, key in one command" 0 'keys: 3 steps ok; url unchanged' -- keys $TAB 'click:css:#name' 'type:xyz' 'key:Tab'
ok "keys typed into the page" 0 'xyz'                         -- evaluate_script --pageId $TAB '() => document.getElementById("name").value'
ok "keys failure names the step" 1 'keys failed at step 2 of 3 (click:css:#nope): umb: css:#nope matched 0 elements' -- keys $TAB 'key:Tab' 'click:css:#nope' 'key:Tab'
ok "keys bad key names the step" 1 'keys failed at step 1 of 1 (key:Bogus): ' -- keys $TAB 'key:Bogus'
printf 'a1\tb1\na2\t\n' > "$TMPD/grid.tsv"
ok "keys type:@file fills a grid, --read shows it" 0 'a1,b1,a2,' -- keys $TAB "click:css:[aria-label='Cell A1']" "type:@$TMPD/grid.tsv" --read '#cells'
ok "keys missing file fails" 1 'no such file' -- keys $TAB "type:@$TMPD/none.tsv"
ok "keys key combo"        0 'Meta+A'                         -- keys $TAB 'key:Meta+A' --read '#keylog'

# clear, paste, and the type:@file size guard.
ok "keys clear replaces the old text" 0 'keys: 3 steps ok' -- keys $TAB 'click:css:#name' clear 'type:new'
ok "clear result"             0 '"new"'                       -- evaluate_script --pageId $TAB '() => document.getElementById("name").value'
ok "keys paste into an input" 0 'keys: 3 steps ok'            -- keys $TAB 'click:css:#name' clear 'paste:pasted text'
ok "paste result"             0 '"pasted text"'               -- evaluate_script --pageId $TAB '() => document.getElementById("name").value'
printf 'p1\tq1\np2\tq2\n' > "$TMPD/paste.tsv"
ok "paste @file fills the grid in one step" 0 'p1,q1,p2,q2'  -- keys $TAB "click:css:[aria-label='Cell A1']" "paste:@$TMPD/paste.tsv" --read '#cells'
python3 -c 'print("x\t" * 40)' > "$TMPD/long.tsv"
ok "type:@file refuses a block" 1 'use paste:@'               -- keys $TAB "type:@$TMPD/long.tsv"
ok "paste into a button fails" 1 'did not take the paste'  -- keys $TAB 'key:Escape' 'click:css:#plain' 'paste:x'

# Proof flags: --expect, --expect-gone, --expect-url, --read.
ok "expect ok"                0 'expect ok'                   -- click $TAB css:#plain --expect 'plain clicked'
ok "expect failed"            1 'expect failed: "never there" not on the page' -- click $TAB css:#plain --expect 'never there' --timeout 500
ok "expect-gone ok"           0 'expect ok'                   -- click $TAB css:#plain --expect-gone 'never there'
ok "expect-gone failed"       1 'expect failed: "Fixture" still on the page' -- click $TAB css:#plain --expect-gone Fixture --timeout 500
ok "expect-url ok"            0 'expect ok'                   -- click $TAB css:#plain --expect-url fixture.html
ok "read prints that part of the page" 0 'plain clicked'      -- click $TAB css:#plain --read '#log'
ok "read-max caps"            0 '-- cut at 5 of 13 chars'     -- click $TAB css:#plain --read '#log' --read-max 5
ok "fill takes proof flags"   0 'expect ok'                   -- fill $TAB 'css:#name' hello --expect 'plain clicked'
ok "recipe --tab runs in an open tab" 0 '"name":"recipe","log":"span clicked"' -- recipe fixture-echo "{\"port\":$PORT}" --tab $TAB
ok "recipe --tab proof"       0 'expect ok'                   -- recipe fixture-echo "{\"port\":$PORT}" --tab $TAB --expect 'span clicked'

# shot: a small JPEG at an absolute path; a region crop is smaller than the viewport.
px() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/ {print $2}' | tr '\n' ' '; }
ok "shot prints one path"     0 '.jpeg'                       -- shot $TAB --max-px 600 --out "$TMPD/view.jpeg"
[[ "$OUT" == /* && "$OUT" != *$'\n'* && -f "$OUT" ]] && { PASS=$((PASS+1)); echo "ok   shot path is absolute and the file exists"; } || { FAIL=$((FAIL+1)); echo "FAIL shot path: $OUT"; }
VIEW=$OUT; read VW VH <<<"$(px $VIEW)"
[[ "$(file -b $VIEW)" == JPEG* ]] && { PASS=$((PASS+1)); echo "ok   shot is a JPEG"; } || { FAIL=$((FAIL+1)); echo "FAIL shot type: $(file -b $VIEW)"; }
(( VW <= 600 && VH <= 600 && (VW == 600 || VH == 600) )) && { PASS=$((PASS+1)); echo "ok   shot longest side is exactly --max-px (${VW}x${VH})"; } || { FAIL=$((FAIL+1)); echo "FAIL shot size ${VW}x${VH}"; }
ok "shot --region"            0 '.jpeg'                       -- shot $TAB --region 'css:#grid' --max-px 600 --out "$TMPD/grid.jpeg"
read RW RH <<<"$(px $OUT)"
(( RW * RH < VW * VH )) && { PASS=$((PASS+1)); echo "ok   region crop (${RW}x${RH}) is smaller than the viewport shot (${VW}x${VH})"; } || { FAIL=$((FAIL+1)); echo "FAIL region ${RW}x${RH} vs ${VW}x${VH}"; }
ok "shot default path"        0 '.cache/umb/shots/'           -- shot $TAB; rm -f "$OUT"
ok "shot region matching nothing fails" 1 'matched 0 elements' -- shot $TAB --region 'css:#nope'

# Pass-throughs: relative --filePath is made absolute; press_key, type_text and tabs print one short line.
CALLS=$((CALLS+1)); OUT=$(cd "$TMPD" && "$UMB" take_screenshot $TAB --format jpeg --filePath rel.jpeg 2>&1)
[[ "$OUT" == *"Saved screenshot to ${TMPD:A}/rel.jpeg"* && -f "$TMPD/rel.jpeg" ]] && { PASS=$((PASS+1)); echo "ok   relative --filePath lands in the caller's folder"; } || { FAIL=$((FAIL+1)); echo "FAIL filePath: $OUT"; }
ok "press_key is one short line" 0 'pressed Tab'              -- press_key $TAB Tab
[[ "$OUT" == "pressed Tab" ]] && { PASS=$((PASS+1)); echo "ok   press_key prints only that"; } || { FAIL=$((FAIL+1)); echo "FAIL press_key output: $OUT"; }
ok "type_text is one short line" 0 'typed 3 chars'            -- type_text $TAB abc
ok "tabs: id, short title, host" 0 "$TAB \"UMB fixture\" 127.0.0.1" -- tabs

# Site notes: a fixture folder via UMB_NOTES with notes for 127.0.0.1 only.
export UMB_NOTES="$HERE/notes"
ok "notes lists hosts"         0 '127.0.0.1'                   -- notes
ok "notes for a host"          0 'fixture notes:'              -- notes 127.0.0.1
ok "notes for a tab id"        0 'fixture notes:'              -- notes $TAB
ok "notes missing is one line, exit 0" 0 'no notes for example.com' -- notes example.com
ok "open adds a notes line"    0 'notes: umb notes 127.0.0.1'  -- open "http://127.0.0.1:$PORT/fixture2.html"
"$UMB" close "${OUT%% *}" >/dev/null 2>&1; CALLS=$((CALLS+1))
UMB_NOTES="$TMPD/nonotes" ok "open adds nothing without notes" 0 '127.0.0.1' -- open "http://127.0.0.1:$PORT/fixture2.html"
absent "no notes line when none exist" 'notes:'
"$UMB" close "${OUT%% *}" >/dev/null 2>&1; CALLS=$((CALLS+1))
unset UMB_NOTES

ok "link click navigates"     0 '(navigated)'                 -- click $TAB 'text:Go next'
ok "snap after navigation"    0 'link "Back"'                 -- snap $TAB

# Tab ownership: a tab opened with the daemon directly (not umb open) is "the user's". Reads work, actions are refused.
CDT="$HOME/.local/share/helium-cdt/node_modules/.bin/chrome-devtools"
FIX=$("$CDT" new_page "http://127.0.0.1:$PORT/fixture2.html" --background --output-format json 2>/dev/null | python3 -c 'import json,sys; print(max(p["id"] for p in json.load(sys.stdin)["pages"]))')
[[ "$FIX" == <-> ]] || { echo "FAIL could not open the non-owned fixture tab"; exit 1; }
cleanup() { [ -n "$TAB" ] && "$UMB" close "$TAB" >/dev/null 2>&1; [ -n "$FIX" ] && "$CDT" close_page "$FIX" >/dev/null 2>&1; kill $SRV 2>/dev/null; rm -rf "$TMPD"; }
NOT="tab $FIX was not opened by umb; reads are allowed, actions need: umb lend $FIX"
ok "not owned: click refused"    1 "$NOT" -- click $FIX 'css:#plain'
ok "not owned: fill refused"     1 "$NOT" -- fill $FIX 'css:#name' x
ok "not owned: keys refused"     1 "$NOT" -- keys $FIX 'key:Tab'
ok "not owned: run refused"      1 "$NOT" -- run $FIX - <<<'return 1'
ok "not owned: recipe --tab refused" 1 "$NOT" -- recipe fixture-echo "{\"port\":$PORT}" --tab $FIX
ok "not owned: close refused"    1 "$NOT" -- close $FIX
ok "not owned: close_page refused" 1 "$NOT" -- close_page $FIX
ok "not owned: evaluate_script refused" 1 "$NOT" -- evaluate_script --pageId $FIX '() => 1'
ok "not owned: navigate_page refused" 1 "$NOT" -- navigate_page $FIX --url about:blank
ok "not owned: press_key refused" 1 "$NOT" -- press_key $FIX Tab
ok "not owned: type_text refused" 1 "$NOT" -- type_text $FIX abc
ok "not owned: select_page refused" 1 "$NOT" -- select_page $FIX
ok "new_page points to open"     1 'use: umb open' -- new_page about:blank
ok "pass-through with no tab id refused" 1 'changes a tab' -- hover
ok "not owned: snap works"       0 'link "Back"' -- snap $FIX
ok "not owned: text works"       0 'Second page' -- text $FIX
ok "not owned: take_snapshot works" 0 'Back' -- take_snapshot $FIX
ok "not owned: list_pages works" 0 "$FIX:" -- list_pages
ok "not owned: tabs lists it"    0 "$FIX \"" -- tabs
[[ "$OUT" != *"$FIX "*" +"* && "$OUT" != *"$FIX "*" ~"* ]] && { PASS=$((PASS+1)); echo "ok   not owned: no mark on the user's tab"; } || { FAIL=$((FAIL+1)); echo "FAIL mark on user's tab"; }
[[ "$OUT" == *"$TAB \""*"\" 127.0.0.1 +"* ]] && { PASS=$((PASS+1)); echo "ok   tabs marks the tab umb opened with +"; } || { FAIL=$((FAIL+1)); echo "FAIL + mark: $OUT"; }
# An old record from another daemon run (or a reused id) is ignored and dropped.
print -r -- "1 0" > "$HOME/.cache/umb/tabs/own-$FIX"
ok "stale record from another daemon is ignored" 1 "$NOT" -- click $FIX 'css:#plain'
ok "stale record is dropped by tabs" 0 "$FIX" -- tabs
[ ! -e "$HOME/.cache/umb/tabs/own-$FIX" ] && { PASS=$((PASS+1)); echo "ok   stale record file removed"; } || { FAIL=$((FAIL+1)); echo "FAIL stale record kept"; }
ok "lend"                        0 "lent $FIX" -- lend $FIX
ok "lent: tabs marks with ~"     0 "$FIX \"" -- tabs
[[ "$OUT" == *"$FIX "*" ~"* ]] && { PASS=$((PASS+1)); echo "ok   lent tab is marked ~"; } || { FAIL=$((FAIL+1)); echo "FAIL ~ mark: $OUT"; }
ok "lent: run works"             0 'url unchanged' -- run $FIX - <<<'return 1'
ok "lent: pass-through works"    0 '1' -- evaluate_script --pageId $FIX '() => 1'
ok "lent: close refused without --force" 1 'closing it needs: umb close' -- close $FIX
ok "unlend"                      0 "unlent $FIX" -- unlend $FIX
ok "unlent: refused again"       1 "$NOT" -- run $FIX - <<<'return 1'
ok "lend a tab that does not exist fails" 1 'no tab' -- lend 999999
ok "close: junk id fails"        1 'usage: umb close' -- close abc
ok "close: empty id fails"       1 'usage: umb close' -- close
ok "close: negative id fails"    1 'usage: umb close' -- close -1
ok "close: id with trailing text fails" 1 'usage: umb close' -- close "${TAB}x"
ok "close: extra argument fails" 1 'usage: umb close' -- close $TAB extra
ok "owned tab still open after junk closes" 0 "$TAB \"" -- tabs
ok "lend again, then close --force" 0 "lent $FIX" -- lend $FIX
ok "lent: close --force works"   0 "closed $FIX" -- close $FIX --force
FIX=""
ok "profiles lists a profile"    0 'Default' -- profiles
ok "open with an unknown profile fails before opening" 1 'no profile "nope"' -- open "http://127.0.0.1:$PORT/fixture2.html" --profile nope
ok "open option typo fails"      1 'unknown or incomplete open option' -- open "http://127.0.0.1:$PORT/fixture2.html" --profil Default

# Usage log: tagged lines, exit codes, failures counted, no URL paths or typed values.
LOG=~/.local/state/umb/usage.jsonl
MINE=$(grep -F "\"task\": \"$UMB_TASK\"" "$LOG")
N=$(print -r -- "$MINE" | wc -l | tr -d ' ')
FAILED=$(print -r -- "$MINE" | grep -c '"exit": [1-9]')
echo "     log lines for this run: $N (failures: $FAILED)"
[[ $N -eq $CALLS && $FAILED -eq 41 ]] && { PASS=$((PASS+1)); echo "ok   log has $N lines (one per call), $FAILED non-zero exits"; } || { FAIL=$((FAIL+1)); echo "FAIL log lines=$N failures=$FAILED (wanted $CALLS and 41)"; }
OUT=$MINE; absent "log has no URL path" 'fixture.html'; absent "log has no typed value" 'hello world'; absent "log has no scheme" 'http'
ok "cost totals"              0 "$UMB_TASK: " -- cost --task "$UMB_TASK"
ok "cost counts failures"     0 ', 41 failures,' -- cost --task "$UMB_TASK"

echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
