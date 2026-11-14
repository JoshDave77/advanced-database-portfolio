# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** Josh Kay's Fisheries. **Model type:** document database (MongoDB).
**Tested on:** MongoDB Server 9.0.8 and mongosh 2.14.2.
**Data:** repeatable synthetic data: 16 products, 500 customers, 10,000 orders, 24,669 stock movements.

## Files
| File | Purpose |
|---|---|
| `01_seed.js` | Creates collections, schema validation, unique indexes and the synthetic data |
| `02_queries.js` | Eight example operations: reads, updates, aggregations, `$lookup`, validation |
| `03_indexes_explain.js` | `explain("executionStats")` before and after adding indexes |
| `evidence/` | Captures of the seed, query examples and index comparison |

## How to run
From the repository root in PowerShell, set `$mongosh` to the location of your `mongosh.exe`. This is the path used
for this run; change it if you extracted mongosh elsewhere:
```powershell
$mongosh = "$env:USERPROFILE\Documents\mongosh-2.14.2-win32-x64\mongosh-2.14.2-win32-x64\bin\mongosh.exe"
& $mongosh "mongodb://localhost:27017/fisheries" --file ".\portfolio-4-nosql\01_seed.js"
& $mongosh "mongodb://localhost:27017/fisheries" --file ".\portfolio-4-nosql\02_queries.js"
& $mongosh "mongodb://localhost:27017/fisheries" --file ".\portfolio-4-nosql\03_indexes_explain.js"
```
The seed script drops and recreates the four project collections, so only run it when it is safe to reset this data.
The query script updates sample orders and appends a payment. The explain script removes and recreates its three
performance indexes, making the comparison repeatable. This local MongoDB server has access control disabled; keep it
local and do not expose it to a network. If using Atlas, replace the connection string and never commit credentials.

## The model: what I embedded and what I referenced
| Relational (Portfolio 1) | MongoDB | Decision and reason |
|---|---|---|
| `orders` + `order_item` + `payment` + `delivery` | **one `orders` document** with `items[]`, `payments[]`, `delivery{}` | Always read together; bounded size (a few items); one read replaces a 4-table join |
| `customer` details on an order | `customer{}` **snapshot** inside the order, plus `customerId` | Order history is shown without a second lookup; the snapshot also records who the customer was at order time |
| `product` | separate `products` collection | Referenced by SKU; changes independently; has `attributes{}` that differ by form |
| `stock_movement` | separate `stock_movements` collection | Append-only and grows without limit, so it must not be embedded (16 MB document limit) |
| `delivery_zone` | zone name stored as a field | Only four values; fee is stored on the order as a snapshot |

**Where the document model fits this business well:** fresh products carry `source/handling`, smoked products carry
`smokingMethod/woodType`. In SQL that is nullable columns or an extra table; in MongoDB each document holds only the
attributes it needs. Customers without an email simply have no `email` field.

## Evidence summary
The baseline retained MongoDB's `_id_` index and the unique `orderNo_1` index, but did not yet have indexes for these
query filters. The after run added indexes on customer phone, order status/date, and embedded item SKU/status.

| Query | Before: plan; examined / returned; time | After: plan; examined / returned; time |
|---|---|---|
| E1 orders by customer phone | COLLSCAN; 10,000 / 21; 10 ms | FETCH>IXSCAN; 21 / 21; 20 ms |
| E2 pending orders, last 30 days, sorted | SORT>COLLSCAN; 10,000 / 19; 12 ms | FETCH>IXSCAN; 19 / 19; 26 ms |
| E3 pending orders containing a SKU | COLLSCAN; 10,000 / 38; 17 ms | FETCH>IXSCAN; 38 / 38; 24 ms |

The indexes reduced documents examined by about 99.6–99.8% for these queries, and E2 no longer needed a sort stage.
Elapsed times were higher after indexing in this single run. At this dataset size, millisecond timings are small and
noisy, so they do not demonstrate a speedup here; the explain plans and documents-examined counts are the clearer
evidence that the indexes narrowed the work. The `items.sku` index is multikey because it indexes values in the
embedded `items` array.

Evidence files are in `evidence/`: `p4-seed-run.png`, `p4-queries-q1-q4.png`, `p4-queries-q1-q4 2.png`,
`p4-queries-q1-q4 3.png`, `p4-queries-q5-q8 4.png`, `p4-queries-q5-q8 5.png`, and `p4-indexes-explain.png`.

## Why a document database suits (and does not suit) this case study
I embedded order items, payments, delivery details and a customer snapshot because they are commonly read with the order.
This keeps the order view convenient, and the snapshot preserves the customer's details as they were when the order was
placed. The trade-off is duplicated data: a later customer phone change will not update old order snapshots. Item names
are also copied into order lines so the order retains what was sold if the catalogue changes.

I kept products separate because the catalogue is managed independently and fresh and smoked products have different
attributes. I also kept stock movements in their own collection because that history grows over time. The cached
`stockOnHand` value on each product must remain consistent with those movements. Concurrent sales therefore need
careful consistency controls to prevent overselling. MongoDB supports multi-document transactions on replica sets and
sharded clusters, but the scripts here do not implement a transactional stock workflow. For this case study, I would
prefer a relational database for tightly constrained inventory and accounting workflows, while MongoDB is a good fit
for the flexible catalogue and order-oriented read model. A real system could combine them; a key-value store such as
Redis could also be considered for carts or counters, but I did not implement one.

## Technical reflection
I ran MongoDB locally and verified the connection with a ping before loading the data. The server was MongoDB 9.0.8,
and mongosh was 2.14.2. Because mongosh was extracted under Documents and was not on my PATH, I ran it using its full
path from PowerShell. I also initially entered a PowerShell command at the mongosh prompt; mongosh interpreted it as
JavaScript and returned a syntax error. Exiting to PowerShell and running the scripts with `--file` resolved that
confusion.

The seed completed with 16 products, 500 customers, 10,000 orders, and 24,669 stock movements. All eight query
examples ran, including the expected schema-validation rejections. The index comparison taught me not to judge an
index only by elapsed milliseconds: in this run, times rose slightly even though the query plans used indexes and
documents examined fell sharply. A larger dataset and repeated controlled measurements would be needed to compare
latency reliably.
