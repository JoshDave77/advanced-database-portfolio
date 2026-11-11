# Portfolio 1: Database Design and Modelling

## Case study
**Organisation:** Josh Kay's Fisheries, a small business selling fresh and smoked catfish.
**System:** An order, inventory and delivery database, from harvest or smoking batch through to customer delivery.
**Users:** Owner/admin, sales staff, packers, delivery riders, customers.
**Major data:** Customers, products, batches, stock movements, orders, order items, payments, deliveries, delivery zones (Abuja, Lagos, Jos, Kaduna).
**Key operations:** Record a batch, place an order, reduce stock, record payment (transfer or cash), assign and track delivery, report on sales and stock.

## Files
- `schema.sql`: full PostgreSQL schema with keys and constraints (tested, runs without errors)
- `er-diagram.md` / `er-diagram.png`: entity relationship diagram

## Key design decisions
<!-- TODO (Joshua): rewrite each point in your own words after reviewing it. -->
1. **Products are form + size grade + selling unit.** Some products sell per kg and others per piece, so `sell_unit` is a column with a CHECK, and quantities are `NUMERIC` so 2.5 kg and 3 pieces both work.
2. **`order_item` has a composite primary key** (`order_id`, `product_id`). One product appears once per order.
3. **`order_item.unit_price` is a price snapshot.** It is a historical fact about the sale, not a copy of `product.unit_price`, so it does not violate 3NF.
4. **`stock_movement` is an append-only ledger** and `product.quantity_on_hand` is a cached balance. This is a deliberate denormalisation for fast stock checks, protected by `CHECK (quantity_on_hand >= 0)`. It is also the constraint that stops overselling in Portfolio 3.
5. **Business rules live in CHECK constraints:** transfers must carry a reference, delivery time cannot precede dispatch time, stock-in is positive and sales are negative.
6. **`delivery_zone` is its own table**, so zone fee changes in one place. It is also the planned sharding key in Portfolio 5.

## Normalisation walkthrough
Start from an unnormalised order sheet: `order_no, customer_name, phone, address, zone, product_1, qty_1, price_1, product_2, qty_2, price_2, payment_method, rider`.

- **1NF:** Remove repeating groups (`product_1`, `product_2`...). Each order line becomes a row in `order_item`. All values atomic.
- **2NF:** In `order_item`, product name, form and size depend only on `product_id`, not on the whole key (`order_id`, `product_id`). Move them into `product`.
- **3NF:** Customer address and zone depend on the customer, not the order, so they move into `customer`. Zone fee depends on the zone, not the customer, so it moves into `delivery_zone`. No non-key column depends on another non-key column.
- **Deliberate exception:** `quantity_on_hand` (see decision 4).

## How it was tested
```bash
createdb fisheries
psql -d fisheries -f schema.sql
\dt   # 10 tables expected
```
