// Portfolio 4: indexing and explain() evidence
// Run:  mongosh "mongodb://localhost:27017/fisheries" --file 03_indexes_explain.js

function leafStages(p) {                       // walk the plan tree and list its stages
  if (!p) return [];
  if (p.queryPlan) return leafStages(p.queryPlan);
  let s = [p.stage];
  if (p.inputStage) s = s.concat(leafStages(p.inputStage));
  if (p.inputStages) p.inputStages.forEach(x => s = s.concat(leafStages(x)));
  return s;
}
function report(label, cursor) {
  const ex = cursor.explain("executionStats"), es = ex.executionStats;
  print(label.padEnd(34) + " plan=" + leafStages(ex.queryPlanner.winningPlan).join(">").padEnd(32)
        + " examined=" + String(es.totalDocsExamined).padStart(6) + " returned=" + String(es.nReturned).padStart(5)
        + " ms=" + es.executionTimeMillis);
}
const phone = db.customers.findOne({}, { phone: 1 }).phone;
const since = new Date(Date.now() - 30 * 86400000);
function runAll(tag) {
  print("\n--- " + tag + " ---");
  report("E1 orders by customer phone", db.orders.find({ "customer.phone": phone }));
  report("E2 pending orders, last 30 days", db.orders.find({ status: "pending", orderDate: { $gte: since } }).sort({ orderDate: -1 }));
  report("E3 pending orders containing a SKU", db.orders.find({ "items.sku": "S-JUM-PIECE", status: "pending" }));
}

// drop performance indexes so the script can be repeated
["customer.phone_1", "status_1_orderDate_-1", "items.sku_1_status_1"].forEach(n => { try { db.orders.dropIndex(n); } catch (e) {} });

runAll("BEFORE (only the unique orderNo index exists)");
db.orders.createIndex({ "customer.phone": 1 });
db.orders.createIndex({ status: 1, orderDate: -1 });    // equality field first, then sort/range field
db.orders.createIndex({ "items.sku": 1, status: 1 });   // multikey index on an embedded array
runAll("AFTER (3 indexes added)");

print("\nIndexes on orders:");
db.orders.getIndexes().forEach(i => print("  " + i.name));
