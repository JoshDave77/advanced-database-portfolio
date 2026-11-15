# Portfolio 2: Query Processing and Optimisation

**Case study:** Josh Kay's Fisheries. **DBMS:** I ran this portfolio on PostgreSQL 18.6.
**Data:** I generated synthetic data with `seed.sql` (random choices use `setseed`; timestamps are relative to run time): 2,000 customers, 16 products, 50,000 orders, 125,000 order lines, about 123,000 stock movements, and about 48,000 payments and deliveries.

## Files
| File | Purpose |
|---|---|
| `seed.sql` | I use this to generate my synthetic dataset (run after Portfolio 1 `schema.sql`) |
| `queries/q1..q5*.sql` | I wrote these five business queries |
| `indexes.sql` | I added these indexes after reviewing the BEFORE plans |
| `run_plans.sh` | I use this to run each query twice (warm cache) and save my `EXPLAIN (ANALYZE, BUFFERS)` output |
| `plans/before_*.txt`, `plans/after_*.txt` | I saved my execution plans here |
| `evidence/p2-results-summary.sql` | I use this to display my recorded before/after timings and plan changes |
| `evidence/p2-results-summary.png` | I captured this screenshot of the results summary |

## How to reproduce my run
I ran these commands from this folder in Git Bash. On Windows, set the connection variables for your local PostgreSQL role and server:

```bash
export PGUSER=postgres PGHOST=localhost PGDATABASE=fisheries
# If needed, create the database first: createdb -U postgres -h localhost fisheries
# schema.sql drops and recreates the project tables; seed.sql adds the test data.
psql -d fisheries -f ../portfolio-1-database-design/schema.sql
psql -d fisheries -f seed.sql
bash run_plans.sh before
psql -d fisheries -f indexes.sql
bash run_plans.sh after
psql -P pager=off -d fisheries -f evidence/p2-results-summary.sql
```
I ran `seed.sql` once after creating the schema; it inserts data and is not an incremental reload. The summary query displays the timings I recorded for this run; it does not rerun the benchmarks. Update its values if you run the benchmarks again and want the summary to reflect your new measurements.

## Queries
1. **Q1** Order history for one customer (customer service lookup)
2. **Q2** Monthly revenue, last 90 days
3. **Q3** Delivered revenue by delivery zone, last 30 days
4. **Q4** Orders with pending payment plus customer phone (follow-up list)
5. **Q5** Stock movement history for one product, last 30 days

## Results I measured (execution time, ms, one warm run on my machine)
| Query | Before | After | Change | Plan change |
|---|---|---|---|---|
| Q1 customer history | 5.466 | 0.791 | ~6.91x faster | `orders` Seq Scan to Bitmap Index Scan on `idx_orders_customer` |
| Q2 monthly revenue | 100.418 | 89.325 | ~1.12x faster | `orders` Seq Scan to date-index Bitmap Index Scan; `order_item` remains Seq Scan |
| Q3 revenue by zone | 78.435 | 57.591 | ~1.36x faster | `orders` Seq Scan to date-index Bitmap Index Scan; `order_item` remains Seq Scan |
| Q4 unpaid orders | 30.423 | 21.790 | ~1.40x faster | `payment` Seq Scan to Index Scan on partial index `idx_payment_pending` |
| Q5 stock history | 23.086 | 3.533 | ~6.53x faster | `stock_movement` Seq Scan to Bitmap Index Scan on `idx_stock_movement_prod_dt` |

## My performance analysis
I saw the largest improvements in Q1 and Q5 because their filters select a relatively small part of a large table. Q1 returned 24 orders for one customer: its plan changed from scanning all 50,000 orders to using `idx_orders_customer`. Q5 returned about 1,008 matching stock movements from roughly 123,000 rows. I created a composite index beginning with `product_id` for the equality condition and followed by `moved_at` for the date range, allowing PostgreSQL to use both conditions in the index scan.

I saw smaller improvements in Q2 and Q3 because their plans still read all 125,000 `order_item` rows to calculate the aggregates. The date index narrowed the matching orders, but it did not remove the large line-item scan. Q4 improved after PostgreSQL used my partial index for pending payments, which contains only rows with `status = 'pending'` rather than entries for every payment.

I considered the storage and maintenance costs of indexes: the database must update them when rows are inserted, updated or deleted. I would use indexes where they help frequent, selective queries, while weighing that cost for tables such as `orders` and `stock_movement` that also receive writes.

I measured these timings in one warm run on a small synthetic dataset, so they can vary with cache state, hardware and PostgreSQL version. I used the execution plans and rows scanned to explain the changes, but I would not treat these measurements as guaranteed performance for a production-sized database.

## References
- PostgreSQL Global Development Group. *PostgreSQL 18 Documentation: Using EXPLAIN*. https://www.postgresql.org/docs/18/using-explain.html
- PostgreSQL Global Development Group. *PostgreSQL 18 Documentation: Indexes*. https://www.postgresql.org/docs/18/indexes.html
