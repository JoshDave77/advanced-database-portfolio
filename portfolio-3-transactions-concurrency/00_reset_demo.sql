-- Resets the demo product (smoked jumbo, per piece) to exactly 1 piece in stock,
-- keeping the stock ledger and the cached balance consistent.
-- Safe to run before every demo.
INSERT INTO stock_movement (product_id, movement_type, quantity)
SELECT p.product_id, 'adjustment',
       1 - COALESCE((SELECT sum(quantity) FROM stock_movement sm WHERE sm.product_id = p.product_id), 0)
FROM product p
WHERE p.sku = 'S-JUM-PIECE'
  AND COALESCE((SELECT sum(quantity) FROM stock_movement sm WHERE sm.product_id = p.product_id), 0) <> 1;

UPDATE product SET quantity_on_hand = 1, unit_price = 7920.00 WHERE sku = 'S-JUM-PIECE';

-- Consistency check: cached balance vs ledger (drift should be 0 here)
SELECT p.sku, p.quantity_on_hand AS cached_stock,
       (SELECT sum(quantity) FROM stock_movement sm WHERE sm.product_id = p.product_id) AS ledger_stock
FROM product p WHERE p.sku = 'S-JUM-PIECE';
