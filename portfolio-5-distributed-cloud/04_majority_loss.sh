#!/bin/bash
# CAP evidence: with only ONE of three members left, there is no majority. Writes are refused, reads still work.
cd "$(dirname "$0")"; source ./common.sh
KEEP=$(find_primary); echo "== Keeping only port $KEEP; stopping the other two =="
for p in "${PORTS[@]}"; do [ "$p" != "$KEEP" ] && stop_node $p; done
echo "== Waiting for the lone member to step down (it can no longer see a majority) =="
until [ "$("$MONGOSH" --quiet "$(direct "$KEEP")" --eval 'print(db.hello().isWritablePrimary)' 2>/dev/null)" = "false" ]; do sleep 1; done
echo; echo "== Attempt a WRITE on the lone member =="
"$MONGOSH" --quiet "mongodb://127.0.0.1:$KEEP/?directConnection=true" --eval '
  try { db.getSiblingDB("fisheries").failover_log.insertOne({step:"no majority"}); print("UNEXPECTED: write accepted"); }
  catch (e) { print("REFUSED: " + e.message); }'
echo; echo "== Attempt a READ on the lone member (readPreference=secondaryPreferred) =="
"$MONGOSH" --quiet "$(direct "$KEEP")" --eval 'print("read OK, orders=" + db.getSiblingDB("fisheries").orders.countDocuments())'
echo; echo "== Restoring the other two members =="
for p in "${PORTS[@]}"; do [ "$p" != "$KEEP" ] && start_node $p; done
for p in "${PORTS[@]}"; do wait_for_node $p; done
wait_for_primary; sleep 3; show_status
