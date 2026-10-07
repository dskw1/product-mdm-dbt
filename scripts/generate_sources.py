#!/usr/bin/env python3
"""
Generate messy product data from three source systems for the product MDM demo.

Sources (written to ../seeds as CSV):
  raw_erp_products        ERP material master. Some parts exist under two material numbers.
  raw_erp_category_log    ERP category assignments over time (drives the SCD2 hierarchy).
  raw_catalog_products    E-commerce catalog. Nice titles, list prices, the odd MPN typo.
  raw_acq_products        Item file from an acquired distributor. Its own categories,
                          sloppy descriptions, and about a quarter of items missing an MPN.

Also writes mdm_ground_truth.csv, which maps every source record to the real product
it represents. The pipeline never reads it for matching. It's only used to score the
match results (precision and recall).

Standard library only. Deterministic for a given --seed.
"""
import argparse
import csv
import datetime as dt
import os
import random

BRANDS = {
    # canonical brand: (MPN prefix, alias spellings seen in the wild)
    "Arcticline":        ("AL", ["ARCTICLINE", "Arctic Line", "Arcticline Mfg"]),
    "Northwind Comfort": ("NW", ["NORTHWIND", "Northwind Comfort Inc", "N/W Comfort"]),
    "Heliotemp":         ("HT", ["HELIOTEMP", "Helio-Temp", "Heliotemp Corp"]),
    "Corvane":           ("CV", ["CORVANE", "Corvane Controls", "Corvane Inc."]),
    "Bluepeak":          ("BP", ["BLUEPEAK", "Blue Peak", "BluePeak HVAC"]),
    "Ridgeway Air":      ("RW", ["RIDGEWAY", "Ridgeway Air Prod", "Ridgeway"]),
    "Thermaxis":         ("TX", ["THERMAXIS", "Therm-Axis", "Thermaxis LLC"]),
}

# canonical category -> subcategory -> (erp code, catalog path leaf, acquired category name, cost range)
TAXONOMY = {
    "Equipment": {
        "Condensers":   ("EQ-CND", "Condensers",   "Cond Units",   (900, 3800)),
        "Furnaces":     ("EQ-FUR", "Furnaces",     "Gas Furnaces", (700, 2600)),
        "Air Handlers": ("EQ-AHU", "Air Handlers", "AHU",          (650, 2200)),
        "Heat Pumps":   ("EQ-HTP", "Heat Pumps",   "Heat Pump",    (1100, 4200)),
    },
    "Parts": {
        "Motors":       ("PT-MTR", "Motors",       "Motors",       (60, 450)),
        "Capacitors":   ("PT-CAP", "Capacitors",   "Caps",         (8, 60)),
        "Contactors":   ("PT-CON", "Contactors",   "Contactors",   (12, 80)),
        "Compressors":  ("PT-CMP", "Compressors",  "Compressor",   (350, 1600)),
    },
    "Supplies": {
        "Refrigerant":  ("SP-REF", "Refrigerant",  "Refrig",       (90, 420)),
        "Line Sets":    ("SP-LIN", "Line Sets",    "Linesets",     (60, 260)),
        "Filters":      ("SP-FLT", "Filters",      "Filters",      (4, 40)),
    },
    "Controls": {
        "Thermostats":  ("CT-TST", "Thermostats",  "Tstats",       (25, 300)),
        "Sensors":      ("CT-SEN", "Sensors",      "Sensors",      (10, 120)),
    },
}

# Old ERP codes that were retired in a reorg. Products moved off them over time.
LEGACY_CODES = {
    "EQ-CND": "EQUIP-OUT",   # condensers used to sit in "outdoor equipment"
    "EQ-HTP": "EQUIP-OUT",
    "PT-CAP": "PT-ELEC",     # caps and contactors used to share "electrical parts"
    "PT-CON": "PT-ELEC",
}

SERIES = ["Summit", "Granite", "Vector", "Harbor", "Falcon", "Meridian", "Ember", "Cascade",
          "Orion", "Sable", "Atlas", "Pioneer", "Keystone", "Zephyr", "Trident", "Beacon",
          "Sterling", "Juniper", "Apex", "Delta", "Mesa", "Quarry", "Tundra", "Lumen"]

ACQ_DATE = dt.date(2025, 4, 1)
START = dt.date(2019, 1, 1)


def spec_for(sub, rng):
    if sub in ("Condensers", "Heat Pumps"):
        return f"{rng.choice([1.5, 2, 2.5, 3, 3.5, 4, 5])} Ton {rng.choice([14, 15, 16, 18, 20])} SEER"
    if sub == "Furnaces":
        return f"{rng.choice([40, 60, 80, 100, 120])}K BTU {rng.choice([80, 92, 96, 97])}% AFUE"
    if sub == "Air Handlers":
        return f"{rng.choice([2, 2.5, 3, 3.5, 4, 5])} Ton {rng.choice(['Multi-Position', 'Upflow', 'Horizontal'])}"
    if sub == "Motors":
        return f"{rng.choice(['1/6', '1/4', '1/3', '1/2', '3/4', '1'])} HP {rng.choice([825, 1075, 1625])} RPM"
    if sub == "Capacitors":
        return f"{rng.choice([35, 40, 45, 50, 55, 60])}/{rng.choice([3, 5, 7.5, 10])} MFD {rng.choice([370, 440])}V"
    if sub == "Contactors":
        return f"{rng.choice([1, 2, 3])} Pole {rng.choice([30, 40, 50])} Amp {rng.choice([24, 120, 240])}V Coil"
    if sub == "Compressors":
        return f"Scroll {rng.choice([18, 24, 30, 36, 42, 48, 60])}K BTU {rng.choice(['R-410A', 'R-454B'])}"
    if sub == "Refrigerant":
        return f"{rng.choice(['R-410A', 'R-454B', 'R-32', 'R-22'])} {rng.choice([10, 20, 25, 30])} lb Cylinder"
    if sub == "Line Sets":
        return f"{rng.choice(['1/4 x 3/8', '3/8 x 3/4', '3/8 x 7/8'])} {rng.choice([15, 25, 35, 50])} ft"
    if sub == "Filters":
        return f"{rng.choice(['16x20', '16x25', '20x20', '20x25'])}x{rng.choice([1, 2, 4])} MERV {rng.choice([8, 11, 13])}"
    if sub == "Thermostats":
        return f"{rng.choice(['Programmable', 'Smart Wi-Fi', 'Non-Programmable'])} {rng.choice(['1H/1C', '2H/2C', '3H/2C'])}"
    if sub == "Sensors":
        return f"{rng.choice(['Outdoor Temp', 'Duct Temp', 'Humidity', 'CO2'])} {rng.choice(['10K', '20K', '4-20mA'])}"
    return ""


def singular(sub):
    return {"Condensers": "Condenser", "Furnaces": "Furnace", "Air Handlers": "Air Handler",
            "Heat Pumps": "Heat Pump", "Motors": "Motor", "Capacitors": "Capacitor",
            "Contactors": "Contactor", "Compressors": "Compressor", "Refrigerant": "Refrigerant",
            "Line Sets": "Line Set", "Filters": "Filter", "Thermostats": "Thermostat",
            "Sensors": "Sensor"}[sub]


ERP_ABBR = {"Condenser": "COND", "Furnace": "FURN", "Air Handler": "AHU", "Heat Pump": "HP",
            "Motor": "MTR", "Capacitor": "CAP", "Contactor": "CONTR", "Compressor": "COMP",
            "Refrigerant": "REFRIG", "Line Set": "LINESET", "Filter": "FLTR",
            "Thermostat": "TSTAT", "Sensor": "SNSR"}


def mpn_variant(mpn, rng):
    """Same part number, formatted the way a different system would store it."""
    style = rng.random()
    if style < 0.35:
        return mpn
    if style < 0.60:
        return mpn.replace("-", "")
    if style < 0.80:
        return mpn.replace("-", " ").lower()
    return mpn.replace("-", "/")


def typo(s, rng):
    i = rng.randrange(1, len(s) - 1)
    return s[:i] + s[i + 1] + s[i] + s[i + 2:]


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        w.writerows(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--products", type=int, default=2500)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "seeds"))
    args = ap.parse_args()
    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    # ---- the real-world products (never shown to the pipeline) ----
    products, seen = [], set()
    pairs = [(c, s) for c in TAXONOMY for s in TAXONOMY[c]]
    while len(products) < args.products:
        brand = rng.choice(list(BRANDS))
        cat, sub = rng.choice(pairs)
        series = rng.choice(SERIES)
        spec = spec_for(sub, rng)
        title = f"{brand} {series} {spec} {singular(sub)}"
        if title in seen:
            continue
        seen.add(title)
        prefix = BRANDS[brand][0]
        mpn = f"{prefix}-{rng.randint(10000, 99999)}-{rng.choice('ABCDEFGHJK')}"
        lo, hi = TAXONOMY[cat][sub][3]
        cost = round(rng.uniform(lo, hi), 2)
        created = START + dt.timedelta(days=rng.randint(0, 2100))
        products.append(dict(pid=f"P{len(products) + 1:05d}", brand=brand, cat=cat, sub=sub,
                             series=series, spec=spec, title=title, mpn=mpn, cost=cost,
                             created=created))

    truth = []

    # ---- ERP: 85% of products, 5% of those with a duplicate material number ----
    erp_rows, cat_log, mat = [], [], 100_000
    for p in products:
        if rng.random() > 0.85:
            continue
        copies = 2 if rng.random() < 0.05 else 1
        for c in range(copies):
            mat += rng.randint(1, 9)
            material = f"{mat:08d}"
            code = TAXONOMY[p["cat"]][p["sub"]][0]
            desc = f"{ERP_ABBR[singular(p['sub'])]} {p['spec'].upper()} {p['series'][:4].upper()}"
            brand_txt = rng.choice([p["brand"].upper()] + BRANDS[p["brand"]][1][:1])
            created = p["created"] + dt.timedelta(days=rng.randint(0, 400) if c else 0)
            changed = created + dt.timedelta(days=rng.randint(0, 900))
            cost = round(p["cost"] * rng.uniform(0.97, 1.05), 2)
            status = "X" if rng.random() < 0.04 else ""  # X = flagged for deletion in the ERP
            mpn = mpn_variant(p["mpn"], rng)
            erp_rows.append([material, desc, brand_txt, mpn, code, f"{cost:.2f}", "EA",
                             status, created.isoformat(), changed.isoformat()])
            truth.append(["erp", material, p["pid"]])

            # category history: some products started in a legacy code, some got reclassed
            if code in LEGACY_CODES and created < dt.date(2022, 1, 1) and rng.random() < 0.7:
                cat_log.append([material, LEGACY_CODES[code], created.isoformat()])
                moved = dt.date(2022, 1, 1) + dt.timedelta(days=rng.randint(0, 500))
                cat_log.append([material, code, moved.isoformat()])
            else:
                cat_log.append([material, code, created.isoformat()])
            if rng.random() < 0.06:  # someone fat-fingered the category, then fixed it
                wrong = rng.choice([v[0] for s in TAXONOMY.values() for v in s.values() if v[0] != code])
                oops = created + dt.timedelta(days=rng.randint(30, 600))
                cat_log.append([material, wrong, oops.isoformat()])
                cat_log.append([material, code, (oops + dt.timedelta(days=rng.randint(3, 60))).isoformat()])
            if rng.random() < 0.03:  # same code re-saved, should collapse in SCD2
                cat_log.append([material, code, (created + dt.timedelta(days=rng.randint(700, 1200))).isoformat()])

    # ---- Catalog: 70% of products, 2% MPN typos, some brands spelled oddly ----
    catalog_rows = []
    web_ids = iter(rng.sample(range(100000, 1000000), len(products)))
    for p in products:
        if rng.random() > 0.70:
            continue
        sku = f"WEB-{next(web_ids)}"
        mpn = p["mpn"] if rng.random() > 0.02 else typo(p["mpn"], rng)
        brand_txt = p["brand"] if rng.random() > 0.15 else rng.choice(BRANDS[p["brand"]][1])
        leaf = TAXONOMY[p["cat"]][p["sub"]][1]
        path = f"HVAC > {p['cat']} > {leaf}"
        price = round(p["cost"] * rng.uniform(1.25, 1.6), 2)
        published = rng.random() > 0.05
        catalog_rows.append([sku, p["title"], brand_txt, mpn, path, f"{price:.2f}",
                             "true" if published else "false"])
        truth.append(["catalog", sku, p["pid"]])

    # ---- Acquired distributor: 25% of products, 25% of those missing an MPN ----
    acq_rows = []
    acq_ids = iter(rng.sample(range(1000000, 10000000), len(products)))
    for p in products:
        if rng.random() > 0.25:
            continue
        item = f"ACQ{next(acq_ids)}"
        no_mpn = rng.random() < 0.25
        mpn = "" if no_mpn else mpn_variant(p["mpn"], rng)
        brand_txt = rng.choice(BRANDS[p["brand"]][1])
        desc = f"{p['brand']} {p['series']} {p['spec']} {singular(p['sub'])}".lower()
        if rng.random() < 0.3:
            desc = desc.replace(" ton", "t").replace(" seer", "seer")
        acq_cat = TAXONOMY[p["cat"]][p["sub"]][2]
        cost = round(p["cost"] * rng.uniform(0.95, 1.08), 2)
        acq_rows.append([item, desc, brand_txt, mpn, acq_cat, f"{cost:.2f}",
                         ACQ_DATE.isoformat()])
        truth.append(["acquired", item, p["pid"]])

    rng.shuffle(erp_rows)
    rng.shuffle(catalog_rows)
    rng.shuffle(acq_rows)

    write_csv(os.path.join(args.out, "raw_erp_products.csv"),
              ["material_number", "material_desc", "manufacturer", "mfr_part_number", "category_code",
               "standard_cost", "base_uom", "deletion_flag", "created_on", "changed_on"], erp_rows)
    write_csv(os.path.join(args.out, "raw_erp_category_log.csv"),
              ["material_number", "category_code", "effective_date"], cat_log)
    write_csv(os.path.join(args.out, "raw_catalog_products.csv"),
              ["catalog_sku", "title", "brand", "mpn", "category_path", "list_price", "is_published"],
              catalog_rows)
    write_csv(os.path.join(args.out, "raw_acq_products.csv"),
              ["item_id", "item_desc", "vendor_name", "vendor_part_no", "item_category", "last_cost",
               "acquired_on"], acq_rows)
    write_csv(os.path.join(args.out, "mdm_ground_truth.csv"),
              ["source_system", "source_key", "true_product_id"], truth)

    # ---- reference data the pipeline is allowed to use ----
    alias_rows = []
    for brand, (_, aliases) in BRANDS.items():
        for a in sorted(set([brand, brand.upper()] + aliases)):
            alias_rows.append([a, brand])
    write_csv(os.path.join(args.out, "ref_brand_aliases.csv"), ["brand_alias", "brand_name"], alias_rows)

    map_rows = []
    for cat, subs in TAXONOMY.items():
        for sub, (erp, leaf, acq, _) in subs.items():
            map_rows.append(["erp", erp, cat, sub])
            map_rows.append(["catalog", f"HVAC > {cat} > {leaf}", cat, sub])
            map_rows.append(["acquired", acq, cat, sub])
    map_rows.append(["erp", "EQUIP-OUT", "Equipment", "Outdoor Equipment (legacy)"])
    map_rows.append(["erp", "PT-ELEC", "Parts", "Electrical Parts (legacy)"])
    write_csv(os.path.join(args.out, "ref_category_map.csv"),
              ["source_system", "source_category", "category", "subcategory"], map_rows)

    print(f"true products      {len(products):>6,}")
    print(f"erp records        {len(erp_rows):>6,}")
    print(f"erp category log   {len(cat_log):>6,}")
    print(f"catalog records    {len(catalog_rows):>6,}")
    print(f"acquired records   {len(acq_rows):>6,}")


if __name__ == "__main__":
    main()
