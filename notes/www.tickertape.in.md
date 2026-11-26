# TickerTape (www.tickertape.in)
Recipe line: run on v2 (recipe header says verified 2026-11-26). Other lines: carried over from v1 notes, not re-verified on v2. <t> = tab id.

## Screener columns
- `umb recipe tickertape-columns '{"columns":["Debt to Equity","5Y Revenue Growth"]}' --tab <t>` on `https://www.tickertape.in/screener/equity`. It skips columns already present (clicking a selected filter removes it) and reports substitutions.
- Each added filter becomes an export column. Adding columns does not drop blank rows. Default PE and 1M Return are columns, not active filters.

## Screener filters
- Smallcap and Midcap buttons replace each other. Set the market-cap min spinbutton to 0 instead. Filling the max spinbutton and pressing Enter also works as a cap filter.
- Sub-sectors: expand a sector by clicking `.sector-top [class*=icon-chevron]` in `umb run`, then click sub-sector names to untick them.
- Export dialog has a file-name box; the CSV lands in ~/Downloads.
