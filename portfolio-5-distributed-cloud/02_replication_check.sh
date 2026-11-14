#!/bin/bash
# Evidence of replication: the same data exists on every member, and a majority write is acknowledged.
cd "$(dirname "$0")"; source ./common.sh
echo "== Members =="; show_status
echo "== Majority-acknowledged write (w:majority) =="
"$MONGOSH" --quiet "$RS_URI" --eval '
  const r = db.replication_log.insertOne({note: "write acknowledged by a majority", at: new Date()},
                                         {writeConcern: {w: "majority", wtimeout: 5000}});
  print("acknowledged: " + r.acknowledged);'
sleep 2
echo "== Same data on every member (each queried directly) =="
for p in "${PORTS[@]}"; do
  "$MONGOSH" --quiet "$(direct "$p")" --eval '
    const h = db.hello(); const d = db.getSiblingDB("fisheries");
    print("port '$p'  " + (h.isWritablePrimary ? "PRIMARY  " : "SECONDARY") +
          "  orders=" + d.orders.countDocuments() + "  products=" + d.products.countDocuments() +
          "  replication_log=" + d.replication_log.countDocuments());'
done
