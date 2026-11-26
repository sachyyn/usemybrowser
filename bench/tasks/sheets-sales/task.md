# Task: build a sales spreadsheet in Google Sheets

Do this in the Google Sheets web UI of the user's real, logged-in browser (Google account index 0, so URLs start `https://docs.google.com/spreadsheets/u/0/`).

1. Create a NEW Google Sheets spreadsheet titled exactly `umb-bench {{ARM}} {{RUN_ID}}`.
2. Tab `Data`: put the header and the 40 rows below in A1:F41 (tab separated; Date as a real date, Units and Unit Price as numbers).
3. In `Data`, column G has the header `Revenue` and a formula per row (Units x Unit Price). Column H has the header `Month` and a formula per row that gives `yyyy-mm` from the date (as text, for example `2026-01`).
4. Formatting on `Data`: the header row is bold; the first row is frozen; Unit Price and Revenue use a currency number format.
5. Conditional formatting: Revenue cells (G2:G41) above 5000 get a green fill.
6. Data validation: the Region column (rows 2 to 41) is a dropdown limited to the four regions North, South, East, West.
7. A named range `Revenue` for `Data!G2:G41`.
8. Tab `Summary`. Everything must be a formula, not a typed number:
   - Region totals in `A1:B5`: header `Region | Revenue` in row 1, then North, South, East, West with their revenue.
   - `A7` is `Grand Total` and `B7` is the total revenue.
   - Product totals in `D1:E6`: header `Product | Revenue` in row 1, then the five products.
   - A month-by-region matrix starting at `G1`: `G1` is `Month`, `H1:K1` are the four regions, `G2:G5` are the months 2026-01 to 2026-04 (down), and the cells under the regions hold revenue.
   - `A9` is `Top Rep` and `B9` is a formula that returns the name of the rep with the highest total revenue.
9. A column chart of revenue by region on the `Summary` tab.
10. Report in your final answer: the spreadsheet URL, the grand total, the top region and the top rep.

Rules:
- Work only through the browser tool described below, in the Sheets web UI. Apps Script, the Sheets API, IMPORT functions, uploading a file and add-ons are not allowed.
- Work only in the spreadsheet you created and in tabs you opened yourself. Do not touch any other tab or file. Do not share the file.
- Close the tabs you opened when you are done. Leave the spreadsheet in place.
- If the tool cannot reach the browser, stop and say so. Do not look for another way.

Data (tab separated):

```
{{TSV}}
```
