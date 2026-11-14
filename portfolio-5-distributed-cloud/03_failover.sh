#!/bin/bash
# Availability evidence: stop the PRIMARY, watch an election, keep writing, then bring the old primary back.
cd "$(dirname "$0")"; source ./common.sh
OLD=$(find_primary); echo "== Current primary: port $OLD =="; show_status
"$MONGOSH" --quiet "$RS_URI" --eval 'db.failover_log.insertOne({step:"before outage", at:new Date()},{writeConcern:{w:"majority"}}); print("marker written before outage")'

echo; echo "== Stopping the primary (port $OLD) =="
stop_node $OLD; SECONDS=0
until [ -n "$(find_primary)" ] && [ "$(find_primary)" != "$OLD" ]; do sleep 1; done
NEW=$(find_primary)
echo "== New primary elected: port $NEW after about $SECONDS seconds =="; show_status

echo; echo "== Writing and reading while one node is down (2 of 3 members = still a majority) =="
"$MONGOSH" --quiet "$RS_URI" --eval '
  db.failover_log.insertOne({step:"during outage", at:new Date()},{writeConcern:{w:"majority", wtimeout:10000}});
  print("write with w:majority succeeded during the outage");
  print("orders still readable: " + db.orders.countDocuments());'

echo; echo "== Restarting the old primary (port $OLD) =="
start_node $OLD; wait_for_node $OLD
until [ "$("$MONGOSH" --quiet "$(direct "$OLD")" --eval 'print(db.hello().secondary)' 2>/dev/null)" = "true" ]; do sleep 1; done
sleep 3
echo "== Old primary rejoined as a secondary and caught up =="; show_status
for p in "${PORTS[@]}"; do
  "$MONGOSH" --quiet "$(direct "$p")" --eval 'print("port '$p'  failover_log entries=" + db.getSiblingDB("fisheries").failover_log.countDocuments())'
done
