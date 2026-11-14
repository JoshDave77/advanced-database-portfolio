#!/bin/bash
# Shared settings/helpers for the Portfolio 5 demos (run the scripts from Git Bash).
# If mongod/mongosh are not on your PATH, set them in Git Bash first, for example:
#   export MONGOD="$(cygpath -u 'C:\Program Files\MongoDB\Server\9.0\bin\mongod.exe')"
#   export MONGOSH="$(cygpath -u "$USERPROFILE\Documents\mongosh-2.14.2-win32-x64\mongosh-2.14.2-win32-x64\bin\mongosh.exe")"
MONGOD=${MONGOD:-mongod}
MONGOSH=${MONGOSH:-mongosh}
PORTS=(27018 27019 27020)
RS_NAME=fisheriesRS
RS_URI="mongodb://127.0.0.1:27018,127.0.0.1:27019,127.0.0.1:27020/fisheries?replicaSet=$RS_NAME"

start_node() {            # start one replica-set member in the background
  local p=$1; mkdir -p "data/$p" logs
  nohup "$MONGOD" --replSet "$RS_NAME" --port "$p" --dbpath "data/$p" \
        --bind_ip 127.0.0.1 --oplogSize 128 > "logs/$p.log" 2>&1 &
}
direct() {                # direct() PORT  -> connection string for ONE member (reads allowed on secondaries)
  echo "mongodb://127.0.0.1:$1/?directConnection=true&readPreference=secondaryPreferred&serverSelectionTimeoutMS=2000"
}
wait_for_node() {         # wait until a member answers
  local p=$1; local t=0
  until "$MONGOSH" --quiet "$(direct "$p")" --eval 'db.hello().ok' >/dev/null 2>&1; do
    if [ "$t" -ge 60 ]; then
      echo "Timed out waiting for MongoDB member on port $p; check logs/$p.log." >&2
      return 1
    fi
    sleep 1
    t=$((t+1))
  done
}
stop_node() {             # simulate a node failure by shutting the member down
  "$MONGOSH" --quiet "$(direct "$1")" --eval 'db.getSiblingDB("admin").shutdownServer({force:true})' >/dev/null 2>&1
}
find_primary() {          # print the port of the current primary (empty if none)
  for p in "${PORTS[@]}"; do
    r=$("$MONGOSH" --quiet "$(direct "$p")" --eval 'print(db.hello().isWritablePrimary)' 2>/dev/null)
    if [ "$r" = "true" ]; then echo "$p"; return; fi
  done
}
wait_for_primary() {
  local t=0
  while [ "$t" -lt 60 ]; do
    [ -n "$(find_primary)" ] && return 0
    sleep 1
    t=$((t+1))
  done
  echo "Timed out waiting for a replica-set primary; check the member logs." >&2
  return 1
}
show_status() { "$MONGOSH" --quiet "$RS_URI" --file status.js; }
