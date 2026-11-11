# Portfolio 3: Transactions and Concurrency

**Case study:** Josh Kay's Fisheries. **DBMS:** PostgreSQL (tested on 16; replace with your own version).
**Demo product:** smoked jumbo catfish per piece (`S-JUM-PIECE`), reset to exactly **1 piece in stock**, so two customers can compete for the last one.

## Files
| File | Purpose |
|---|---|
| `00_reset_demo.sql` | Resets the demo product to 1 piece and checks cache vs ledger |
| `01_commit_rollback.sql` | Demo 1: COMMIT and ROLLBACK in one session |
| `README.md` | Demos 2-5 are run by hand in two windows (steps below) |
| `evidence/` | Put your own screenshots here (create the folder) |

## Setup for two-window demos
Open **two terminals** in VS Code (split the terminal). Start psql **from the repo root** in both:
```
psql -U postgres -d fisheries
```
Call them **Window A** and **Window B**. In Window A run `\i portfolio-3-transactions-concurrency/00_reset_demo.sql`
and confirm `cached_stock = 1` and `ledger_stock = 1`. Re-run this reset before every demo below.

---
## Demo 1: COMMIT and ROLLBACK (one window)
```
\i portfolio-3-transactions-concurrency/01_commit_rollback.sql
```
Expected: section A commits an order and stock drops by 2.5 kg. Section B inserts an order, then the stock update
violates `CHECK (quantity_on_hand >= 0)`, PostgreSQL refuses every further command until `ROLLBACK`, and afterwards
**no trace** of the failed order remains in `orders` or `stock_movement`.
**Screenshot:** the section B error and the three "should be" checks.

## Demo 2: The concurrency problem (lost update / overselling)
The unsafe pattern: the application **reads** stock, decides, then **writes back a value it calculated itself**.
Run the steps in this exact order. The sale block is the same in A and B:
```sql
INSERT INTO orders (customer_id, taken_by, status) VALUES (1, 2, 'confirmed') RETURNING order_id \gset
INSERT INTO order_item (order_id, product_id, quantity, unit_price)
  SELECT :order_id, product_id, 1, unit_price FROM product WHERE sku = 'S-JUM-PIECE';
INSERT INTO stock_movement (product_id, order_id, movement_type, quantity)
  SELECT product_id, :order_id, 'sale_out', -1 FROM product WHERE sku = 'S-JUM-PIECE';
UPDATE product SET quantity_on_hand = 0 WHERE sku = 'S-JUM-PIECE';
```
| Step | Window | Run |
|---|---|---|
| 1 | A | `BEGIN;` then `SELECT quantity_on_hand FROM product WHERE sku='S-JUM-PIECE';` (sees 1) |
| 2 | B | `BEGIN;` then the same SELECT (also sees **1**, A has not committed) |
| 3 | A | the sale block, then `COMMIT;` |
| 4 | B | the sale block, then `COMMIT;` (both succeed) |
| 5 | either | check query below |

```sql
SELECT p.quantity_on_hand AS cached_stock,
       (SELECT sum(quantity) FROM stock_movement sm WHERE sm.product_id = p.product_id) AS ledger_stock
FROM product p WHERE sku = 'S-JUM-PIECE';
```
Expected: `cached_stock = 0` but `ledger_stock = -1`. **Two customers were sold the last piece** and the cached
balance no longer matches the ledger. **Screenshot** both windows and the check query.

## Demo 3: Fix 1, pessimistic locking with `SELECT ... FOR UPDATE`
Reset, then:
| Step | Window | Run |
|---|---|---|
| 1 | A | `BEGIN;` then `SELECT quantity_on_hand FROM product WHERE sku='S-JUM-PIECE' FOR UPDATE;` (sees 1) |
| 2 | B | `BEGIN;` then the same query. **It hangs, with no result.** This is the lock. |
| 3 | A | `UPDATE product SET quantity_on_hand = quantity_on_hand - 1 WHERE sku='S-JUM-PIECE'; COMMIT;` |
| 4 | B | the query now returns, seeing **0**. Run `ROLLBACK;` (the application rejects the order) |

Expected: B waits, then sees 0 and refuses the sale. No oversell.
**Screenshot:** B hanging at step 2 and B's result at step 4.

## Demo 4: Fix 2, `REPEATABLE READ` isolation
Reset, then:
| Step | Window | Run |
|---|---|---|
| 1 | A | `BEGIN ISOLATION LEVEL REPEATABLE READ;` then `SELECT quantity_on_hand FROM product WHERE sku='S-JUM-PIECE';` |
| 2 | B | same `BEGIN ISOLATION LEVEL REPEATABLE READ;` and SELECT (sees 1) |
| 3 | A | `UPDATE product SET quantity_on_hand = quantity_on_hand - 1 WHERE sku='S-JUM-PIECE';` |
| 4 | B | the same UPDATE. **It hangs**, waiting for A. |
| 5 | A | `COMMIT;` |
| 6 | B | `ERROR: could not serialize access due to concurrent update`, then run `ROLLBACK;` |

Expected: B is aborted by the database instead of overwriting A. The application must **retry** the transaction.
**Screenshot:** B's error message.

## Demo 5: Isolation levels (price changes during checkout)
Reset, then for each isolation level (`READ COMMITTED` is the default, then `REPEATABLE READ`):
| Step | Window | Run |
|---|---|---|
| 1 | A | `BEGIN ISOLATION LEVEL READ COMMITTED;` then `SELECT unit_price FROM product WHERE sku='S-JUM-PIECE';` (7920.00) |
| 2 | B | `UPDATE product SET unit_price = unit_price + 500 WHERE sku='S-JUM-PIECE';` |
| 3 | A | run the SELECT again, then `COMMIT;` |

Expected: `READ COMMITTED` shows **8420.00** on the second read (a non-repeatable read). Reset and repeat with
`REPEATABLE READ`: the second read stays **7920.00**.

---
## Results summary (my notes from testing, replace with what YOU observed)
| Demo | Mechanism | Outcome |
|---|---|---|
| 1 | Transaction, COMMIT/ROLLBACK, CHECK constraint | Atomic: failed order leaves no rows |
| 2 | None (stale read, absolute write) | Last piece sold twice, cache != ledger |
| 3 | `FOR UPDATE` | Second buyer waits, then sees 0 stock |
| 4 | `REPEATABLE READ` | Second buyer aborted, must retry |
| 5 | READ COMMITTED vs REPEATABLE READ | Non-repeatable read demonstrated and prevented |

## Technical reflection
<!-- TODO (Joshua): write in your own words. Points to cover:
- Why Demo 2 breaks: the decision is made on a stale read, and the write overwrites A's change
- Locking (Demo 3) queues buyers but holds the row; isolation (Demo 4) fails fast and needs retry logic. When would each suit a fish business?
- The CHECK constraint is a safety net, but alone it only rejects the second buyer AFTER order rows were inserted, so the transaction must roll back (Demo 1B)
- The cached balance and the ledger drifting apart in Demo 2 is the cost of the denormalisation decision in Portfolio 1
- Identity values (order_id) are not rolled back, so a failed order leaves a gap in the sequence -->
