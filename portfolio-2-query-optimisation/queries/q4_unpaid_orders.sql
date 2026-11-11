-- Q4: Orders whose payment is still pending, with customer phone (follow-up list)
SELECT o.order_id, o.order_date, c.full_name, c.phone, p.amount, p.method
FROM payment p
JOIN orders o   ON o.order_id = p.order_id
JOIN customer c ON c.customer_id = o.customer_id
WHERE p.status = 'pending'
ORDER BY o.order_date
