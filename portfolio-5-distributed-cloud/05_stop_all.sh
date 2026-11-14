#!/bin/bash
# Stops all three members. Add the argument  clean  to also delete the data and logs.
cd "$(dirname "$0")"; source ./common.sh
for p in "${PORTS[@]}"; do stop_node $p; done
[ "$1" = "clean" ] && rm -rf data logs && echo "data and logs removed"
echo "stopped"
