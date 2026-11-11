-- =====================================================================
-- Portfolio 2: synthetic data for Josh Kay's Fisheries
-- Run AFTER portfolio-1-database-design/schema.sql
-- All data is synthetic (generated with generate_series + random()).
-- setseed makes the run repeatable.
-- Volumes: 2,000 customers, 16 products, 50,000 orders (~125k items)
-- =====================================================================
SELECT setseed(0.42);

-- Staff: 1 owner, 2 sales, 2 packers, 4 riders
INSERT INTO staff (full_name, phone, role) VALUES
 ('Joshua Kanda',   '08030000001', 'owner'),
 ('Sales Staff 1',  '08030000002', 'sales'),
 ('Sales Staff 2',  '08030000003', 'sales'),
 ('Packer 1',       '08030000004', 'packer'),
 ('Packer 2',       '08030000005', 'packer'),
 ('Rider Abuja',    '08030000006', 'rider'),
 ('Rider Lagos',    '08030000007', 'rider'),
 ('Rider Jos',      '08030000008', 'rider'),
 ('Rider Kaduna',   '08030000009', 'rider');

-- Products: 2 forms x 4 grades x 2 units = 16
INSERT INTO product (sku, product_name, form, size_grade, sell_unit, unit_price)
SELECT upper(left(f,1)) || '-' || upper(left(g,3)) || '-' || upper(u),
       initcap(f) || ' catfish ' || g || ' (per ' || u || ')',
       f, g, u,
       (CASE f WHEN 'fresh' THEN 3000 ELSE 4500 END)
       * (CASE g WHEN 'small' THEN 1.0 WHEN 'medium' THEN 1.3 WHEN 'large' THEN 1.7 ELSE 2.2 END)
       * (CASE u WHEN 'kg' THEN 1.0 ELSE 0.8 END)
FROM unnest(ARRAY['fresh','smoked']) f,
     unnest(ARRAY['small','medium','large','jumbo']) g,
     unnest(ARRAY['kg','piece']) u;

-- Customers: 2,000 spread across the four zones
INSERT INTO customer (full_name, phone, email, address, zone_id, created_at)
SELECT 'Customer ' || i,
       '0802' || lpad(i::text, 7, '0'),
       CASE WHEN i % 2 = 0 THEN 'customer' || i || '@example.com' END,
       i || ' Sample Street, ' || z.zone_name,
       z.zone_id,
       now() - (random() * 365 || ' days')::interval
FROM generate_series(1, 2000) i
JOIN delivery_zone z ON z.zone_id = (i % 4) + 1;

-- Orders: 50,000 over the last 12 months
INSERT INTO orders (customer_id, taken_by, order_date, status)
SELECT 1 + floor(random() * 2000)::int,
       2 + floor(random() * 2)::int,                       -- staff 2 or 3 (sales)
       now() - (random() * 365 || ' days')::interval,
       CASE WHEN r < 0.80 THEN 'delivered'
            WHEN r < 0.88 THEN 'dispatched'
            WHEN r < 0.94 THEN 'confirmed'
            WHEN r < 0.97 THEN 'pending'
            ELSE 'cancelled' END
FROM (SELECT random() AS r FROM generate_series(1, 50000)) t;

-- Order items: 1-4 distinct products per order (price snapshot from product)
INSERT INTO order_item (order_id, product_id, quantity, unit_price)
SELECT o.order_id, p.product_id,
       CASE p.sell_unit WHEN 'kg' THEN round((0.5 + floor(random()*9) * 0.5)::numeric, 1)
                        ELSE (1 + floor(random()*6))::numeric END,
       p.unit_price
FROM orders o
CROSS JOIN LATERAL generate_series(1, 1 + (o.order_id % 4)) k
JOIN product p ON p.product_id = ((o.order_id * 7 + k * 5) % 16) + 1;

-- Batches: 120 per product (harvest for fresh, smoking for smoked)
INSERT INTO batch (product_id, batch_type, batch_date, quantity, recorded_by)
SELECT p.product_id,
       CASE p.form WHEN 'fresh' THEN 'harvest' ELSE 'smoking' END,
       (current_date - (random() * 365)::int),
       400 + floor(random() * 400),
       1
FROM product p, generate_series(1, 120);

-- Stock ledger: stock in from batches ...
INSERT INTO stock_movement (product_id, batch_id, movement_type, quantity, moved_at)
SELECT b.product_id, b.batch_id,
       CASE b.batch_type WHEN 'harvest' THEN 'harvest_in' ELSE 'smoking_in' END,
       b.quantity, b.batch_date::timestamptz
FROM batch b;

-- ... and stock out for every non-cancelled order line
INSERT INTO stock_movement (product_id, order_id, movement_type, quantity, moved_at)
SELECT oi.product_id, oi.order_id, 'sale_out', -oi.quantity, o.order_date
FROM order_item oi JOIN orders o USING (order_id)
WHERE o.status <> 'cancelled';

-- Cached stock balance = sum of the ledger
UPDATE product p
SET quantity_on_hand = s.bal
FROM (SELECT product_id, sum(quantity) AS bal FROM stock_movement GROUP BY product_id) s
WHERE s.product_id = p.product_id;

-- Payments: one per non-cancelled order (amount = items + zone delivery fee)
INSERT INTO payment (order_id, method, amount, reference, status, paid_at)
SELECT o.order_id,
       m.method,
       t.total + z.delivery_fee,
       CASE WHEN m.method = 'transfer' THEN 'TRF-' || lpad(o.order_id::text, 8, '0') END,
       CASE WHEN o.status IN ('pending','confirmed') THEN 'pending' ELSE 'confirmed' END,
       CASE WHEN o.status IN ('pending','confirmed') THEN NULL ELSE o.order_date + interval '10 minutes' END
FROM orders o
JOIN customer c ON c.customer_id = o.customer_id
JOIN delivery_zone z ON z.zone_id = c.zone_id
JOIN LATERAL (SELECT sum(quantity * unit_price) AS total FROM order_item WHERE order_id = o.order_id) t ON true
CROSS JOIN LATERAL (SELECT CASE WHEN o.order_id % 100 < 65 THEN 'transfer' ELSE 'cash' END AS method) m
WHERE o.status <> 'cancelled';

-- Deliveries: one per non-cancelled order, rider matches the zone (staff 6-9)
INSERT INTO delivery (order_id, rider_id, zone_id, status, dispatched_at, delivered_at)
SELECT o.order_id,
       5 + c.zone_id,
       c.zone_id,
       CASE o.status WHEN 'delivered'  THEN 'delivered'
                     WHEN 'dispatched' THEN 'dispatched'
                     ELSE 'pending' END,
       CASE WHEN o.status IN ('delivered','dispatched') THEN o.order_date + interval '3 hours' END,
       CASE WHEN o.status = 'delivered' THEN o.order_date + interval '1 day' END
FROM orders o JOIN customer c USING (customer_id)
WHERE o.status <> 'cancelled';

ANALYZE;
