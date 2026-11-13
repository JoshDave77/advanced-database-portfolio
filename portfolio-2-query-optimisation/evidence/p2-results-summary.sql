-- Summary of timings printed by run_plans.sh for this run.
-- These recorded measurements are displayed here; this query does not rerun the benchmarks.
WITH run_results (query_name, before_ms, after_ms, plan_change) AS (
    VALUES
        ('Q1 customer history', 5.466::numeric, 0.791::numeric, 'orders Seq Scan -> idx_orders_customer'),
        ('Q2 monthly revenue', 100.418::numeric, 89.325::numeric, 'orders Seq Scan -> idx_orders_date; order_item Seq Scan remains'),
        ('Q3 revenue by zone', 78.435::numeric, 57.591::numeric, 'orders Seq Scan -> idx_orders_date; order_item Seq Scan remains'),
        ('Q4 unpaid orders', 30.423::numeric, 21.790::numeric, 'payment Seq Scan -> idx_payment_pending'),
        ('Q5 stock history', 23.086::numeric, 3.533::numeric, 'stock_movement Seq Scan -> idx_stock_movement_prod_dt')
)
SELECT
    query_name,
    before_ms,
    after_ms,
    round(before_ms / after_ms, 2) AS speedup,
    round(100 * (before_ms - after_ms) / before_ms, 1) AS reduction_pct,
    plan_change
FROM run_results
ORDER BY query_name;
