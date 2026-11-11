-- Indexes added after reading the BEFORE execution plans
CREATE INDEX idx_orders_customer         ON orders (customer_id);
CREATE INDEX idx_orders_date             ON orders (order_date);
CREATE INDEX idx_payment_pending         ON payment (order_id) WHERE status = 'pending';
CREATE INDEX idx_stock_movement_prod_dt  ON stock_movement (product_id, moved_at);
ANALYZE;
