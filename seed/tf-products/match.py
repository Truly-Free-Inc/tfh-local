#!/usr/bin/env python3
"""Map local catalog products to TF DEV child product ids (pure logic, no network, no DB).

Why: the local catalog is a prod export, so its tf_products.tf_child_product_id values are PROD TF ids. tfh-local
calls the TF DEV Composition API (the system develop/stage use), which answers POST /v1/tax/estimate with 400
"Product not found for tfProductId ..." for them. develop/stage get matching ids from their own product sync
(cron sync-products-to-tf creates the products on TF dev). tfh-local never runs that cron (it WRITES to TF dev);
instead it reads TF dev's product list and matches by SKU.

usage: match.py <local.tsv> <tfdev.json> <out.tsv>
  local.tsv  : product_id <TAB> uuid <TAB> sku <TAB> name        (sticky_products)
  tfdev.json : {"products": [{"id","uuid","sku","name","status"}, ...]}  (TF dev GET /tfh-next-gen/products/)
  out.tsv    : product_id <TAB> tf_child_product_id               (matched rows only)
Prints a one-line JSON summary (counts only; no ids, names or SKUs).

Match rule (deterministic): exact SKU (trimmed, case-insensitive) == TF sellerSku. Products without a SKU are not
matched (names on TF dev are test-suffixed and not unique). Among several TF rows with that SKU prefer:
  1. tfhNextGenProductUuid == the local product uuid
  2. status APPROVED > PENDING_APPROVAL > INACTIVE; REJECTED rows are never used
  3. TF name == local name (case-insensitive)
  4. the newest row (largest 24-hex Mongo ObjectId; its first 8 hex digits are the creation time)
"""
import csv, json, re, sys

STATUS_RANK = {"APPROVED": 0, "PENDING_APPROVAL": 1, "INACTIVE": 2}
OID = re.compile(r"^[0-9a-f]{24}$")


def norm(s):
    return (s or "").strip().lower()


def pick(cands, uuid, name):
    def key(p):
        return (
            0 if norm(p.get("uuid")) == norm(uuid) and uuid else 1,
            STATUS_RANK.get((p.get("status") or "").upper(), 9),
            0 if norm(p.get("name")) == norm(name) and name else 1,
            # newest first: invert the hex id so a plain ascending sort puts the largest id first
            "".join("%x" % (15 - int(c, 16)) for c in p["id"].lower()),
        )
    return sorted(cands, key=key)[0]


def match(local_rows, tf_products):
    by_sku = {}
    for p in tf_products:
        pid = (p.get("id") or "").strip()
        st = (p.get("status") or "").upper()
        if not OID.match(pid.lower()) or st not in STATUS_RANK:
            continue
        k = norm(p.get("sku"))
        if k:
            by_sku.setdefault(k, []).append(dict(p, id=pid))
    out, s = [], {"local": 0, "matched": 0, "uuid_equal": 0, "multi_candidates": 0, "no_sku": 0, "no_match": 0}
    for row in local_rows:
        if len(row) < 4:
            continue
        product_id, uuid, sku, name = row[0].strip(), row[1], row[2], row[3]
        if not product_id.isdigit():
            continue
        s["local"] += 1
        k = norm(sku)
        if not k:
            s["no_sku"] += 1
            continue
        cands = by_sku.get(k)
        if not cands:
            s["no_match"] += 1
            continue
        if len(cands) > 1:
            s["multi_candidates"] += 1
        best = pick(cands, uuid, name)
        if norm(best.get("uuid")) == norm(uuid):
            s["uuid_equal"] += 1
        s["matched"] += 1
        out.append((product_id, best["id"]))
    return out, s


def main(argv):
    if len(argv) != 4:
        sys.stderr.write(__doc__)
        return 2
    with open(argv[1], newline="") as f:
        local_rows = list(csv.reader(f, delimiter="\t"))
    with open(argv[2]) as f:
        tf = json.load(f)
    products = tf.get("products") if isinstance(tf, dict) else None
    if not isinstance(products, list) or not products:
        sys.stderr.write("match.py: TF product list is empty or malformed; refusing (would unmap everything)\n")
        return 3
    rows, summary = match(local_rows, products)
    with open(argv[3], "w", newline="") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        for r in rows:
            w.writerow(r)
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
