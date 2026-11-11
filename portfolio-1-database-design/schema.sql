-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Case study: Josh Kay's Fisheries (fresh and smoked catfish)
-- DBMS: PostgreSQL
-- =====================================================================

DROP TABLE IF EXISTS delivery, payment, order_item, stock_movement,
                     orders, batch, product, customer, staff, delivery_zone CASCADE;

-- 1. Delivery zones (later used as the sharding key in Portfolio 5)
CREATE TABLE delivery_zone (
    zone_id       SMALLINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    zone_name     VARCHAR(50)   NOT NULL UNIQUE,
    delivery_fee  NUMERIC(10,2) NOT NULL CHECK (delivery_fee >= 0)
);

-- 2. Staff (owner, sales, packers, riders)
CREATE TABLE staff (
    staff_id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name  VARCHAR(100) NOT NULL,
    phone      VARCHAR(20)  NOT NULL UNIQUE,
    role       VARCHAR(20)  NOT NULL
               CHECK (role IN ('owner','sales','packer','rider')),
    is_active  BOOLEAN      NOT NULL DEFAULT TRUE
);

-- 3. Customers
CREATE TABLE customer (
    customer_id  INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name    VARCHAR(100) NOT NULL,
    phone        VARCHAR(20)  NOT NULL UNIQUE,
    email        VARCHAR(120) UNIQUE,
    address      VARCHAR(255) NOT NULL,
    zone_id      SMALLINT     NOT NULL REFERENCES delivery_zone(zone_id),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 4. Products (a product is a form + size grade + selling unit)
CREATE TABLE product (
    product_id        INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku               VARCHAR(30)   NOT NULL UNIQUE,
    product_name      VARCHAR(100)  NOT NULL,
    form              VARCHAR(10)   NOT NULL CHECK (form IN ('fresh','smoked')),
    size_grade        VARCHAR(10)   NOT NULL CHECK (size_grade IN ('small','medium','large','jumbo')),
    sell_unit         VARCHAR(10)   NOT NULL CHECK (sell_unit IN ('kg','piece')),
    unit_price        NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    -- Controlled denormalisation: cached balance of stock_movement.
    -- CHECK (>= 0) is what prevents overselling in Portfolio 3.
    quantity_on_hand  NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    is_active         BOOLEAN       NOT NULL DEFAULT TRUE,
    UNIQUE (form, size_grade, sell_unit)
);

-- 5. Batches (a harvest from the pond or a smoking run)
CREATE TABLE batch (
    batch_id        INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id      INT           NOT NULL REFERENCES product(product_id),
    batch_type      VARCHAR(10)   NOT NULL CHECK (batch_type IN ('harvest','smoking')),
    batch_date      DATE          NOT NULL,
    quantity        NUMERIC(10,2) NOT NULL CHECK (quantity > 0),
    recorded_by     INT           NOT NULL REFERENCES staff(staff_id)
);

-- 6. Orders
CREATE TABLE orders (
    order_id     INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  INT          NOT NULL REFERENCES customer(customer_id),
    taken_by     INT          REFERENCES staff(staff_id),
    order_date   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    status       VARCHAR(12)  NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','confirmed','dispatched','delivered','cancelled'))
);

-- 7. Order items (price is a snapshot of the price at order time)
CREATE TABLE order_item (
    order_id    INT           NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id  INT           NOT NULL REFERENCES product(product_id),
    quantity    NUMERIC(10,2) NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, product_id)
);

-- 8. Stock movements (append-only ledger)
CREATE TABLE stock_movement (
    movement_id    BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id     INT           NOT NULL REFERENCES product(product_id),
    batch_id       INT           REFERENCES batch(batch_id),
    order_id       INT           REFERENCES orders(order_id),
    movement_type  VARCHAR(12)   NOT NULL
                   CHECK (movement_type IN ('harvest_in','smoking_in','sale_out','adjustment')),
    quantity       NUMERIC(10,2) NOT NULL CHECK (quantity <> 0),
    moved_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- stock-in rows must be positive, sales must be negative
    CHECK ((movement_type IN ('harvest_in','smoking_in') AND quantity > 0)
        OR (movement_type = 'sale_out' AND quantity < 0)
        OR  movement_type = 'adjustment')
);

-- 9. Payments (transfer or cash)
CREATE TABLE payment (
    payment_id  INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    INT           NOT NULL REFERENCES orders(order_id),
    method      VARCHAR(10)   NOT NULL CHECK (method IN ('transfer','cash')),
    amount      NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    reference   VARCHAR(60),
    status      VARCHAR(10)   NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','confirmed','failed')),
    paid_at     TIMESTAMPTZ,
    -- a bank transfer must carry a reference so it can be reconciled
    CHECK (method <> 'transfer' OR reference IS NOT NULL)
);

-- 10. Deliveries (one per order)
CREATE TABLE delivery (
    delivery_id    INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id       INT          NOT NULL UNIQUE REFERENCES orders(order_id),
    rider_id       INT          REFERENCES staff(staff_id),
    zone_id        SMALLINT     NOT NULL REFERENCES delivery_zone(zone_id),
    status         VARCHAR(12)  NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','dispatched','delivered','failed')),
    dispatched_at  TIMESTAMPTZ,
    delivered_at   TIMESTAMPTZ,
    CHECK (delivered_at IS NULL OR dispatched_at IS NULL OR delivered_at >= dispatched_at)
);

-- Seed reference data
INSERT INTO delivery_zone (zone_name, delivery_fee) VALUES
    ('Abuja', 1500), ('Lagos', 3500), ('Jos', 2000), ('Kaduna', 1800);
