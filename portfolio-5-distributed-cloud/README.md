# Portfolio 5: Distributed and Cloud Database Exercise

**Case study:** I used Josh Kay's Fisheries and the same MongoDB data as Portfolio 4.
**What I implemented:** a 3-node MongoDB **replica set** on one computer, with replication, failover and majority-loss demos.
**What I discussed but did not implement:** sharding by delivery zone and PostgreSQL replication.
**Tested on:** I ran the demos with MongoDB Server 9.0.8 and mongosh 2.14.2.

## Why I considered distributing this business's data
I considered orders and payments to be the money record, so losing them or having the order system go down on a busy day
(for example, during a festive season) would be costly. I used replication to keep three copies and keep the service
available after one replica member fails. I ran all three members on one computer, so I did not test a whole-machine
or network failure. I treated sharding as a design exercise rather than a current need because this business is small.

## Files
| File | Purpose |
|---|---|
| `common.sh`, `status.js` | The shared settings and helper functions I used |
| `01_start_replica_set.sh` | I use this to start my 3 members (ports 27018-27020), initiate the set and load the Portfolio 4 data |
| `02_replication_check.sh` | I use this to check my majority-acknowledged write and verify the data counts on each member |
| `03_failover.sh` | I use this to stop my primary, watch the election, write during the outage and restart the old primary |
| `04_majority_loss.sh` | I use this to leave one of my three members running and check that writes are refused while reads still work |
| `05_stop_all.sh` | I use this to stop my replica set (`clean` also deletes `data/` and `logs/`) |
| `evidence/` | My captures from the four local demos |

## How I ran the demos (Git Bash, from this folder)
If `mongod` or `mongosh` are not on your PATH, set their executable paths in Git Bash. These are the paths used for
this run; adjust them if you installed either program elsewhere:
```bash
export MONGOD="$(cygpath -u 'C:\Program Files\MongoDB\Server\9.0\bin\mongod.exe')"
export MONGOSH="$(cygpath -u "$USERPROFILE\Documents\mongosh-2.14.2-win32-x64\mongosh-2.14.2-win32-x64\bin\mongosh.exe")"
"$MONGOD" --version
"$MONGOSH" --version
```
I kept this Git Bash session open so the exported paths remained available to each demo.
```bash
bash 01_start_replica_set.sh
bash 02_replication_check.sh
bash 03_failover.sh
bash 04_majority_loss.sh
bash 05_stop_all.sh
```
I ran the members as background processes. `05_stop_all.sh clean` also deletes `data/` and `logs/`; I omitted `clean`
when I wanted to preserve the data and logs.

## What I observed in each demo
| Demo | Concept | What I observed |
|---|---|---|
| 01 | **Replica-set setup** | I saw one PRIMARY and two SECONDARY members; the set contained 16 products, 500 customers, 10,000 orders and 24,669 stock movements |
| 02 | **Replication, durability** | My `w:"majority"` write was acknowledged; each member reported `orders=10000`, `products=16` and the replicated log entry |
| 03 | **Availability** | I observed an election from port 27019 to 27018 in about 3 seconds; my majority write worked with 2 of 3 members, and the old primary rejoined |
| 04 | **Consistency vs availability (CAP)** | With one of three members left, I saw writes refused (`not primary`) while reads worked, and the set recovered |

In my run, shutting down the primary cleanly led to an election in about **3 seconds**. After Demo 03, each member
reported four `failover_log` entries. In Demo 04, the lone member refused my write but returned `orders=10000` for a read;
after I restarted the other members, port 27020 became PRIMARY. I understand that a real crash may take longer; the
default election timeout is 10 seconds.

## My consistency and availability choices for the fisheries data
| Data | Write concern | Reads from | My reason |
|---|---|---|---|
| Orders, payments | `w: "majority"` | Primary | I would protect these money records through failover and avoid stale reads |
| Stock quantity | `w: "majority"` | **Primary only** | I would avoid stale stock reads that could lead to overselling, as I demonstrated in Portfolio 3 |
| Sales reports, revenue by zone | default | Secondary (`secondaryPreferred`) | I consider a few seconds of delay acceptable for reports, and secondary reads can move load off the primary |
| Product catalogue | `w: 1` is acceptable | Secondary | I consider this reasonable for a catalogue that rarely changes, where fast writes matter more |

## My CAP discussion (demonstrated in Demo 04)
In my test, the remaining member could not form a majority and stepped down as primary. The database refused my write,
while a `secondaryPreferred` read still returned the order count. My test showed that the replica set favoured write
consistency over availability in this failure case; a secondary read can still be stale. For a business taking orders,
I would rather retry a refused order than risk conflicting stock counts.

## Sharding design (NOT implemented, discussion only)
I considered sharding as a way to split data across machines. For `orders`, I compared:
| Shard key | Benefit | Problem |
|---|---|---|
| `{ orderNo: "hashed" }` | Even spread of writes | A report for one zone must ask every shard (scatter-gather) |
| `{ "customer.zone": 1, orderNo: 1 }` | Queries for one zone go to one shard; zone-aware placement is possible (e.g. Lagos data on a Lagos-located shard) | Only 4 zones, so `orderNo` is needed in the key to let chunks split; Lagos could be much busier than the rest; rising `orderNo` makes the newest chunk of each zone a hotspot |
My recommendation for this business is not to shard yet; at the current volume, one replica set is enough. If the
business grew, I would start with the zone-prefixed compound key because most delivery and regional-report queries are
by zone. I would keep unsharded collections such as `products` and `customers` on one shard.

## Cloud deployment: MongoDB Atlas free tier
I did not deploy this project to Atlas. If I extended the work to Atlas, I would follow these steps. Atlas clusters are
replica sets of three nodes managed in the cloud.
1. I would create a free **M0** cluster at cloud.mongodb.com.
2. I would create a database user under **Database Access** and allow my current IP address under **Network Access**.
3. I would copy the connection string from **Connect, Drivers/Shell** and keep its password out of the repository.
4. I would load the data with `"$MONGOSH" "<your Atlas connection string>/fisheries" --file ../portfolio-4-nosql/01_seed.js`
5. I would capture the cluster overview showing its three nodes and a query result from mongosh connected to Atlas.
I used the local replica set as my failover evidence rather than claiming an Atlas failover test.

## PostgreSQL side (discussion only)
I did not implement PostgreSQL replication. For the relational design, I would consider streaming replication: one
primary would take writes, while hot standbys could serve read-only reports and be promoted if the primary failed.

## Evidence checklist
- [x] `01`: I captured three members, one PRIMARY and two SECONDARY (`p5-01-replica-set-start.png`)
- [x] `02`: I captured the same document counts on all three members (`p5-02-replication-check.png`; an additional capture is `p5-02-replication 2-check.png`)
- [x] `03`: I captured the election, write during the outage and old primary rejoining (`p5-03a-failover-election.png`, `p5-03b-failover-recovery.png`)
- [x] `04`: I captured `REFUSED: not primary` and a successful read (`p5-04-majority-loss.png`)
- [ ] I did not capture an Atlas cluster page or query output (optional)

## Technical reflection
I ran the local replica set with MongoDB 9.0.8 and mongosh 2.14.2. Neither executable was on my PATH, so I set
`MONGOD` and `MONGOSH` in Git Bash. The paths contained spaces; quoting the `MONGOSH` variable in the scripts was
necessary for their readiness checks and later demos to work. I also encountered a terminal paste issue that inserted
`[200~` into a command, so I typed the commands directly. Rerunning the start script after an earlier initialization
printed `already initialized`; the member-health output and completed seed confirmed that the replica set was already
healthy.

In my failover exercise, the replica set elected a new primary about three seconds after I shut down the old one cleanly,
and the old primary rejoined and caught up. I was most surprised by Demo 04: the single remaining member still served
the read I tested, but refused my write after losing its majority. I would keep stock reads on the primary because stale
secondary reads could lead to overselling. By running three members on separate ports and data directories, I
demonstrated member failure and recovery, but not independent hardware or a real network partition.
