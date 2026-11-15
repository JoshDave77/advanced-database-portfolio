# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** I modelled Josh Kay's Fisheries with a document database (MongoDB).
**Tested on:** I ran my tests with MongoDB Server 9.0.8 and mongosh 2.14.2.
**Data:** I generated repeatable synthetic data: 16 products, 500 customers, 10,000 orders and 24,669 stock movements.

## Files
| File | Purpose |
|---|---|
| `01_seed.js` | I use this to create my collections, schema validation, unique indexes and synthetic data |
| `02_queries.js` | I use this for the eight read, update, aggregation, `$lookup` and validation operations |
| `03_indexes_explain.js` | I use this to capture `explain("executionStats")` before and after adding indexes |
| `evidence/` | My captures of the seed, query examples and index comparison |

## How I ran the scripts
I ran these commands from the repository root in PowerShell. I set `$mongosh` to the location of my `mongosh.exe`;
change the path if you extracted mongosh elsewhere:
```powershell
$mongosh = "$env:USERPROFILE\Documents\mongosh-2.14.2-win32-x64\mongosh-2.14.2-win32-x64\bin\mongosh.exe"
& $mongosh "mongodb://localhost:27017/fisheries" --file ".\portfolio-4-nosql\01_seed.js"
& $mongosh "mongodb://localhost:27017/fisheries" --file ".\portfolio-4-nosql\02_queries.js"
& $mongosh "mongodb://localhost:27017/fisheries" --file ".\portfolio-4-nosql\03_indexes_explain.js"
```
I noted that the seed script drops and recreates the four project collections, so I only run it when it is safe to reset
this data. The query script updates sample orders and appends a payment. The explain script removes and recreates its
three performance indexes, making the comparison repeatable. I ran this local MongoDB server with access control
disabled, so I keep it local and do not expose it to a network. If I use Atlas, I replace the connection string and
never commit credentials.

## My model: what I embedded and what I referenced
| Relational (Portfolio 1) | MongoDB | My decision and reason |
|---|---|---|
| `orders` + `order_item` + `payment` + `delivery` | **one `orders` document** with `items[]`, `payments[]`, `delivery{}` | I embedded these fields because I commonly read them together and each order has a bounded number of items; this replaces a 4-table join for the order view |
| `customer` details on an order | `customer{}` **snapshot** inside the order, plus `customerId` | I stored a snapshot so I can show order history without a second lookup and preserve the customer's details as they were when the order was placed |
| `product` | separate `products` collection | I kept products separate because I reference them by SKU, manage them independently, and their `attributes{}` differ by form |
| `stock_movement` | separate `stock_movements` collection | I kept stock movements separate because the append-only history grows without limit and should not be embedded (16 MB document limit) |
| `delivery_zone` | zone name stored as a field | I stored the zone name on the order because there are only four values, and kept the fee there as an order-time snapshot |

**Where I found the document model useful:** I stored `source/handling` for fresh products and `smokingMethod/woodType`
for smoked products. In SQL, I would use nullable columns or an extra table; in MongoDB, I can store only the
attributes each document needs. I left out the `email` field for customers who do not have one.

## Evidence summary
In my baseline run on the `orders` collection, MongoDB retained its `_id_` index and the unique `orderNo_1` index, but
I had not yet added indexes for these query filters. In the after run, I added indexes on customer phone, order status/date,
and embedded item SKU/status.

| Query | Before: plan; examined / returned; time | After: plan; examined / returned; time |
|---|---|---|
| E1 orders by customer phone | COLLSCAN; 10,000 / 21; 10 ms | FETCH>IXSCAN; 21 / 21; 20 ms |
| E2 pending orders, last 30 days, sorted | SORT>COLLSCAN; 10,000 / 19; 12 ms | FETCH>IXSCAN; 19 / 19; 26 ms |
| E3 pending orders containing a SKU | COLLSCAN; 10,000 / 38; 17 ms | FETCH>IXSCAN; 38 / 38; 24 ms |

I found that the indexes reduced documents examined by about 99.6–99.8% for these queries, and E2 no longer needed a
sort stage. Elapsed times were higher after indexing in this single run. At this dataset size, the millisecond timings
are small; they did not show a speedup in my run. I used the explain plans and documents-examined counts as clearer
evidence that the indexes narrowed the work. The `items.sku` index is multikey because it indexes values in my
embedded `items` array.

I saved my evidence files in `evidence/`: `p4-seed-run.png`, `p4-queries-q1-q4.png`, `p4-queries-q1-q4 2.png`,
`p4-queries-q1-q4 3.png`, `p4-queries-q5-q8 4.png`, `p4-queries-q5-q8 5.png`, and `p4-indexes-explain.png`.

## Why a document database suits (and does not suit) this case study
I embedded order items, payments, delivery details and a customer snapshot because I commonly read them with the order.
I did this to keep the order view convenient, and to preserve the customer's details as they were when the order was
placed. I accepted the trade-off of duplicated data: a later customer phone change will not update old order snapshots.
I also copied item names into order lines so each order retains what was sold if the catalogue changes.

I kept products separate because I manage the catalogue independently and fresh and smoked products have different
attributes. I also kept stock movements in their own collection because that history grows over time. I would need to
keep each product's cached `stockOnHand` value consistent with its movements, so concurrent sales need careful controls
to prevent overselling. MongoDB supports multi-document transactions on replica sets and sharded clusters, but I did not
implement a transactional stock workflow in these scripts. For this case study, I would prefer a relational database
for tightly constrained inventory and accounting workflows, while using MongoDB for the flexible catalogue and
order-oriented read model. I could combine the two in a real system; I could also consider a key-value store such as
Redis for carts or counters, but I did not implement one.

## Technical reflection
I ran MongoDB locally and verified the connection with a ping before loading the data. The server was MongoDB 9.0.8,
and mongosh was 2.14.2. Because mongosh was extracted under Documents and was not on my PATH, I ran it using its full
path from PowerShell. I also initially entered a PowerShell command at the mongosh prompt; mongosh interpreted it as
JavaScript and returned a syntax error. Exiting to PowerShell and running the scripts with `--file` resolved that
confusion.

My seed run created 16 products, 500 customers, 10,000 orders and 24,669 stock movements. I ran all eight query
examples, including the expected schema-validation rejections. The index comparison taught me not to judge an
index only by elapsed milliseconds: in my run, times rose even though I observed the query plans use indexes and the
documents examined fell sharply. I would need a larger dataset and repeated controlled measurements to compare latency reliably.
