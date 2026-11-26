#!/usr/bin/env python3
"""Objective checker for the sheets-sales task. No model involved.

Usage: check.py <spreadsheet-url> <task> [--title "umb-bench v1 <run_id>"] [--xlsx saved.xlsx] [--keep PATH]

Downloads the spreadsheet as .xlsx through the logged-in browser (v1 `helium` command), parses it with
the standard library, prints PASS/FAIL/UNKNOWN per check and `score: N/M` (UNKNOWN is not counted in M).
Exit 0 when it could fetch and parse; non-zero otherwise.
"""
import argparse, collections, csv, datetime, io, json, re, subprocess, sys, time, zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

BENCH = Path(__file__).resolve().parent
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
      "c": "http://schemas.openxmlformats.org/drawingml/2006/chart",
      "dr": "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"}
M = "{%s}" % NS["m"]
REGIONS = ["North", "South", "East", "West"]


# ---------- fetching through the browser ----------
def helium(*args):
    p = subprocess.run(["helium", *args, "--output-format", "json"], capture_output=True, text=True, timeout=180)
    out = p.stdout
    i = out.find("{")
    if p.returncode or i < 0:
        raise RuntimeError(f"helium {args[0]} failed: {(p.stderr or out)[:300]}")
    return json.JSONDecoder().raw_decode(out[i:])[0]


def js(page, src):
    msg = helium("evaluate_script", "--pageId", str(page), src)["message"]
    m = re.search(r"```json\n(.*)\n```", msg, re.S)
    if not m:
        raise RuntimeError("evaluate_script gave no json: " + msg[:300])
    return json.loads(m.group(1))


def page_ids():
    return {p["id"] for p in helium("list_pages")["pages"]}


def fetch_xlsx(sheet_id):
    """Export redirects cross-origin without CORS, so an in-page fetch cannot read it.
    Instead a background tab navigates to the export URL; the browser saves the file to its
    download folder (logged in), we read that one new file and delete it."""
    dl = Path.home() / "Downloads"
    before_pages, before_files = page_ids(), set(dl.glob("*.xlsx"))
    t0 = time.time()
    page = helium("new_page", f"https://docs.google.com/spreadsheets/d/{sheet_id}/edit", "--background")["pages"][-1]["id"]
    try:
        title = js(page, "() => document.title")
        helium("new_page", f"https://docs.google.com/spreadsheets/d/{sheet_id}/export?format=xlsx", "--background")
        want = dl / (re.sub(r"\s*-\s*Google Sheets$", "", title) + ".xlsx")
        for _ in range(60):
            new = [f for f in set(dl.glob("*.xlsx")) - before_files if f.stat().st_mtime >= t0 - 1] or \
                  ([want] if want.exists() and want.stat().st_mtime >= t0 - 1 else [])
            if new and not list(dl.glob("*.crdownload")):
                time.sleep(1)
                f = new[0]
                data = f.read_bytes()
                f.unlink()
                return data, title
            time.sleep(1)
        raise RuntimeError("export download did not appear in the download folder")
    finally:
        for pid in page_ids() - before_pages:
            try:
                helium("close_page", str(pid))
            except Exception as e:  # report, do not hide a leaked tab
                print(f"WARNING: could not close tab {pid}: {e}", file=sys.stderr)


# ---------- xlsx parsing ----------
def col_num(letters):
    n = 0
    for ch in letters:
        n = n * 26 + ord(ch) - 64
    return n


class Book:
    def __init__(self, data):
        self.z = zipfile.ZipFile(io.BytesIO(data))
        self.wb = self.xml("xl/workbook.xml")
        rels = {r.get("Id"): r.get("Target") for r in self.xml("xl/_rels/workbook.xml.rels")}
        self.sheets = {}
        for s in self.wb.find("m:sheets", NS):
            t = rels[s.get("{%s}id" % NS["r"])].lstrip("/")
            self.sheets[s.get("name")] = t if t.startswith("xl/") else "xl/" + t
        self.sst = []
        if "xl/sharedStrings.xml" in self.z.namelist():
            for si in self.xml("xl/sharedStrings.xml"):
                self.sst.append("".join(t.text or "" for t in si.iter(M + "t")))
        self.styles = self.xml("xl/styles.xml")
        self.cells = {n: self.read_cells(p) for n, p in self.sheets.items()}

    def xml(self, name):
        return ET.fromstring(self.z.read(name))

    def read_cells(self, path):
        out = {}
        for c in self.xml(path).iter(M + "c"):
            ref = c.get("r")
            v, f, t = c.find("m:v", NS), c.find("m:f", NS), c.get("t")
            val = None
            if t == "inlineStr":
                val = "".join(x.text or "" for x in c.iter(M + "t"))
            elif v is not None and v.text is not None:
                if t == "s":
                    val = self.sst[int(v.text)]
                elif t in ("str", "e"):
                    val = v.text
                elif t == "b":
                    val = v.text == "1"
                else:
                    val = float(v.text)
            out[ref] = {"v": val, "f": f is not None, "s": int(c.get("s", 0)), "ft": (f.text if f is not None else None)}
        return out

    def xf(self, style):
        return self.styles.find("m:cellXfs", NS)[style]

    def numfmt(self, style):
        fid = int(self.xf(style).get("numFmtId", 0))
        for nf in self.styles.iterfind("m:numFmts/m:numFmt", NS):
            if int(nf.get("numFmtId")) == fid:
                return fid, nf.get("formatCode")
        return fid, None

    def bold(self, style):
        font = self.styles.find("m:fonts", NS)[int(self.xf(style).get("fontId", 0))]
        b = font.find("m:b", NS)
        return b is not None and b.get("val", "1") not in ("0", "false")


def is_currency(fid, code):
    if code:
        return bool(re.search(r"\$|\[\$|€|£|¥|₹|currency", code, re.I))
    return fid in (5, 6, 7, 8, 37, 38, 39, 40, 44)


def iso(v):
    if isinstance(v, float):
        return (datetime.date(1899, 12, 30) + datetime.timedelta(days=int(v))).isoformat()
    return str(v)[:10] if v else None


def load_expected(task):
    rows = list(csv.reader(open(BENCH / "tasks" / task / "data.tsv"), delimiter="\t"))
    head, rows = rows[0], rows[1:]
    e = {"head": head, "rows": rows, "reg": collections.Counter(), "prod": collections.Counter(),
         "rep": collections.Counter(), "mat": collections.Counter(), "rev": [], "month": []}
    for d, reg, rep, prod, u, p in rows:
        rev = int(u) * int(p)
        e["rev"].append(rev)
        e["month"].append(d[:7])
        e["reg"][reg] += rev
        e["prod"][prod] += rev
        e["rep"][rep] += rev
        e["mat"][(d[:7], reg)] += rev
    e["total"] = sum(e["rev"])
    e["top_rep"] = e["rep"].most_common(1)[0][0]
    e["top_region"] = e["reg"].most_common(1)[0][0]
    return e


# ---------- checks ----------
class Results:
    def __init__(self):
        self.items = []

    def add(self, name, status, why=""):
        self.items.append((name, status, why))
        print(f"{status}  {name}" + (f": {why}" if why else ""))

    def ok(self, name, cond, why_pass="", why_fail=""):
        self.add(name, "PASS" if cond else "FAIL", why_pass if cond else why_fail)


def close(a, b):
    return isinstance(a, (int, float)) and abs(a - b) < 0.01


def run_checks(bk, e, title, want_title, R):
    if want_title:
        R.ok("title", title == want_title, title, f"got {title!r}, want {want_title!r}")
    else:
        R.ok("title", bool(title) and title.startswith("umb-bench "), title, f"got {title!r}")

    R.ok("tabs Data and Summary exist", "Data" in bk.sheets and "Summary" in bk.sheets, "", f"tabs: {list(bk.sheets)}")
    D, S = bk.cells.get("Data", {}), bk.cells.get("Summary", {})
    g = lambda cells, ref: cells.get(ref, {}).get("v")

    nrows = {int(re.sub(r"\D", "", r)) for r in D if re.match(r"[A-F]\d+$", r) and D[r]["v"] not in (None, "")}
    head = [g(D, c + "1") for c in "ABCDEF"]
    R.ok("Data has header + 40 rows", max(nrows, default=0) == 41 and len(nrows) == 41 and head == e["head"],
         "41 rows, header ok", f"rows={len(nrows)} max={max(nrows, default=0)} header={head}")

    bad = []
    for r in (2, 10, 20, 30, 41):
        want = e["rows"][r - 2]
        got = [iso(g(D, f"A{r}")), g(D, f"B{r}"), g(D, f"C{r}"), g(D, f"D{r}"), g(D, f"E{r}"), g(D, f"F{r}")]
        ok = got[:4] == [want[0], want[1], want[2], want[3]] and close(got[4], int(want[4])) and close(got[5], int(want[5]))
        if not ok:
            bad.append((r, got))
    R.ok("5 sampled data rows (2,10,20,30,41) match", not bad, "", f"mismatch {bad[:2]}")

    gcells = [D.get(f"G{r}", {}) for r in range(2, 42)]
    R.ok("G2:G41 are formulas", all(c.get("f") for c in gcells) and g(D, "G1") == "Revenue",
         "", f"{sum(1 for c in gcells if c.get('f'))}/40 formulas, G1={g(D, 'G1')!r}")
    wrong = [r for r in range(2, 42) if not close(g(D, f"G{r}"), e["rev"][r - 2])]
    R.ok("G2:G41 cached values correct", not wrong, "", f"wrong rows {wrong[:5]}")
    hcells = [D.get(f"H{r}", {}) for r in range(2, 42)]
    R.ok("H2:H41 are formulas", all(c.get("f") for c in hcells) and g(D, "H1") == "Month",
         "", f"{sum(1 for c in hcells if c.get('f'))}/40 formulas, H1={g(D, 'H1')!r}")
    wrong = [r for r in range(2, 42) if g(D, f"H{r}") != e["month"][r - 2]]
    R.ok("H values are yyyy-mm and correct", not wrong, "", f"wrong rows {wrong[:5]}, e.g. {g(D, 'H2')!r}")

    hdr = [D[c + "1"]["s"] for c in "ABCDEFGH" if c + "1" in D]
    R.ok("header row bold", len(hdr) == 8 and all(bk.bold(s) for s in hdr), "", "A1:H1 not all bold")

    sv = bk.xml(bk.sheets["Data"]).find("m:sheetViews/m:sheetView/m:pane", NS)
    R.ok("first row frozen", sv is not None and sv.get("state") == "frozen" and float(sv.get("ySplit", 0)) == 1 and float(sv.get("xSplit", 0)) == 0,
         "", "no frozen pane with ySplit=1" if sv is None else f"pane={sv.attrib}")

    fm = {c: bk.numfmt(D[c + "2"]["s"]) for c in "FG" if c + "2" in D}
    R.ok("currency format on F and G", len(fm) == 2 and all(is_currency(*v) for v in fm.values()),
         str(fm), f"formats {fm}")

    sh = bk.xml(bk.sheets["Data"])
    cf = []
    for blk in sh.iterfind("m:conditionalFormatting", NS):
        for rule in blk.iterfind("m:cfRule", NS):
            cf.append((blk.get("sqref"), rule.get("type"), rule.get("operator"), [f.text for f in rule.iterfind("m:formula", NS)], rule.get("dxfId")))
    hit = [c for c in cf if c[0] and c[0].startswith("G") and "5000" in " ".join(c[3])
           and (c[2] in ("greaterThan",) or c[1] == "expression")]
    fill = ""
    if hit and hit[0][4] is not None:
        dxf = bk.styles.find("m:dxfs", NS)[int(hit[0][4])]
        col = dxf.find("m:fill/m:patternFill/m:bgColor", NS)
        col = col if col is not None else dxf.find("m:fill/m:patternFill/m:fgColor", NS)
        fill = col.get("rgb", "") if col is not None else ""
    R.ok("conditional format on G, > 5000", bool(hit), f"{hit[0][:4]} fill={fill or '?'}", f"rules: {cf}")
    if hit and fill and len(fill) >= 6:
        r_, g_, b_ = (int(fill[-6:][i:i + 2], 16) for i in (0, 2, 4))
        R.ok("conditional fill is greenish", g_ > r_ and g_ > b_, fill, f"fill {fill} is not green-dominant")

    dv = []
    for v in sh.iterfind("m:dataValidations/m:dataValidation", NS):
        f1 = v.find("m:formula1", NS)
        dv.append((v.get("type"), v.get("sqref"), f1.text if f1 is not None else None))
    def allowed(f1):
        if not f1:
            return None
        if f1.startswith('"'):
            return [x.strip() for x in f1.strip('"').split(",")]
        m = re.match(r"(?:'?(\w+)'?!)?\$?([A-Z]+)\$?(\d+):\$?([A-Z]+)\$?(\d+)$", f1)
        if m:
            cells = bk.cells.get(m.group(1) or "Data", {})
            return [str(cells.get(f"{m.group(2)}{r}", {}).get("v")) for r in range(int(m.group(3)), int(m.group(5)) + 1)]
        return None
    hit = [d for d in dv if d[0] == "list" and d[1] and re.match(r"B", d[1]) and allowed(d[2]) and set(allowed(d[2])) == set(REGIONS)]
    R.ok("Region dropdown limited to 4 regions", bool(hit), str(hit[0]) if hit else "", f"validations: {dv}")

    dn = {d.get("name"): (d.text or "") for d in bk.wb.iterfind("m:definedNames/m:definedName", NS)}
    R.ok("named range Revenue = Data!G2:G41", dn.get("Revenue", "").replace("$", "").replace("'", "") == "Data!G2:G41",
         dn.get("Revenue"), f"names: {dn}")

    # Summary
    reg_ok, reg_f, row_of = True, True, {}
    for r in range(2, 6):
        row_of[g(S, f"A{r}")] = r
    wrong = []
    for reg, want in e["reg"].items():
        r = row_of.get(reg)
        c = S.get(f"B{r}", {}) if r else {}
        if not close(c.get("v"), want):
            wrong.append((reg, c.get("v"), want))
        reg_f &= bool(c.get("f"))
    R.ok("region totals A1:B5 values", g(S, "A1") == "Region" and g(S, "B1") == "Revenue" and not wrong,
         "", f"A1={g(S, 'A1')!r} B1={g(S, 'B1')!r} wrong={wrong}")
    R.ok("region totals are formulas", reg_f and len(row_of) == 4, "", "some B2:B5 are typed values")
    R.ok("Grand Total in A7/B7", g(S, "A7") == "Grand Total" and close(g(S, "B7"), e["total"]),
         f"{g(S, 'B7')}", f"A7={g(S, 'A7')!r} B7={g(S, 'B7')!r} want {e['total']}")
    R.ok("Grand Total is a formula", bool(S.get("B7", {}).get("f")), "", "B7 is a typed value")
    prow = {g(S, f"D{r}"): r for r in range(2, 7)}
    wrong = [(p, g(S, f"E{prow.get(p, 0)}"), w) for p, w in e["prod"].items() if not close(g(S, f"E{prow.get(p, 0)}"), w)]
    nf = [p for p in e["prod"] if not S.get(f"E{prow.get(p, 0)}", {}).get("f")]
    R.ok("product totals D1:E6 values", g(S, "D1") == "Product" and not wrong, "", f"D1={g(S, 'D1')!r} wrong={wrong}")
    R.ok("product totals are formulas", not nf and len(prow) == 5, "", f"typed values for {nf}")

    cols = {g(S, f"{c}1"): c for c in "HIJK"}
    mrow = {g(S, f"G{r}"): r for r in range(2, 6)}
    wrong, nf = [], 0
    for (mon, reg), want in e["mat"].items():
        ref = f"{cols.get(reg, '?')}{mrow.get(mon, 0)}"
        c = S.get(ref, {})
        if not close(c.get("v"), want):
            wrong.append((mon, reg, c.get("v"), want))
        nf += 0 if c.get("f") else 1
    R.ok("month x region matrix values", g(S, "G1") == "Month" and not wrong and len(mrow) == 4 and len(cols) == 4,
         "", f"G1={g(S, 'G1')!r} wrong={wrong[:3]} months={list(mrow)} cols={list(cols)}")
    R.ok("matrix cells are formulas", nf == 0, "", f"{nf} cells without formula")
    R.ok("Top Rep value", g(S, "A9") == "Top Rep" and g(S, "B9") == e["top_rep"], g(S, "B9"),
         f"A9={g(S, 'A9')!r} B9={g(S, 'B9')!r} want {e['top_rep']!r}")
    R.ok("Top Rep is a formula", bool(S.get("B9", {}).get("f")), "", "B9 is typed")

    # chart on Summary
    chart = None
    sp = bk.sheets.get("Summary", "")
    rels_name = sp.replace("worksheets/", "worksheets/_rels/") + ".rels"
    if rels_name in bk.z.namelist():
        for rel in bk.xml(rels_name):
            if rel.get("Type", "").endswith("/drawing"):
                dpath = "xl/" + rel.get("Target").replace("../", "")
                drels = dpath.replace("drawings/", "drawings/_rels/") + ".rels"
                if drels in bk.z.namelist():
                    for r2 in bk.xml(drels):
                        if r2.get("Type", "").endswith("/chart"):
                            chart = bk.xml("xl/" + r2.get("Target").replace("../", ""))
    if chart is None:
        R.ok("column chart on Summary", False, "", "no chart in Summary's drawing")
    else:
        bar = chart.find(".//c:barChart/c:barDir", NS)
        refs = [f.text for f in chart.iter("{%s}f" % NS["c"])]
        R.ok("column chart on Summary", bar is not None and bar.get("val") == "col", f"refs {refs}",
             f"chart is not a column chart ({'bar dir ' + bar.get('val') if bar is not None else 'no barChart'})")
        R.ok("chart plots the region totals (A2:B5)", any("$A$2:$A$5" in x or "A2:A5" in x for x in refs) and
             any("$B$2:$B$5" in x or "B2:B5" in x for x in refs), "", f"refs {refs}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("task")
    ap.add_argument("--title")
    ap.add_argument("--xlsx", help="parse this local file instead of fetching")
    ap.add_argument("--keep", help="save the downloaded xlsx here")
    a = ap.parse_args()
    m = re.search(r"/spreadsheets/(?:u/\d+/)?d/([\w-]+)", a.url)
    if not m:
        sys.exit("not a spreadsheet url")
    try:
        if a.xlsx:
            data, title = Path(a.xlsx).read_bytes(), ""
        else:
            data, title = fetch_xlsx(m.group(1))
        if a.keep:
            Path(a.keep).write_bytes(data)
        title = re.sub(r"\s*-\s*Google Sheets$", "", title)
        bk = Book(data)
        e = load_expected(a.task)
    except Exception as ex:
        print(f"could not fetch or parse: {ex}", file=sys.stderr)
        sys.exit(2)
    R = Results()
    run_checks(bk, e, title, a.title, R)
    n = sum(1 for _, s, _ in R.items if s != "UNKNOWN")
    p = sum(1 for _, s, _ in R.items if s == "PASS")
    print(f"expected: grand total {e['total']}, top region {e['top_region']}, top rep {e['top_rep']}")
    print(f"score: {p}/{n}")


main()
