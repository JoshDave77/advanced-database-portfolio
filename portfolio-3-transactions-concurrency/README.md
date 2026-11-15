# Portfolio 3: Transactions and Concurrency

**Case study:** Josh Kay's Fisheries. **DBMS:** PostgreSQL 18.6.
**Demo product:** I used smoked jumbo catfish per piece (`S-JUM-PIECE`), reset to exactly **1 piece in stock**, so two customers could compete for the last one.

## Files
| File | Purpose |
|---|---|
| `00_reset_demo.sql` | Resets my demo product to 1 piece and checks the cached balance against the ledger |
| `01_commit_rollback.sql` | Runs my Demo 1 COMMIT and ROLLBACK checks in one session |
| `README.md` | I ran Demos 2-5 by hand in two windows, following the steps below |
| `evidence/` | My demo screenshots and captured run output |

## How I set up the two-window demos
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
I saw section A commit an order and stock drop by 2.5 kg. In section B, I inserted an order, then the stock update
violated `CHECK (quantity_on_hand >= 0)`. PostgreSQL rejected further commands until I ran `ROLLBACK`; afterwards,
**no trace** of the failed order remained in `orders` or `stock_movement`.
**Evidence:** I captured the section B error and the three "should be" checks.

## Demo 2: The concurrency problem (lost update / overselling)
I demonstrated the unsafe pattern where an application **reads** stock, makes a decision, then **writes back a value it calculated itself**.
I ran the steps in this order; the sale block was the same in A and B:
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
I observed `cached_stock = 0` and `ledger_stock = -1`. **Two customers were sold the last piece**, and my cached
balance no longer matched the ledger. **Evidence:** I captured both windows and the check query.

## Demo 3: Fix 1, pessimistic locking with `SELECT ... FOR UPDATE`
Reset, then:
| Step | Window | Run |
|---|---|---|
| 1 | A | `BEGIN;` then `SELECT quantity_on_hand FROM product WHERE sku='S-JUM-PIECE' FOR UPDATE;` (sees 1) |
| 2 | B | `BEGIN;` then the same query. **It hangs, with no result.** This is the lock. |
| 3 | A | `UPDATE product SET quantity_on_hand = quantity_on_hand - 1 WHERE sku='S-JUM-PIECE'; COMMIT;` |
| 4 | B | the query now returns, seeing **0**. Run `ROLLBACK;` (the application rejects the order) |

I observed B wait, then see 0 and roll back rather than make the second sale. This prevented an oversell.
**Evidence:** I captured B waiting at step 2 and its result at step 4.

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

I observed PostgreSQL abort B instead of allowing it to overwrite A. An application using this approach must **retry** the transaction.
**Evidence:** I captured B's error message.

## Demo 5: Isolation levels (price changes during checkout)
Reset, then for each isolation level (`READ COMMITTED` is the default, then `REPEATABLE READ`):
| Step | Window | Run |
|---|---|---|
| 1 | A | `BEGIN ISOLATION LEVEL READ COMMITTED;` then `SELECT unit_price FROM product WHERE sku='S-JUM-PIECE';` (7920.00) |
| 2 | B | `UPDATE product SET unit_price = unit_price + 500 WHERE sku='S-JUM-PIECE';` |
| 3 | A | run the SELECT again, then `COMMIT;` |

I observed `READ COMMITTED` return **8420.00** on the second read (a non-repeatable read). After resetting and repeating
with `REPEATABLE READ`, I saw the second read remain **7920.00**.

---
## Results summary
| Demo | Mechanism | What I observed |
|---|---|---|
| 1 | Transaction, COMMIT/ROLLBACK, CHECK constraint | I committed the 2.5 kg order. The over-stock sale raised the expected CHECK error; after I rolled back, no failed order or movement rows remained. |
| 2 | Stale reads and absolute write | Both sessions read 1 and committed a sale. I checked the balances and found cached stock 0 and ledger stock -1. |
| 3 | `SELECT ... FOR UPDATE` | Window B waited for A's lock, then read 0 after A committed. I rolled back B rather than selling again. |
| 4 | `REPEATABLE READ` | Window B waited, then received `could not serialize access due to concurrent update` after A committed. I rolled back B. |
| 5 | `READ COMMITTED` and `REPEATABLE READ` | Under `READ COMMITTED`, I read 7920 and then 8420 in A. Under `REPEATABLE READ`, I read 7920 both times. |

## Technical reflection
Demo 2 taught me why it is unsafe to check stock in one statement and later write an application-calculated balance. Both sessions read 1 before either sale committed. Each then recorded a sale and set the cached balance to 0, so both orders succeeded even though the ledger total became -1. I saw how the cached quantity and movement ledger can disagree when an application writes a value based on a stale read.

Demo 1 showed me that the CHECK constraint protects the product balance from becoming negative, but does not undo earlier order and movement inserts on its own. I need those statements in the same transaction and must roll the transaction back when the stock update fails. An insert that is later rolled back can still consume an identity value, so gaps in `order_id` are normal and do not mean an order row is missing.

In Demo 3, I used `SELECT ... FOR UPDATE` to make the second session wait until the first finished; it then saw stock at 0, so I could reject the sale. I think this approach suits a checkout where waiting briefly for a stock decision is acceptable. In Demo 4, I used `REPEATABLE READ`: the second update waited and was then rejected with a serialization error. An application using this approach needs to roll back and retry the whole transaction, which can suit workloads where detecting conflicts and retrying is preferable to queueing buyers for long periods.

In Demo 5, I observed the difference between the isolation levels. Under `READ COMMITTED`, each statement saw a fresh committed snapshot, so the second price read changed after Window B's update. Under `REPEATABLE READ`, both reads used the same transaction snapshot and the price stayed at its original value in Window A.

I ran these controlled demonstrations on one local PostgreSQL instance and a small dataset. They helped me understand transaction behaviour, but they do not measure performance or simulate failures across separate database servers.
