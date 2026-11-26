#!/usr/bin/env python3
"""Generate data.tsv deterministically. Run: python3 gen.py > data.tsv"""
import random, datetime
random.seed(2026)
REGIONS = ["North", "South", "East", "West"]
REPS = ["Asha", "Ben", "Chen", "Dara", "Eli", "Farah"]
PRODUCTS = {"Widget": 25, "Gadget": 60, "Gizmo": 120, "Doohickey": 175, "Thingamajig": 240}
start = datetime.date(2026, 1, 1)
span = (datetime.date(2026, 4, 30) - start).days
dates = sorted(start + datetime.timedelta(days=random.randint(0, span)) for _ in range(40))
print("\t".join(["Date", "Region", "Rep", "Product", "Units", "Unit Price"]))
for d in dates:
    p = random.choice(list(PRODUCTS))
    print("\t".join([d.isoformat(), random.choice(REGIONS), random.choice(REPS), p,
                     str(random.randint(1, 40)), str(PRODUCTS[p])]))
