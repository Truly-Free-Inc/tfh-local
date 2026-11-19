#!/usr/bin/env python3
"""Customer/order DATA scan for the catalog export (run by `make seed-catalog` before every load).

The rule (Michael, Nov 19 2026): scan every exported column and every value - including keys and values nested in
JSON columns - for CUSTOMER data (emails, phones, person names, postal addresses, card-like numbers, ids that point
at a person) and ORDER data (order/transaction/charge/subscription/cart ids, order totals, line items, shipping
or tracking info). It does NOT trust table names: a table called `orders_whatever` is judged by its rows, and a
catalog table called `order_bump_configurations` is fine as long as its rows hold no customer/order data.

Outcome per table:
  EXCLUDE      a populated person-id / order-id column (the rows ARE customer or order records) -> written as []
  DROP_COLS    some columns hold customer/order data -> those columns are removed from every row
  KEEP         nothing found
Never prints, logs or writes values: output is table / column / detector / count only.

Usage: python3 -I pii_scan.py IN_DATA_DIR OUT_DIR      (writes OUT_DIR/data/<table>.json + OUT_DIR/SCAN.json)
Exit 0 = clean copy written; 2 = usage/input error. Tables only ever get MORE restricted than the input.
"""
import collections, json, os, re, sys

# ---- name signals (top-level columns AND nested JSON keys), only count when the value is populated ----
_ID = r"_?(id|ids|uuid|number|no|num)"
PERSON_ID = re.compile(
    r"^(sticky_)?(customer|customers|user|member|account|contact|subscriber|profile|identity|kratos_identity|shopper|"
    r"buyer|recipient|person|lead|prospect|patient|referrer|referee|klaviyo_profile|braintree_customer|stripe_customer)"
    + _ID + r"$", re.I)
ORDER_ID = re.compile(
    r"^(sticky_|parent_|ancestor_|original_|rebill_|child_|previous_|last_|first_|source_)?"
    r"(order|orders|transaction|txn|charge|payment_intent|invoice|refund|chargeback|subscription|cart|checkout_session|"
    r"shipment|fulfillment|fulfilment|return|rma|receipt|gateway_transaction)" + _ID + r"$", re.I)
PERSON_FIELD = re.compile(
    r"^(e_?mail|email_?address|emails|[a-z_]*_email|phone|phones|phone_?number|[a-z_]*_phone|mobile|cell|telephone|fax|"
    r"first_?name|last_?name|middle_?name|full_?name|surname|given_?name|family_?name|customer_?name|[a-z_]*_full_name|"
    r"billing_?name|shipping_?name|recipient_?name|dob|date_of_birth|birth_?date|birthday|ssn|tax_?id|"
    r"ip|ip_?address|user_?agent|device_?id|fingerprint|password|password_hash|passwd)$", re.I)
ADDRESS_STRONG = re.compile(
    r"^(address|addresses|address_?(line_?)?[12]?|street|street_?[12]|street_?address|"
    r"(billing|shipping|ship|bill|home|mailing|delivery)_?(address|street|addr)[a-z0-9_]*|ship_to|bill_to)$", re.I)
ADDRESS_PART = {"city": re.compile(r"^(city|town)$", re.I),
                "zip": re.compile(r"^(zip|zipcode|zip_?code|postal|postal_?code|postcode)$", re.I)}
ORDER_FIELD = re.compile(
    r"^((order|grand|sub)_?total|order_?amount|amount_?(paid|charged|refunded|captured|authorized)|total_?(paid|charged)|"
    r"refund_?amount|line_?items|order_?items|order_?lines|items_?ordered|tracking|tracking_?(number|no|code|url)|"
    r"carrier_?tracking[a-z_]*|auth_?code|avs[a-z_]*|cvv[a-z_]*|card_?(number|last_?4|brand|exp[a-z_]*|holder[a-z_]*)|"
    r"cc_[a-z_]+|last_?4|last_?four|bin|gateway_?response|processor_?response|decline_?reason|paid_at|"
    r"shipped_at|delivered_at|refunded_at|charged_at)$", re.I)

# ---- value signals ----
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})")
COMPANY_DOMAIN = re.compile(r"(^|\.)(trulyfreehome\.com|trulyfree\.com|mygreenfills\.com)$", re.I)
ROLE_LOCAL = re.compile(r"^(support|help|hello|hi|info|care|customercare|customer\.care|customerservice|"
                        r"customer\.service|service|team|noreply|no-reply|donotreply|contact|press|media|privacy|legal|"
                        r"returns|family|wholesale|affiliates?|partners?|marketing|feedback|careers|billing|accounts|sales)$", re.I)
PLACEHOLDER_DOMAIN = re.compile(r"(^|\.)(example\.(com|org|net)|test|invalid|localhost)$", re.I)
PHONE = re.compile(r"(?<![\w.])(?:\+?1[-. ]?)?\(?([2-9]\d{2})\)?[-. ]([2-9]\d{2})[-. ](\d{4})(?![\w.])")
TOLL_FREE = {"800", "833", "844", "855", "866", "877", "888"}
SSN = re.compile(r"(?<![\d-])\d{3}-\d{2}-\d{4}(?![\d-])")
STREET = re.compile(r"\b\d{1,6}\s+(?:[NSEW]\.?\s+)?[A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+){0,2}\s+"
                    r"(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Ct|Court|Way|Pkwy|Parkway|Hwy|"
                    r"Highway|Pl|Place|Ter|Terrace|Cir|Circle)\b\.?(?:.{0,80}?\b\d{5}(?:-\d{4})?\b)", re.S)
CARD_CAND = re.compile(r"(?<![\w/.-])(?:\d[ -]?){12,18}\d(?![\w/.-])")
TRACKING = re.compile(r"\b(1Z[0-9A-Z]{16}|9[2-5]\d{20,24})\b")
ORDER_REF = re.compile(r"\border\s*(?:#|no\.?|number|id)\s*:?\s*#?\s*\d{5,}\b", re.I)
IPV4 = re.compile(r"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.])")
IP_AS_URL_HOST = re.compile(r"://(?:\d{1,3}\.){3}\d{1,3}")
SECRET = re.compile(r"(sk_live_|pk_live_|rk_live_|AKIA[0-9A-Z]{16}|xox[abprs]-|ghp_[A-Za-z0-9]{20,}|"
                    r"-----BEGIN [A-Z ]*PRIVATE KEY|AIza[0-9A-Za-z_-]{30,}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.)")
URLISH = re.compile(r"^(https?://|/)|^[0-9a-fA-F-]{36}$")


def luhn(d):
    s, alt = 0, False
    for ch in reversed(d):
        x = int(ch)
        if alt:
            x *= 2
            if x > 9:
                x -= 9
        s += x
        alt = not alt
    return s % 10 == 0


def populated(v):
    return v not in (None, "", [], {}, 0, False) and not (isinstance(v, str) and v.strip() in ("", "0", "null"))


def maybe_json(v):
    if isinstance(v, str) and v[:1] in "{[":
        try:
            return json.loads(v)
        except ValueError:
            return v
    return v


def walk(v, key=None):
    """yield (key, scalar) for every scalar, with the innermost dict key; also re-parses JSON strings."""
    v = maybe_json(v)
    if isinstance(v, dict):
        keys = {str(k).lower() for k, x in v.items() if populated(maybe_json(x))}
        yield ("__keys__", keys)
        for k, x in v.items():
            yield from walk(x, str(k))
    elif isinstance(v, list):
        for x in v:
            yield from walk(x, key)
    elif v is not None:
        yield (key, v)


def name_hits(name, keyset=None):
    out = []
    if PERSON_ID.match(name):
        out.append("person_id")
    if ORDER_ID.match(name):
        out.append("order_id")
    if PERSON_FIELD.match(name):
        out.append("person_field")
    if ADDRESS_STRONG.match(name):
        out.append("address_field")
    if ORDER_FIELD.match(name):
        out.append("order_field")
    return out


def address_parts(keys):
    found = {p for k in keys for p, rx in ADDRESS_PART.items() if rx.match(k)}
    return len(found) == 2


def value_hits(s):
    out = []
    for m in EMAIL.finditer(s):
        local, dom = m.group(0).split("@", 1)[0], m.group(1)
        if PLACEHOLDER_DOMAIN.search(dom):
            continue
        if COMPANY_DOMAIN.search(dom) and ROLE_LOCAL.match(local):
            continue
        out.append("email")
        break
    for m in PHONE.finditer(s):
        if m.group(1) in TOLL_FREE or m.group(2) == "555":
            continue
        out.append("phone")
        break
    if SSN.search(s):
        out.append("ssn")
    if STREET.search(s):
        out.append("street_address")
    if TRACKING.search(s):
        out.append("tracking_number")
    if ORDER_REF.search(s):
        out.append("order_reference")
    if SECRET.search(s):
        out.append("secret")
    if IPV4.search(IP_AS_URL_HOST.sub("://HOST", s)):
        out.append("ipv4")
    if not URLISH.search(s):
        for m in CARD_CAND.finditer(s):
            d = re.sub(r"\D", "", m.group(0))
            if len(d) in (13, 14, 15, 16, 19) and d[0] in "3456" and luhn(d):
                out.append("card_number")
                break
    return out


def scan_table(rows):
    cols = sorted({k for r in rows for k in r})
    hits = collections.defaultdict(collections.Counter)  # col -> detector -> count
    for r in rows:
        for c in cols:
            v = r.get(c)
            if not populated(maybe_json(v)):
                continue
            for h in name_hits(c):
                hits[c][h] += 1
            for k, x in walk(v):
                if k == "__keys__":
                    if address_parts(x):
                        hits[c]["nested:address_parts"] += 1
                    continue
                if k is not None and k != c and populated(x):
                    for h in name_hits(k):
                        hits[c]["nested:" + h] += 1
                if isinstance(x, str):
                    for h in value_hits(x):
                        hits[c][h] += 1
        top = {c.lower() for c in cols if populated(maybe_json(r.get(c)))}
        if address_parts(top):
            for c in cols:
                if any(rx.match(c) for rx in ADDRESS_PART.values()) and populated(r.get(c)):
                    hits[c]["address_parts"] += 1
    # rows are person/order records when a top-level id column pointing at a person or order is populated
    record_cols = sorted(c for c, h in hits.items() if h.get("person_id") or h.get("order_id"))
    return cols, {c: dict(h) for c, h in hits.items()}, record_cols


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    src, out = argv[1], argv[2]
    if not os.path.isdir(src):
        print(f"pii_scan: no input dir {src}", file=sys.stderr)
        return 2
    os.makedirs(os.path.join(out, "data"), exist_ok=True)
    report = {}
    for fn in sorted(os.listdir(src)):
        if not fn.endswith(".json"):
            continue
        t = fn[:-5]
        with open(os.path.join(src, fn)) as fh:
            rows = json.load(fh)
        if not isinstance(rows, list) or not all(isinstance(r, dict) for r in rows):
            print(f"pii_scan: {fn} is not a JSON array of objects", file=sys.stderr)
            return 2
        cols, hits, record_cols = scan_table(rows)
        if record_cols:
            status, kept, dropped = "EXCLUDE", [], cols
        elif hits:
            status, dropped = "DROP_COLS", sorted(hits)
            kept = [{k: v for k, v in r.items() if k not in hits} for r in rows]
        else:
            status, kept, dropped = "KEEP", rows, []
        with open(os.path.join(out, "data", fn), "w") as fh:
            json.dump(kept, fh, separators=(",", ":"), sort_keys=True)
        report[t] = {"status": status, "rows_in": len(rows), "rows_out": len(kept), "record_cols": record_cols,
                     "dropped_cols": dropped if status == "DROP_COLS" else [], "hits": hits}
    with open(os.path.join(out, "SCAN.json"), "w") as fh:
        json.dump(report, fh, indent=1, sort_keys=True)
    n = collections.Counter(r["status"] for r in report.values())
    for t, r in report.items():
        if r["status"] != "KEEP":
            det = sorted({d for h in r["hits"].values() for d in h})
            what = f"record cols {r['record_cols']}" if r["status"] == "EXCLUDE" else f"dropped {r['dropped_cols']}"
            print(f"pii_scan: {r['status']:9} {t}: {what}; detectors {det}")
    print(f"pii_scan: {len(report)} tables: {n['KEEP']} KEEP, {n['DROP_COLS']} DROP_COLS, {n['EXCLUDE']} EXCLUDE "
          f"(metadata only: {out}/SCAN.json)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
