-- Q2: Monthly revenue for the last 90 days (excluding cancelled orders)
SELECT date_trunc('month', o.order_date) AS month,
       count(DISTINCT o.order_id)        AS orders,
       sum(oi.quantity * oi.unit_price)  AS revenue
FROM orders o
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.order_date >= now() - interval '90 days'
  AND o.status <> 'cancelled'
GROUP BY 1
ORDER BY 1
