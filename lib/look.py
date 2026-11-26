# umb look helper: ask a small Gemini vision model one question about a JPEG; print only its short answer.
# Usage: look.py <image.jpg> <question> <max-chars>.   Docs: https://ai.google.dev/gemini-api/docs/image-understanding
# Key: $GEMINI_API_KEY, else Keychain item "gemini-api-key" (same lookup as bin/decide). Never printed or logged.
# Model: $UMB_LOOK_MODEL, default gemini-3.5-flash-lite ($0.30 in / $2.50 out per 1M tokens: https://ai.google.dev/gemini-api/docs/pricing).
# gemini-2.5-flash-lite is cheaper but the API refuses new users; gemini-3.1-flash-lite ($0.25 / $1.50) dropped a cell when reading a sheet.
# If $UMB_EXTRA names a file, the model's token counts are written there for the usage log.
import base64, json, os, subprocess, sys, urllib.error, urllib.request

MODEL = os.environ.get("UMB_LOOK_MODEL") or "gemini-3.5-flash-lite"
SYSTEM = ("You answer questions about a screenshot. Answer in at most 2 short lines. "
          "If asked to read a table or a block of cells, answer as compact rows, one row per line, cells separated by ' | '. "
          "No preamble, no markdown.")


def fail(msg):
    sys.exit("umb: look: " + msg)


def api_key():
    key = os.environ.get("GEMINI_API_KEY")
    if key:
        return key
    out = subprocess.run(["security", "find-generic-password", "-s", "gemini-api-key", "-w"], capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        fail("no Gemini key. Set GEMINI_API_KEY or add Keychain item 'gemini-api-key'.")
    return out.stdout.strip()


def main():
    path, question, max_chars = sys.argv[1], sys.argv[2], int(sys.argv[3])
    body = {
        "systemInstruction": {"parts": [{"text": SYSTEM}]},
        "contents": [{"parts": [{"text": question},  # text first, then the image, as the docs advise
                                {"inline_data": {"mime_type": "image/jpeg", "data": base64.b64encode(open(path, "rb").read()).decode()}}]}],
        "generationConfig": {"temperature": 0, "maxOutputTokens": 400},
    }
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent",
        data=json.dumps(body).encode(), method="POST",
        headers={"x-goog-api-key": api_key(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            res = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        if e.code in (401, 402, 403) or "API key" in detail:
            fail(f"the Gemini API refused the request (HTTP {e.code}); check the key and billing.")
        try: detail = json.loads(detail)["error"]["message"]
        except Exception: pass
        fail(f"HTTP {e.code}: {detail[:200]}")
    except urllib.error.URLError as e:
        fail(f"could not reach the Gemini API: {e.reason}")
    u = res.get("usageMetadata", {})
    if os.environ.get("UMB_EXTRA"):
        with open(os.environ["UMB_EXTRA"], "w") as f:
            json.dump({"model": MODEL, "model_in": u.get("promptTokenCount"),
                       "model_out": (u.get("candidatesTokenCount") or 0) + (u.get("thoughtsTokenCount") or 0)}, f)
    parts = (res.get("candidates") or [{}])[0].get("content", {}).get("parts", [])
    text = "".join(p.get("text", "") for p in parts).strip()
    if not text:
        fail("the model returned no text" + (f" (blocked: {res['promptFeedback'].get('blockReason')})" if res.get("promptFeedback") else ""))
    print(text if len(text) <= max_chars else text[:max_chars] + f"\n-- cut at {max_chars} of {len(text)} chars")


main()
