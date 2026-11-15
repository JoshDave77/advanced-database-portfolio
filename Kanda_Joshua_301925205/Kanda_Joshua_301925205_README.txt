MIT 8103 ADVANCED DATABASE SYSTEMS
INDIVIDUAL PRACTICAL DATABASE PORTFOLIO

Student: Kanda Joshua
Student ID: 301925205
Session: 2026/2027 First Semester
Institution: Miva Open University

1. SELECTED ORGANISATION AND SCOPE

I selected Josh Kay's Fisheries as my case study. It is a simulated small business selling fresh and smoked catfish across Abuja, Lagos, Jos and Kaduna, not a claim about a registered company.

I designed the database to support the owner/administrator, sales staff, packers, delivery riders and customers. I modelled customer, product, batch, staff, stock movement, order, payment, delivery and delivery-zone information. The main operations I covered were recording stock, placing orders, processing payments, assigning deliveries, tracking delivery status and generating sales and inventory reports. I used synthetic data throughout the practical exercises.

2. PORTFOLIO ACTIVITIES AND RESULTS

Portfolio 1: Database Design and Modelling

I designed a relational PostgreSQL database consisting of ten tables: delivery_zone, staff, customer, product, batch, orders, order_item, stock_movement, payment and delivery. I used primary keys, foreign keys and CHECK constraints to enforce important business rules.

I used a normalisation walkthrough to cover first, second and third normal forms. I separated product and customer information to reduce unnecessary duplication. I retained the product's cached stock balance as a deliberate denormalisation and used stock movements as the inventory ledger. I also stored the sale-time unit price on each order item so later catalogue price changes would not rewrite order history.

Portfolio 2: Query Processing and Optimisation

I used PostgreSQL 18.6 and generated synthetic data consisting of 2,000 customers, 16 products, 50,000 orders, 125,000 order lines, approximately 123,000 stock movements and approximately 48,000 payment and delivery records.

I evaluated five business queries with EXPLAIN ANALYZE before and after adding indexes. In one warm local run, customer history improved from 5.466 ms to 0.791 ms, while stock history improved from 23.086 ms to 3.533 ms. The other three queries improved by approximately 1.12x to 1.40x.

I saw the largest improvements in queries with selective filters. Monthly revenue and revenue by zone still scanned the order-item table because they required substantial aggregation. These measurements represent one local run, not guaranteed production performance. I also considered the storage and write-maintenance costs of indexes.

Portfolio 3: Transactions and Concurrency

Using two PostgreSQL sessions, I demonstrated COMMIT, ROLLBACK and competing sales for the last available unit of stock.

In the unsafe example, both sessions read a stock balance of one and wrote back an application-calculated balance of zero. Both sales committed, leaving the cached balance at zero while the stock movement ledger total became negative one.

I then demonstrated two corrective approaches. SELECT FOR UPDATE made the second session wait and then observe zero stock, while REPEATABLE READ produced a serialization error requiring a transaction retry.

I also demonstrated a non-repeatable read under READ COMMITTED: the price changed from 7,920 to 8,420 between reads. Under REPEATABLE READ, the second read retained the original value of 7,920.

Portfolio 4: NoSQL and Advanced Data Models

I implemented a MongoDB version of the fisheries database using MongoDB Server 9.0.8 and mongosh 2.14.2. My synthetic dataset contained 16 products, 500 customers, 10,000 orders and 24,669 stock movements.

I embedded order items, payments, delivery details and customer-at-order-time information in order documents because I commonly retrieve these details together. I kept products and the growing stock-movement history in separate collections.

I ran eight examples involving reads, updates, aggregations, $lookup and schema validation. After indexing, the documents examined in three tested queries decreased from 10,000 to 21, 19 and 38 respectively.

Although measured execution times increased in this run, I used the explain plans and document-examination counts as evidence of reduced document-scanning work. This exercise helped me understand the trade-offs between document-oriented convenience, duplication and data consistency.

Portfolio 5: Distributed and Cloud Database Exercise

I configured a three-member MongoDB replica set on one computer to demonstrate replication, failover and loss of majority availability.

My majority-acknowledged write became visible on all three members. During failover, the primary changed from port 27019 to port 27018 in approximately three seconds. My majority write and an order read continued to work with two of the three members available, and the former primary later rejoined as a secondary.

When only one member remained, the database rejected my write attempt with "not primary", while a read still returned 10,000 orders. After I restored the other members, port 27020 became primary.

This exercise demonstrated replica-set recovery and the limitations of write availability under the conditions I tested. However, I ran all members on one computer, so I did not test independent hardware failures or a genuine network partition. I did not implement sharding, MongoDB Atlas deployment or PostgreSQL replication.

3. INDIVIDUAL TECHNICAL REFLECTION

This portfolio helped me understand that data integrity, query efficiency and availability are related but different database design objectives.

The concurrency exercises showed me that a database constraint alone does not make a multi-step sale safe. I need transactions and an appropriate locking or isolation strategy to prevent inconsistent stock updates.

The query optimisation exercises showed me why I should select indexes according to actual query patterns and evaluate their storage and write costs.

The MongoDB exercises helped me understand the convenience of embedding related order information and the associated duplication and consistency trade-offs. The replica-set exercise demonstrated recovery from a member failure, but also showed me the limitations of running all members on one computer.

I also encountered practical configuration challenges involving executable paths containing spaces in Git Bash and shell-script quoting. Working through these issues improved my understanding of command execution and local database environment configuration.

Overall, these exercises strengthened my understanding of relational modelling, transaction management, indexing, document databases and database availability.

4. GITHUB REPOSITORY AND EVIDENCE

Repository: https://github.com/JoshDave77/advanced-database-portfolio

I have made the repository public so it can be accessed without a GitHub account. It contains my five portfolio folders, database scripts, schemas, README files and supporting evidence. I organised screenshots, execution plans and other practical evidence in the respective portfolio evidence folders. I will confirm assessor access before submission.

5. AI-USE DECLARATION

I used Claude (Anthropic), through claude.ai, and an AI assistant through Copilot SDK in VS Code. Claude helped me develop the case-study design, draft SQL, MongoDB and shell scripts and README templates, explain concepts, guide setup, review documentation and outline this summary. Copilot helped me troubleshoot commands and scripts, correct shell quoting, add readiness timeouts, explain concepts and edit documentation.

I ran the database exercises myself, checked results against terminal outputs and saved evidence, replaced template figures with results from my runs, and checked changed shell scripts using bash -n. I am responsible for the accuracy of this document and can explain the submitted database designs, scripts and results.

6. REFERENCES

1. Miva Open University. (2026/2027). MIT 8103 Advanced Database Systems: Individual Practical Database Portfolio. First Semester Continuous Assessment.
2. PostgreSQL Global Development Group. PostgreSQL 18 Documentation: Transaction Isolation. https://www.postgresql.org/docs/18/transaction-iso.html
3. MongoDB, Inc. MongoDB Manual: Data Modelling. https://www.mongodb.com/docs/manual/data-modeling/
4. MongoDB, Inc. MongoDB Manual: Replication. https://www.mongodb.com/docs/manual/replication/
5. MongoDB, Inc. MongoDB Manual: Write Concern. https://www.mongodb.com/docs/manual/reference/write-concern/
6. MongoDB, Inc. MongoDB Manual: Explain Results. https://www.mongodb.com/docs/manual/reference/explain-results/
7. MongoDB, Inc. MongoDB Manual: Read Preference. https://www.mongodb.com/docs/manual/core/read-preference/
8. PostgreSQL Global Development Group. PostgreSQL 18 Documentation: Using EXPLAIN. https://www.postgresql.org/docs/18/using-explain.html
9. PostgreSQL Global Development Group. PostgreSQL 18 Documentation: Indexes. https://www.postgresql.org/docs/18/indexes.html
10. MongoDB, Inc. MongoDB Manual: Schema Validation. https://www.mongodb.com/docs/manual/core/schema-validation/
