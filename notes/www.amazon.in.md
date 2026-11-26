# Amazon India (www.amazon.in)
Recipe line: run on v2 (recipe header says verified 2026-11-26). Other lines: carried over from v1 notes, not re-verified on v2. <t> = tab id.

- Top results across shops: `umb recipe shop-search '{"query":"running shoes","sites":["amazon.in"],"limit":3}'` prints `site | title | price`, sponsored results left out.
- Search URL: `https://www.amazon.in/s?k=<url-encoded query>`.
- Result cards: `div[data-component-type=s-search-result]`. Skip cards that contain `.puis-sponsored-label-text`.
- Space searches out across shops; the recipe pauses between sites.
