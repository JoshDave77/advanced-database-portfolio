-- Q3: Delivered revenue by delivery zone in the last 30 days
SELECT z.zone_name,
       count(DISTINCT o.order_id)        AS orders,
       sum(oi.quantity * oi.unit_price)  AS revenue
FROM orders o
JOIN customer c       ON c.customer_id = o.customer_id
JOIN delivery_zone z  ON z.zone_id = c.zone_id
JOIN order_item oi    ON oi.order_id = o.order_id
WHERE o.status = 'delivered'
  AND o.order_date >= now() - interval '30 days'
GROUP BY z.zone_name
ORDER BY revenue DESC
