// Portfolio 4: queries on the fisheries document model
// Run:  mongosh "mongodb://localhost:27017/fisheries" --file 02_queries.js

print("\n=== Q1. One order by number: items, payment and delivery come back in ONE read ===");
printjson(db.orders.findOne({ orderNo: 1234 }, { _id: 0, customerId: 0 }));

print("\n=== Q2. A customer's order history by phone (embedded customer snapshot) ===");
const ph = db.customers.findOne({}, { phone: 1 }).phone;
db.orders.find({ "customer.phone": ph }, { _id: 0, orderNo: 1, status: 1, total: 1 }).sort({ orderDate: -1 }).limit(5).forEach(printjson);

print("\n=== Q3. Update an embedded document: mark a dispatched order as delivered ===");
const d = db.orders.findOne({ status: "dispatched" }, { orderNo: 1 });
const r = db.orders.updateOne({ orderNo: d.orderNo },
  { $set: { status: "delivered", "delivery.status": "delivered", "delivery.deliveredAt": new Date() } });
print("order " + d.orderNo + " -> matched " + r.matchedCount + ", modified " + r.modifiedCount);

print("\n=== Q4. Append to an embedded array: record a second payment on a confirmed order ===");
const c = db.orders.findOne({ status: "confirmed" }, { orderNo: 1 });
db.orders.updateOne({ orderNo: c.orderNo },
  { $push: { payments: { method: "cash", amount: 1000, status: "confirmed", paidAt: new Date() } } });
printjson(db.orders.findOne({ orderNo: c.orderNo }, { _id: 0, orderNo: 1, payments: 1 }));

print("\n=== Q5. Aggregation: delivered revenue by zone, last 30 days ===");
db.orders.aggregate([
  { $match: { status: "delivered", orderDate: { $gte: new Date(Date.now() - 30 * 86400000) } } },
  { $group: { _id: "$customer.zone", orders: { $sum: 1 }, revenue: { $sum: "$itemsTotal" } } },
  { $sort: { revenue: -1 } }
]).forEach(printjson);

print("\n=== Q6. Aggregation: top 5 products by revenue ($unwind on the embedded items) ===");
db.orders.aggregate([
  { $match: { status: { $ne: "cancelled" } } },
  { $unwind: "$items" },
  { $group: { _id: "$items.sku", revenue: { $sum: "$items.lineTotal" }, unitsSold: { $sum: "$items.quantity" } } },
  { $sort: { revenue: -1 } }, { $limit: 5 }
]).forEach(printjson);

print("\n=== Q7. $lookup (a join): smoked products' smoking method, joined from the products collection ===");
db.orders.aggregate([
  { $unwind: "$items" },
  { $match: { "items.form": "smoked" } },
  { $group: { _id: "$items.sku", revenue: { $sum: "$items.lineTotal" } } },
  { $sort: { revenue: -1 } }, { $limit: 3 },
  { $lookup: { from: "products", localField: "_id", foreignField: "sku", as: "product" } },
  { $project: { _id: 0, sku: "$_id", revenue: 1, smokingMethod: { $first: "$product.attributes.smokingMethod" } } }
]).forEach(printjson);

print("\n=== Q8. Schema validation rejects bad documents ===");
try { db.orders.insertOne({ orderNo: 999999, customer: { customerId: 1, fullName: "x", phone: "0", zone: "Jos" },
        orderDate: new Date(), status: "pending", items: [] });   // empty items array
      print("UNEXPECTED: accepted"); } catch (e) { print("Rejected (empty items): " + e.message); }
try { db.orders.insertOne({ orderNo: 999998, customer: { customerId: 1, fullName: "x", phone: "0", zone: "Jos" },
        orderDate: new Date(), status: "shipped",                // not an allowed status
        items: [{ sku: "F-MED-KG", quantity: 1, unitPrice: 3900 }] });
      print("UNEXPECTED: accepted"); } catch (e) { print("Rejected (bad status): " + e.message); }
