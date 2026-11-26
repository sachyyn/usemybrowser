"""Pick the tab umb just asked the browser for, out of the tabs that appeared after a launch.

Only a new tab whose host equals the asked URL's host counts (an http to https redirect keeps the host).
A URL with no host (about:blank, file://) must match exactly. The user's own new tabs are never adopted.
Usage: newtab.py <asked url> <list_pages json before> <list_pages json after>; prints the tab id, or nothing.
"""
import json, sys
from urllib.parse import urlparse


def pick(asked, before, after):
    known = {p["id"] for p in before["pages"]}
    new = [p for p in after["pages"] if p["id"] not in known]
    host = urlparse(asked).hostname
    if host:
        hit = [p for p in new if urlparse(p["url"]).hostname == host]
    else:
        hit = [p for p in new if p["url"].rstrip("/") == asked.rstrip("/")]
    exact = [p for p in hit if p["url"].rstrip("/") == asked.rstrip("/")]
    hit = exact if len(exact) == 1 else hit
    return hit[0]["id"] if len(hit) == 1 else None


if __name__ == "__main__":
    i = pick(sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3]))
    if i is not None:
        print(i)
