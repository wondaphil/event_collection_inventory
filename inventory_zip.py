import csv, zipfile, datetime, re, io

# --- Read source file explicitly as UTF-8
with io.open("inventory_source.txt", "r", encoding="utf-8") as f:
    lines = [l.strip() for l in f if l.strip()]

categories, items = [], []
current_cat, cat_id, item_id = None, 0, 0
now = datetime.datetime.now().isoformat(timespec="seconds")

for line in lines:
    if line.startswith("* "):
        cat_id += 1
        current_cat = line[2:].strip()
        categories.append((cat_id, current_cat))
    else:
        if not current_cat:
            continue
        item_id += 1
        prefix = "".join(
            [w[0].upper() for w in re.findall(r"[A-Za-z]+", current_cat.split("/")[0].strip())]
        )[:2] or "IT"
        code = f"{prefix}{item_id:03d}"
        items.append([item_id, code, line, "", cat_id, now, now])

# --- Write UTF-8 CSVs
def write_utf8_csv(filename, header, rows):
    with io.open(filename, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)

write_utf8_csv("categories.csv", ["id", "name"], categories)
write_utf8_csv(
    "items.csv",
    ["id", "code", "name", "description", "categoryId", "createdAt", "updatedAt"],
    items,
)

# --- Zip them
with zipfile.ZipFile("inventory_seed_data.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.write("categories.csv")
    z.write("items.csv")

print("✅ Created inventory_seed_data.zip (UTF-8 encoded).")