# Portfolio 3: Transactions and Concurrency

**Case study:** Josh Kay's Fisheries. **DBMS:** PostgreSQL 18.6.
**Demo product:** smoked jumbo catfish per piece (`S-JUM-PIECE`), reset to exactly **1 piece in stock**, so two customers can compete for the last one.

## Files
| File | Purpose |
|---|---|
| `00_reset_demo.sql` | Resets the demo product to 1 piece and checks cache vs ledger |
| `01_commit_rollback.sql` | Demo 1: COMMIT and ROLLBACK in one session |
| `README.md` | Demos 2-5 are run by hand in two windows (steps below) |
| `evidence/` | Demo screenshots and captured run output |

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
## Results summary
| Demo | Mechanism | Outcome |
|---|---|---|
| 1 | Transaction, COMMIT/ROLLBACK, CHECK constraint | The 2.5 kg order committed. The over-stock sale raised the expected CHECK error; rollback left no failed order or movement rows. |
| 2 | Stale reads and absolute write | Both sessions read 1 and committed a sale. The check showed cached stock 0 and ledger stock -1. |
| 3 | `SELECT ... FOR UPDATE` | Window B waited for A's lock, then read 0 after A committed; B rolled back rather than selling. |
| 4 | `REPEATABLE READ` | Window B waited, then received `could not serialize access due to concurrent update` after A committed; B rolled back. |
| 5 | `READ COMMITTED` and `REPEATABLE READ` | Under `READ COMMITTED`, A read 7920 then 8420. Under `REPEATABLE READ`, A read 7920 both times. |

## Technical reflection
Demo 2 showed why checking stock in one statement and later writing an application-calculated balance is unsafe. Both sessions read the same value of 1 before either sale committed. Each then recorded a sale and set the cached balance to 0, so both orders succeeded even though the ledger total became -1. The cached quantity and movement ledger can disagree when application writes are based on stale reads.

The CHECK constraint protects the product balance from becoming negative, as Demo 1 showed, but it does not undo earlier order and movement inserts on its own. Those statements must be in the same transaction, and the application must roll the transaction back when the stock update fails. A failed insert can still consume an identity value, so gaps in `order_id` are normal and do not mean an order row is missing.

In Demo 3, `SELECT ... FOR UPDATE` made the second session wait until the first finished; it then saw that stock was 0 and could reject the sale. This approach suits a checkout where waiting briefly for a stock decision is acceptable. Demo 4 used `REPEATABLE READ`: the second update waited but was then rejected with a serialization error, so an application using this approach needs to roll back and retry the whole transaction. That can suit workloads where detecting conflicts and retrying is preferable to queueing buyers for long periods.

Demo 5 showed the difference between the isolation levels. Under `READ COMMITTED`, each statement sees a fresh committed snapshot, so the second price read changed after Window B's update. Under `REPEATABLE READ`, both reads used the same transaction snapshot and the price stayed at its original value for Window A.

These were controlled demonstrations on one local PostgreSQL instance and a small dataset. They illustrate transaction behavior, but do not measure performance or simulate failures across separate database servers.
