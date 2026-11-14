# Portfolio 5: Distributed and Cloud Database Exercise

**Case study:** Josh Kay's Fisheries (same MongoDB data as Portfolio 4).
**What was implemented:** a 3-node MongoDB **replica set** on one computer, with replication, failover and majority-loss demos.
**What is design/discussion only:** sharding by delivery zone (not executed), and PostgreSQL replication.
**Tested on:** MongoDB Server 9.0.8 and mongosh 2.14.2.

## Why distribute this business's data at all?
Orders and payments are the money record, so losing them or having the order system go down on a busy day (e.g. a festive season)
is costly. Replication keeps three copies and can keep the service available after one replica member fails. These three
members ran on one computer, so this exercise did not test a whole-machine or network failure. Sharding is about scale;
this business is small, so I treat it as a design exercise, not a need.

## Files
| File | Purpose |
|---|---|
| `common.sh`, `status.js` | Shared settings and helper functions |
| `01_start_replica_set.sh` | Starts 3 members (ports 27018-27020), initiates the set, loads the Portfolio 4 data |
| `02_replication_check.sh` | Majority-acknowledged write; same counts on every member |
| `03_failover.sh` | Stops the primary, watches the election, keeps writing, restarts the old primary |
| `04_majority_loss.sh` | Leaves one of three members: writes are refused, reads still work |
| `05_stop_all.sh` | Stops everything (`clean` also deletes `data/` and `logs/`) |
| `evidence/` | Captures from the four local demos |

## How to run (Git Bash, from this folder)
If `mongod` or `mongosh` are not on your PATH, set their executable paths in Git Bash. These are the paths used for
this run; adjust them if you installed either program elsewhere:
```bash
export MONGOD="$(cygpath -u 'C:\Program Files\MongoDB\Server\9.0\bin\mongod.exe')"
export MONGOSH="$(cygpath -u "$USERPROFILE\Documents\mongosh-2.14.2-win32-x64\mongosh-2.14.2-win32-x64\bin\mongosh.exe")"
"$MONGOD" --version
"$MONGOSH" --version
```
Keep this Git Bash session open so the exported paths remain available to each demo.
```bash
bash 01_start_replica_set.sh
bash 02_replication_check.sh
bash 03_failover.sh
bash 04_majority_loss.sh
bash 05_stop_all.sh
```
The members run as background processes. `05_stop_all.sh clean` also deletes `data/` and `logs/`; omit `clean` to
preserve them.

## What each demo shows
| Demo | Concept | What you should observe |
|---|---|---|
| 01 | **Replica-set setup** | One PRIMARY, two SECONDARY members; 16 products, 500 customers, 10,000 orders and 24,669 stock movements |
| 02 | **Replication, durability** | `w:"majority"` write acknowledged; all members report `orders=10000`, `products=16` and the replicated log entry |
| 03 | **Availability** | Election from port 27019 to 27018 in about 3 seconds; majority write works with 2 of 3 members; old primary rejoins |
| 04 | **Consistency vs availability (CAP)** | With one of three members left, writes are refused (`not primary`), reads work, and the set recovers |

In my run, the clean shutdown of the primary led to an election in about **3 seconds**. After Demo 03, each member
reported four `failover_log` entries. In Demo 04, the lone member refused a write but returned `orders=10000` for a read;
after the other members restarted, port 27020 became PRIMARY. A real crash may take longer; the default election timeout
is 10 seconds.

## Consistency and availability decisions for the fisheries data
| Data | Write concern | Reads from | Reason |
|---|---|---|---|
| Orders, payments | `w: "majority"` | Primary | Money record: must survive a failover and never be read stale |
| Stock quantity | `w: "majority"` | **Primary only** | Overselling risk (Portfolio 3); a stale read can sell the last piece twice |
| Sales reports, revenue by zone | default | Secondary (`secondaryPreferred`) | A few seconds of delay is harmless, and it moves load off the primary |
| Product catalogue | `w: 1` is acceptable | Secondary | Rarely changes; fast writes matter more |

## CAP discussion (this is what Demo 04 shows)
In this test, when only one of three members remained, it could not form a majority and stepped down as primary. The
write was refused, while a `secondaryPreferred` read still returned the order count. That favors consistency for writes
over write availability in this failure case; a secondary read can be stale. For a business taking orders, a refused
order that is retried is better than conflicting stock counts.

## Sharding design (NOT implemented, discussion only)
Sharding splits data across machines. For `orders` I considered:
| Shard key | Benefit | Problem |
|---|---|---|
| `{ orderNo: "hashed" }` | Even spread of writes | A report for one zone must ask every shard (scatter-gather) |
| `{ "customer.zone": 1, orderNo: 1 }` | Queries for one zone go to one shard; zone-aware placement is possible (e.g. Lagos data on a Lagos-located shard) | Only 4 zones, so `orderNo` is needed in the key to let chunks split; Lagos could be much busier than the rest; rising `orderNo` makes the newest chunk of each zone a hotspot |
Recommendation for this business: not needed yet. At current volume one replica set is enough. If growth required it,
I would start with the zone-prefixed compound key because most queries (deliveries, regional reports) are by zone.
Unsharded collections such as `products` and `customers` would stay on one shard.

## Cloud deployment (optional but strong evidence): MongoDB Atlas free tier
Atlas clusters are replica sets of three nodes managed in the cloud.
1. Create a free **M0** cluster at cloud.mongodb.com.
2. **Database Access**: create a database user. **Network Access**: allow your current IP address.
3. **Connect, Drivers/Shell**: copy the connection string (it contains your password, so never commit it).
4. Load the data: `"$MONGOSH" "<your Atlas connection string>/fisheries" --file ../portfolio-4-nosql/01_seed.js`
5. **Screenshots:** the cluster overview showing its three nodes, and a query result from mongosh connected to Atlas.
The free tier does not allow you to trigger a failover on demand, which is why the local replica set is the failover evidence.

## PostgreSQL side (discussion only)
The relational design could use streaming replication: one primary takes writes, hot standbys serve read-only reports and
can be promoted if the primary fails. I did not implement it.

## Evidence checklist (your own screenshots)
- [x] `01`: three members started, one PRIMARY and two SECONDARY (`p5-01-replica-set-start.png`)
- [x] `02`: same document counts on all three members (`p5-02-replication-check.png`; an additional capture is `p5-02-replication 2-check.png`)
- [x] `03`: election, write during the outage and old primary rejoining (`p5-03a-failover-election.png`, `p5-03b-failover-recovery.png`)
- [x] `04`: `REFUSED: not primary` and successful read (`p5-04-majority-loss.png`)
- [ ] (optional) Atlas cluster page and query output

## Technical reflection
I ran the local replica set with MongoDB 9.0.8 and mongosh 2.14.2. Neither executable was on my PATH, so I set
`MONGOD` and `MONGOSH` in Git Bash. The paths contained spaces; quoting the `MONGOSH` variable in the scripts was
necessary for their readiness checks and later demos to work. I also encountered a terminal paste issue that inserted
`[200~` into a command, so I typed the commands directly. Rerunning the start script after an earlier initialization
printed `already initialized`; the member-health output and completed seed confirmed that the replica set was already
healthy.

The failover exercise took about three seconds to elect a new primary after a clean shutdown, and the old primary
rejoined and caught up. The result that surprised me most was Demo 04: the single remaining member could still serve
the tested read, but refused the write after losing its majority. I would keep stock reads on the primary because stale
secondary reads could lead to overselling. Running three members on separate ports and data directories demonstrated
member failure and recovery, but not independent hardware or a real network partition.
