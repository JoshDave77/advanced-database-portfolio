# Portfolio 1: Database Design and Modelling

## Case study
**Organisation:** I modelled Josh Kay's Fisheries, a small business selling fresh and smoked catfish.
**System:** I designed an order, inventory and delivery database covering the process from harvest or smoking batch through to customer delivery.
**Users:** I identified the owner/administrator, sales staff, packers, delivery riders and customers as the system's users.
**Major data:** I modelled customers, products, batches, stock movements, orders, order items, payments, deliveries and delivery zones (Abuja, Lagos, Jos and Kaduna).
**Key operations:** I designed the database to record batches, place orders, reduce stock, record transfer or cash payments, assign and track deliveries, and report on sales and stock.

## Files
- `schema.sql`: the PostgreSQL schema I created, with keys and constraints; I tested it and it runs without errors.
- `er-diagram.md` / `er-diagram.png`: the entity relationship diagram I created.

## Key design decisions
1. **I describe each product by its form, size grade, and selling unit.** Since I sell catfish by the kilogram or by the piece, I use `sell_unit` to restrict the allowed units and `NUMERIC` quantities to represent amounts such as 2.5 kg.
2. **I use (`order_id`, `product_id`) as the `order_item` primary key.** I chose this key so each product can appear at most once in an order.
3. **I store the sale-time price in `order_item.unit_price`.** I do this to preserve the amount charged if I change the product's current price later; the value describes that order line rather than duplicating the current catalogue price.
4. **I keep stock movements as an append-only record of changes and store `product.quantity_on_hand` as a cached balance.** I use the cached value to make stock checks convenient and a non-negative CHECK constraint to guard against simple over-decrements. As I demonstrated in Portfolio 3, I still need transaction controls for concurrent sales.
5. **I use CHECK constraints to enforce important business rules.** For example, I require a reference for a transfer payment, prevent delivery before dispatch, and require stock-in and sale movements to have the appropriate quantity signs.
6. **I store delivery zones in a separate `delivery_zone` table.** I did this to keep each zone's fee in one place and to give myself a possible zone-based sharding key for Portfolio 5.

## My normalisation walkthrough
I started with an unnormalised order sheet: `order_no, customer_name, phone, address, zone, product_1, qty_1, price_1, product_2, qty_2, price_2, payment_method, rider`.

- **1NF:** I removed the repeating product groups (`product_1`, `product_2`, etc.) and stored each order line in `order_item`, with atomic values.
- **2NF:** I moved product name, form and size into `product` because they depend on `product_id`, not on the full `order_item` key (`order_id`, `product_id`).
- **3NF:** I moved customer address and zone into `customer`, and the zone fee into `delivery_zone`, so non-key attributes depend on their relevant keys rather than on other non-key attributes.
- **Deliberate exception:** I retained `quantity_on_hand` as a cached balance (see decision 4).

## How I tested it
```bash
createdb fisheries
psql -d fisheries -f schema.sql
\dt   # 10 tables expected
```

## References
- Miva Open University. (2026/2027). *MIT 8103 Advanced Database Systems: Individual Practical Database Portfolio*. First Semester Continuous Assessment.
- PostgreSQL Global Development Group. *PostgreSQL 18 Documentation: Constraints*. https://www.postgresql.org/docs/18/ddl-constraints.html
