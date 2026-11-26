#!/bin/zsh
# Smoke test: runs umb against test/fixture.html in a new background tab of the running browser.
# Needs the chrome-devtools daemon already attached (it never starts one). Closes its tab when done.
HERE=${0:A:h}; UMB=${HERE:h}/bin/umb
cd "$HERE" || exit 1
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 & SRV=$!
export UMB_TASK="smoke-$$"; unset UMB_NO_LOG
PASS=0; FAIL=0; TAB=""; CALLS=1  # umb open is call 1
cleanup() { [ -n "$TAB" ] && "$UMB" close "$TAB" >/dev/null 2>&1; kill $SRV 2>/dev/null; }
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

ok "link click navigates"     0 '(navigated)'                 -- click $TAB 'text:Go next'
ok "snap after navigation"    0 'link "Back"'                 -- snap $TAB

# Usage log: tagged lines, exit codes, failures counted, no URL paths or typed values.
LOG=~/.local/state/umb/usage.jsonl
MINE=$(grep -F "\"task\": \"$UMB_TASK\"" "$LOG")
N=$(print -r -- "$MINE" | wc -l | tr -d ' ')
FAILED=$(print -r -- "$MINE" | grep -c '"exit": [1-9]')
echo "     log lines for this run: $N (failures: $FAILED)"
[[ $N -eq $CALLS && $FAILED -eq 5 ]] && { PASS=$((PASS+1)); echo "ok   log has $N lines (one per call), $FAILED non-zero exits"; } || { FAIL=$((FAIL+1)); echo "FAIL log lines=$N failures=$FAILED (wanted $CALLS and 5)"; }
OUT=$MINE; absent "log has no URL path" 'fixture.html'; absent "log has no typed value" 'hello world'; absent "log has no scheme" 'http'
ok "cost totals"              0 "$UMB_TASK: " -- cost --task "$UMB_TASK"
ok "cost counts failures"     0 ', 5 failures,' -- cost --task "$UMB_TASK"

echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
