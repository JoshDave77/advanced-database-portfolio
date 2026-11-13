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
1. **I describe each product by its form, size grade, and selling unit.** Because catfish can be sold by the kilogram or by the piece, `sell_unit` restricts the allowed units and `NUMERIC` quantities can represent amounts such as 2.5 kg.
2. **I use (`order_id`, `product_id`) as the `order_item` primary key.** This makes each product appear at most once in an order.
3. **I store the sale-time price in `order_item.unit_price`.** This preserves the amount charged if the product's current price changes later; it describes that order line rather than duplicating the current catalogue price.
4. **I keep stock movements as an append-only record of changes and store `product.quantity_on_hand` as a cached balance.** The cached value makes stock checks convenient, and a non-negative CHECK constraint guards against simple over-decrements. Concurrent sales still need transaction controls, as demonstrated in Portfolio 3.
5. **I use CHECK constraints to enforce important business rules.** For example, a transfer payment needs a reference, delivery cannot happen before dispatch, and stock-in and sale movements must have the appropriate quantity signs.
6. **I store delivery zones in a separate `delivery_zone` table.** This keeps each zone's fee in one place and gives the design a possible zone-based sharding key for Portfolio 5.

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
