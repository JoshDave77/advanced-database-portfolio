#!/bin/bash
# Usage: ./run_plans.sh before|after   (run from this folder)
# Runs every query twice (warm cache) and saves the second EXPLAIN ANALYZE.
LABEL=$1; DB=${DB:-fisheries}
mkdir -p plans
for q in queries/q*.sql; do
  name=$(basename "$q" .sql)
  sql=$(cat "$q")
  psql -d "$DB" -q -c "EXPLAIN (ANALYZE, BUFFERS) $sql" > /dev/null
  psql -d "$DB" -c "EXPLAIN (ANALYZE, BUFFERS) $sql" > "plans/${LABEL}_${name}.txt"
  echo "$name $LABEL: $(grep 'Execution Time' plans/${LABEL}_${name}.txt)"
done
