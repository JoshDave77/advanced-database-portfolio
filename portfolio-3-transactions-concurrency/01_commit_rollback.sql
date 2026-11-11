-- Demo 1: COMMIT and ROLLBACK (single session)
-- Run with:  psql -d fisheries -f 01_commit_rollback.sql
-- (the deliberate ERROR in section B is expected)
\echo '=== Before ==='
SELECT count(*) AS orders_before FROM orders \gset
SELECT :orders_before AS orders_before;
SELECT sku, quantity_on_hand FROM product WHERE sku IN ('F-MED-KG','S-JUM-PIECE') ORDER BY sku;

\echo '=== A. Successful order: 2.5 kg fresh medium for customer 1 -> COMMIT ==='
BEGIN;
INSERT INTO orders (customer_id, taken_by, status) VALUES (1, 2, 'confirmed') RETURNING order_id \gset a_
INSERT INTO order_item (order_id, product_id, quantity, unit_price)
  SELECT :a_order_id, product_id, 2.5, unit_price FROM product WHERE sku = 'F-MED-KG';
INSERT INTO stock_movement (product_id, order_id, movement_type, quantity)
  SELECT product_id, :a_order_id, 'sale_out', -2.5 FROM product WHERE sku = 'F-MED-KG';
UPDATE product SET quantity_on_hand = quantity_on_hand - 2.5 WHERE sku = 'F-MED-KG';
COMMIT;
SELECT :a_order_id AS committed_order_id;
SELECT order_id, status FROM orders WHERE order_id = :a_order_id;

\echo '=== B. Failing order: 5 pieces smoked jumbo but only 1 in stock -> ROLLBACK ==='
BEGIN;
INSERT INTO orders (customer_id, taken_by, status) VALUES (1, 2, 'confirmed') RETURNING order_id \gset b_
INSERT INTO order_item (order_id, product_id, quantity, unit_price)
  SELECT :b_order_id, product_id, 5, unit_price FROM product WHERE sku = 'S-JUM-PIECE';
INSERT INTO stock_movement (product_id, order_id, movement_type, quantity)
  SELECT product_id, :b_order_id, 'sale_out', -5 FROM product WHERE sku = 'S-JUM-PIECE';
-- This violates CHECK (quantity_on_hand >= 0) and aborts the transaction:
UPDATE product SET quantity_on_hand = quantity_on_hand - 5 WHERE sku = 'S-JUM-PIECE';
-- Any further statement now fails until ROLLBACK:
SELECT 'this will fail: transaction is aborted' AS note;
ROLLBACK;

\echo '=== After: the failed order left nothing behind ==='
SELECT count(*) - :orders_before AS new_orders_should_be_1 FROM orders;
SELECT count(*) AS failed_order_rows_should_be_0 FROM orders WHERE order_id = :b_order_id;
SELECT count(*) AS failed_ledger_rows_should_be_0 FROM stock_movement WHERE order_id = :b_order_id;
SELECT sku, quantity_on_hand FROM product WHERE sku IN ('F-MED-KG','S-JUM-PIECE') ORDER BY sku;
