# Flipkart (www.flipkart.com)
Recipe line: run on v2 (recipe header says verified 2026-11-26). Other lines: carried over from v1 notes, not re-verified on v2. <t> = tab id.

- Top results: `umb recipe shop-search '{"query":"running shoes","sites":["flipkart"]}'`.
- Search URL: `https://www.flipkart.com/search?q=<url-encoded query>`.
- Result cards: `a[href*="/p/"]`, then `closest("div[data-id]")`.
