// =====================================================================
// Portfolio 4: MongoDB model for Josh Kay's Fisheries (synthetic data)
// Run:  mongosh "mongodb://localhost:27017/fisheries" --file 01_seed.js
// Collections: products, customers, orders (embedded items/payments/delivery),
//              stock_movements (referenced, append-only)
// Same entities, prices and zones as the PostgreSQL design in Portfolio 1.
// =====================================================================

// --- repeatable pseudo-random generator (mulberry32) ---
function rng(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(42);

const N_CUSTOMERS = 500, N_ORDERS = 10000, BATCHES_PER_PRODUCT = 30;
const DAY = 86400000, NOW = Date.now();
const ZONES = { Abuja: 1500, Lagos: 3500, Jos: 2000, Kaduna: 1800 };
const ZONE_NAMES = Object.keys(ZONES);

// --- start clean so the script can be re-run ---
["products", "customers", "orders", "stock_movements"].forEach(c => db.getCollection(c).drop());

// --- schema validation: documents are flexible, but not lawless ---
db.createCollection("orders", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["orderNo", "customer", "orderDate", "status", "items"],
    properties: {
      orderNo:   { bsonType: "number" },
      status:    { enum: ["pending", "confirmed", "dispatched", "delivered", "cancelled"] },
      customer:  { bsonType: "object", required: ["customerId", "fullName", "phone", "zone"] },
      items: {
        bsonType: "array", minItems: 1,
        items: { bsonType: "object", required: ["sku", "quantity", "unitPrice"],
                 properties: { quantity: { bsonType: "number", minimum: 0.01 },
                               unitPrice: { bsonType: "number", minimum: 0.01 } } }
      },
      payments: { bsonType: "array",
                  items: { bsonType: "object", properties: { method: { enum: ["transfer", "cash"] } } } }
    }
  } },
  validationAction: "error"
});
db.createCollection("products");
db.createCollection("customers");
db.createCollection("stock_movements");

// --- products: attributes differ by form (the document-model advantage) ---
const products = [];
for (const form of ["fresh", "smoked"])
  for (const grade of ["small", "medium", "large", "jumbo"])
    for (const unit of ["kg", "piece"]) {
      const price = Math.round((form === "fresh" ? 3000 : 4500)
        * { small: 1.0, medium: 1.3, large: 1.7, jumbo: 2.2 }[grade] * (unit === "kg" ? 1.0 : 0.8) * 100) / 100;
      products.push({
        sku: form[0].toUpperCase() + "-" + grade.slice(0, 3).toUpperCase() + "-" + unit.toUpperCase(),
        name: form[0].toUpperCase() + form.slice(1) + " catfish " + grade + " (per " + unit + ")",
        form: form, sizeGrade: grade, sellUnit: unit, unitPrice: price, isActive: true,
        attributes: form === "fresh"
          ? { source: "pond", handling: "iced", shelfLifeDays: 2 }
          : { smokingMethod: "kiln", woodType: "hardwood", shelfLifeDays: 14 }
      });
    }
const bySku = {}; products.forEach(p => bySku[p.sku] = p);

// --- customers ---
const customers = [];
for (let i = 1; i <= N_CUSTOMERS; i++) {
  const c = { fullName: "Customer " + i, phone: "0802" + String(i).padStart(7, "0"),
              address: i + " Sample Street", zone: ZONE_NAMES[i % 4],
              createdAt: new Date(NOW - rand() * 365 * DAY) };
  if (i % 2 === 0) c.email = "customer" + i + "@example.com";   // optional field: absent, not NULL
  customers.push(c);
}
const custIds = db.customers.insertMany(customers).insertedIds;
const custDocs = customers.map((c, idx) => ({ id: custIds[idx], ...c }));

// --- orders (items, payments and delivery embedded) + stock ledger ---
const sold = {};  products.forEach(p => sold[p.sku] = 0);
const orders = [], movements = [];
for (let n = 1; n <= N_ORDERS; n++) {
  const c = custDocs[Math.floor(rand() * N_CUSTOMERS)];
  const date = new Date(NOW - rand() * 365 * DAY);
  const r = rand();
  const status = r < 0.80 ? "delivered" : r < 0.88 ? "dispatched" : r < 0.94 ? "confirmed" : r < 0.97 ? "pending" : "cancelled";

  const items = [];
  for (let k = 1; k <= 1 + (n % 4); k++) {
    const p = products[(n * 7 + k * 5) % 16];
    const qty = p.sellUnit === "kg" ? 0.5 + Math.floor(rand() * 9) * 0.5 : 1 + Math.floor(rand() * 6);
    items.push({ sku: p.sku, name: p.name, form: p.form, sellUnit: p.sellUnit,
                 quantity: qty, unitPrice: p.unitPrice, lineTotal: Math.round(qty * p.unitPrice * 100) / 100 });
  }
  const itemsTotal = items.reduce((s, i) => s + i.lineTotal, 0);
  const fee = ZONES[c.zone];
  const o = { orderNo: n, customerId: c.id,
              customer: { customerId: c.id, fullName: c.fullName, phone: c.phone, zone: c.zone },  // snapshot
              takenBy: n % 2 ? "Sales Staff 1" : "Sales Staff 2", orderDate: date, status: status,
              items: items, itemsTotal: itemsTotal, deliveryFee: fee, total: itemsTotal + fee, payments: [] };

  if (status !== "cancelled") {
    const method = (n % 100) < 65 ? "transfer" : "cash";
    const paid = !(status === "pending" || status === "confirmed");
    const pay = { method: method, amount: o.total, status: paid ? "confirmed" : "pending" };
    if (method === "transfer") pay.reference = "TRF-" + String(n).padStart(8, "0");
    if (paid) pay.paidAt = new Date(date.getTime() + 600000);
    o.payments.push(pay);
    o.delivery = { rider: "Rider " + c.zone, zone: c.zone,
                   status: status === "delivered" ? "delivered" : status === "dispatched" ? "dispatched" : "pending" };
    if (status === "delivered" || status === "dispatched") o.delivery.dispatchedAt = new Date(date.getTime() + 3 * 3600000);
    if (status === "delivered") o.delivery.deliveredAt = new Date(date.getTime() + DAY);
    items.forEach(i => { sold[i.sku] += i.quantity;
      movements.push({ sku: i.sku, type: "sale_out", quantity: -i.quantity, orderNo: n, movedAt: date }); });
  }
  orders.push(o);
}
for (let i = 0; i < orders.length; i += 1000) db.orders.insertMany(orders.slice(i, i + 1000));

// --- stock-in batches, then cached stock per product ---
const stockIn = {}; products.forEach(p => stockIn[p.sku] = 0);
for (const p of products)
  for (let b = 0; b < BATCHES_PER_PRODUCT; b++) {
    const q = 400 + Math.floor(rand() * 400);
    stockIn[p.sku] += q;
    movements.push({ sku: p.sku, type: p.form === "fresh" ? "harvest_in" : "smoking_in", quantity: q,
                     movedAt: new Date(NOW - rand() * 365 * DAY) });
  }
for (let i = 0; i < movements.length; i += 5000) db.stock_movements.insertMany(movements.slice(i, i + 5000));
products.forEach(p => p.stockOnHand = stockIn[p.sku] - sold[p.sku]);
db.products.insertMany(products);

// --- integrity indexes (performance indexes come later, in 03) ---
db.products.createIndex({ sku: 1 }, { unique: true });
db.customers.createIndex({ phone: 1 }, { unique: true });
db.orders.createIndex({ orderNo: 1 }, { unique: true });

print("Seed complete:");
["products", "customers", "orders", "stock_movements"].forEach(c => print("  " + c + ": " + db.getCollection(c).countDocuments()));
print("  lowest stock on hand: " + Math.min(...products.map(p => p.stockOnHand)));
