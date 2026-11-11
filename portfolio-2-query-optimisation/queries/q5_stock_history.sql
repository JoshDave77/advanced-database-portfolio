-- Q5: Stock movement history for one product in the last 30 days
SELECT movement_id, movement_type, quantity, moved_at
FROM stock_movement
WHERE product_id = 10
  AND moved_at >= now() - interval '30 days'
ORDER BY moved_at DESC
