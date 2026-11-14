#!/bin/bash
# Starts a 3-node MongoDB replica set on this computer (ports 27018-27020) and loads the fisheries data.
cd "$(dirname "$0")"; source ./common.sh
echo "== Starting 3 members =="
for p in "${PORTS[@]}"; do start_node $p; done
for p in "${PORTS[@]}"; do wait_for_node "$p" || exit 1; done
echo "== Initiating replica set '$RS_NAME' =="
"$MONGOSH" --quiet "$(direct 27018)" --eval 'printjson(rs.initiate({_id:"'$RS_NAME'", members:[
  {_id:0, host:"127.0.0.1:27018"}, {_id:1, host:"127.0.0.1:27019"}, {_id:2, host:"127.0.0.1:27020"}]}).ok)'
wait_for_primary || exit 1
echo "== Members =="; show_status
echo "== Loading the fisheries data into the replica set (Portfolio 4 seed) =="
"$MONGOSH" --quiet "$RS_URI" --file ../portfolio-4-nosql/01_seed.js
