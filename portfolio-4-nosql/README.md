# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** Josh Kay's Fisheries. **Model type:** document database (MongoDB).
**Tested on:** MongoDB 8.x with mongosh 2.x (replace with your own versions).
**Data:** synthetic and repeatable: 16 products, 500 customers, 10,000 orders, ~24,700 stock movements.

## Files
| File | Purpose |
|---|---|
| `01_seed.js` | Creates collections, schema validation, unique indexes and the synthetic data |
| `02_queries.js` | Eight example operations: reads, updates, aggregations, `$lookup`, validation |
| `03_indexes_explain.js` | `explain("executionStats")` before and after adding indexes |
| `evidence/` | Your own screenshots (create the folder) |

## How to run
```
mongosh "mongodb://localhost:27017/fisheries" --file portfolio-4-nosql/01_seed.js
mongosh "mongodb://localhost:27017/fisheries" --file portfolio-4-nosql/02_queries.js
mongosh "mongodb://localhost:27017/fisheries" --file portfolio-4-nosql/03_indexes_explain.js
```
If you use MongoDB Atlas instead of a local server, replace the connection string with your Atlas one. **Never commit a
connection string containing your password.**

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

## Evidence summary (replace with YOUR numbers from `03_indexes_explain.js`)
| Query | Before | After |
|---|---|---|
| E1 orders by customer phone | COLLSCAN, 10,000 docs examined | IXSCAN, 21 docs examined |
| E2 pending orders, last 30 days, sorted | COLLSCAN + in-memory SORT, 10,000 examined | IXSCAN, 19 examined, no sort stage |
| E3 pending orders containing a SKU | COLLSCAN, 10,000 examined | IXSCAN (multikey index), 38 examined |

The important number is **documents examined**, not milliseconds. At 10,000 documents the times are tiny and noisy;
the examined count shows the work the database avoided.

## Why a document database suits (and does not suit) this case study
<!-- TODO (Joshua): write this in your own words. Points to cover:
- Suits: orders are read and written as a unit; product attributes vary by form; easy to add new fields (e.g. a new product type)
- Does not suit: the stock count. Stock needs strict consistency under concurrent sales (Portfolio 3). MongoDB can do multi-document transactions, but only on a replica set, and PostgreSQL's constraints are simpler for this
- Duplication: the customer snapshot and product name copied into orders means a customer's later phone change does not update old orders. Good for history, bad if you need one current value
- Trade-off summary: relational for stock, payments and reporting; document for the order view and flexible catalogue. A real system could use both (polyglot persistence)
- Key-value option: stock counters or a cart could live in a key-value store such as Redis for speed, but I did not implement this -->

## Technical reflection
<!-- TODO (Joshua): challenges faced (installation, connection string, the first-run errors you saw) and what you learned. -->
