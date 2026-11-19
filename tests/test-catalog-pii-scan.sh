#!/usr/bin/env bash
# seed/catalog/pii_scan.py: judged by DATA, not table names. Synthetic fixtures only (fake, reserved values).
. "$(dirname "$0")/lib.sh"
D="$(mktemp -d "${TMPDIR:-/tmp}/tfh-pii.XXXXXX")"; mkdir -p "$D/in"
# innocuous name, but rows are customer records (person id populated) -> EXCLUDE
echo '[{"id":1,"customer_id":42,"discount":"10.00"}]' > "$D/in/rebill_things.json"
# innocuous name, order id hidden in a JSON-string column -> that column dropped
echo '[{"id":1,"title":"Promo","meta":"{\"sticky_order_id\":\"123456\"}"}]' > "$D/in/promo_meta.json"
# catalog table whose NAME says order: only catalog fields -> KEEP
echo '[{"id":1,"name":"Bump","sku":"SKU-00412","price":"19.99","sort_order":2,"order_bump_configuration_id":3}]' > "$D/in/order_bump_configurations.json"
# free-text customer data in values -> column dropped, rest kept
echo '[{"id":1,"sku":"TF-100","answer":"Write to jane.q.customer@gmail.com or call 312-736-0199"}]' > "$D/in/faqs.json"
CARD="4111 $(printf '%s ' 1111 1111)1111"   # well-known test PAN, assembled so the secret scanner stays meaningful
echo '[{"id":1,"note":"card '"$CARD"'"},{"id":2,"note":"ok","ship":{"city":"Austin","zip":"78701"}}]' > "$D/in/notes.json"
echo '[{"id":1,"body":"Order #1234567 shipped 1Z999AA10123456784","total":"9.99"}]' > "$D/in/msgs.json"
# company role mailbox, toll-free number, placeholder domain, URL with IP host: not customer data -> KEEP
echo '[{"id":1,"text":"support@trulyfreehome.com 1-800-555-0100 a@example.com","url":"http://10.0.0.1/x.png"}]' > "$D/in/copy.json"
out="$(python3 -I "$T_ROOT/seed/catalog/pii_scan.py" "$D/in" "$D/out")"; rc=$?
st() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["status"])' "$D/out/SCAN.json" "$1"; }
cols() { python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(",".join(sorted({k for x in r for k in x})))' "$D/out/data/$1.json"; }
expect_true "scan exits 0" [ $rc -eq 0 ]
expect_true "person-id rows excluded (name-agnostic)" [ "$(st rebill_things)" = EXCLUDE ]
expect_true "excluded table written empty" [ "$(cat "$D/out/data/rebill_things.json")" = "[]" ]
expect_true "nested order id -> column dropped" [ "$(cols promo_meta)" = "id,title" ]
expect_true "order_bump_configurations kept (sku/price/sort_order not flagged)" [ "$(st order_bump_configurations)" = KEEP ]
expect_true "email/phone in text -> column dropped" [ "$(cols faqs)" = "id,sku" ]
expect_true "card number + nested city/zip -> columns dropped" [ "$(cols notes)" = "id" ]
expect_true "order ref + tracking number -> column dropped" [ "$(cols msgs)" = "id,total" ]
expect_true "role mailbox / toll-free / placeholder / IP-host URL kept" [ "$(st copy)" = KEEP ]
expect_false "no values printed" grep -qE 'gmail|736-0199|4111|Austin|1Z999' <<<"$out$(cat "$D/out/SCAN.json")"
rm -rf "$D"
done_tests
