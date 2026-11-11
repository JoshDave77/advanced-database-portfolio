-- Q1: Order history for one customer (customer service lookup)
SELECT o.order_id, o.order_date, o.status,
       sum(oi.quantity * oi.unit_price) AS items_total
FROM orders o
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.customer_id = 1234
GROUP BY o.order_id, o.order_date, o.status
ORDER BY o.order_date DESC
