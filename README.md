# Travel Itinerary and Expense Organizer

A relational database project in **MySQL / MySQL Workbench** for a team of three. Travellers plan a trip day by day, book hotels, flights, trains, cabs, buses and metro, split costs fairly, and watch the budget. The database enforces its own business rules with triggers, constraints and stored procedures.

| Final database | |
|---|---|
| Tables | 32 |
| Foreign keys | 41 (each with an explicit ON DELETE / ON UPDATE rule) |
| Triggers | 31 (18 families: 24 BEFORE, 7 AFTER) |
| Views | 4 |
| Stored procedures | 2 |
| CHECK constraints | 26 |
| UNIQUE keys | 19 |
| Sample rows | 399 (30 tables loaded; `audit_log` and `trip_alerts` fill when triggers fire) |
| Named demo queries | 25, plus about 30 rule and trigger tests |

> **Status.** The SQL was verified by a separate simulation of every constraint and trigger rule, but it has not yet been executed on the team's own MySQL server. **Day-one acceptance test:** run `sql/00_build_everything.sql` and check that the last result grid shows `tables 32, foreign keys 41, triggers 31, views 4`.

---

## 1. Repository layout

```
travel-itinerary-db/
  README.md                        this file: the project handbook
  sql/
    00_build_everything.sql        one-click build = 01 + 03 + 05
    01_travel_itinerary_v2_full.sql core schema + hotel module + 12 triggers + 2 procedures + data
    03_transport_module.sql         flights, trains, cabs, buses, metro + 12 triggers + data
    05_smart_features.sql           audit_log, trip_alerts, 7 AFTER triggers, 2 dashboard views
  demo/
    02_demo_queries.sql             Q1-Q12, core rule tests C1-C14, procedure demo
    04_transport_demo.sql           T1-T7, transport rule tests X1-X12
    06_demo_amenities_views_triggers.sql  amenities A1-A4, views B1-B2, alert + audit demo C1-C4
  docs/
    Tech_Stack_and_Roadmap.pdf      technology stack, architecture, roadmap
    (report, EER diagram image, screenshots, data dictionary)
  app/                             optional Streamlit app (Phase 4)
```

## 2. How to run it

**Prerequisite: a MySQL server must be running.** Workbench is only a client. If Workbench says "Unable to connect to 127.0.0.1:3306", the server is not installed or not started (press Win+R, run `services.msc`, start the MySQL service, or install MySQL Server 8.4 LTS with the MySQL Installer).

1. Open MySQL Workbench and connect to `127.0.0.1:3306` as `root`.
2. `File > Open SQL Script` and choose `sql/00_build_everything.sql`.
3. Press the lightning-bolt button once. The script drops and rebuilds `travel_itinerary_db`.
4. The last grid must show: **32 tables, 41 foreign keys, 31 triggers, 4 views.** Refresh the Schemas panel.
5. For the demos, open a file from `demo/`, click inside one statement and press **Ctrl+Enter** to run only that statement. Take a screenshot of every result.

Demo order and what to expect:

| Order | File | Run after | Expected |
|---|---|---|---|
| 1 | `demo/02_demo_queries.sql` | `01` (or any later script) | Its Section A shows 21/27/12 only if run right after `01`; after the full build it shows 32/41/31, which is correct |
| 2 | `demo/04_transport_demo.sql` | `03` | Expected results are written in the comments |
| 3 | `demo/06_demo_amenities_views_triggers.sql` | `05` | Quick check 32/41/31/4, then amenities, dashboards, alerts |

Re-running `01` rebuilds everything, so run `03` and `05` again afterwards (or just run `00`). Re-running `03` requires running `05` again.

**EER diagram:** `Database > Reverse Engineer`, choose `travel_itinerary_db`, then `File > Export` as PNG or PDF. Workbench draws an IS-A link as a one-to-one relationship, so label the subtype tables on the exported image. The new Workbench 26.x line may not include the EER editor; if the menu is missing, use classic Workbench 8.0.x only for the diagram.

**Troubleshooting**

| Message | Fix |
|---|---|
| Error 1419 (SUPER privilege) | Use `root`, or `SET GLOBAL log_bin_trust_function_creators = 1;` |
| Error 1064 near DELIMITER | Run the script in Workbench, not another client |
| Error 1215 (cannot add foreign key) | A script was run out of order; run `00_build_everything.sql` |
| Error 1046 (no database selected) | `USE travel_itinerary_db;` |
| Error 1175 (safe update mode) | `SET SQL_SAFE_UPDATES = 0;` |
| CHECK not enforced | MySQL is older than 8.0.16; use 8.4 LTS |

---

## 3. Architecture in three modules

| Module | Script | Tables | Triggers | Owner |
|---|---|---|---|---|
| **Core + hotels**: users, destinations, places, trips, itinerary, bookings, expenses, reviews, hotels, amenities, rooms, reservations, payments | `01` | 21 | 12 BEFORE | Member A |
| **Transport**: flights, trains, cabs, buses, metro (public transport) | `03` | 9 | 12 BEFORE | Member B |
| **Smart layer**: audit trail, budget alerts, dashboards | `05` | 2 | 7 AFTER | Member C |

## 4. The 32 tables

### Core and hotels (21)

| Table | Purpose and key design point |
|---|---|
| `users` | App users; unique e-mail; role user/admin |
| `destinations` | Cities or regions; unique (name, country) |
| `places` | Attractions, hotels, restaurants inside a destination; FK to destinations (RESTRICT) |
| `activity_categories` | Lookup: Sightseeing, Food, Adventure, Transport, ... |
| `expense_categories` | Lookup: Transport, Food, Stay, ... |
| `amenities` | **Lookup of hotel facilities** (Wi-Fi, Pool, Spa, ...), each stored once |
| `trips` | A trip with dates, budget and status; owner is a user (RESTRICT) |
| `trip_members` | M:N users to trips with a role (owner, editor, viewer) |
| `itinerary_days` | One row per date of a trip; unique (trip, date) and (trip, day number) |
| `itinerary_items` | Timed activities of a day; category RESTRICT, place SET NULL |
| `bookings` | Activity tickets, at most one per itinerary item |
| `expenses` | Money spent; optionally linked to an itinerary item; payer RESTRICT |
| `reviews` | User rating of a destination; key (user, destination) |
| `saved_destinations` | Wish list; key (user, destination) |
| `hotels` | **IS-A subtype of places** (hotel_id is primary key and foreign key) |
| `hotel_amenities` | **M:N link hotels to amenities, with attribute `is_complimentary`** |
| `room_types` | Types per hotel; unique (hotel, name) and (room_type_id, hotel_id) |
| `rooms` | Physical rooms; **composite FK** (room_type_id, hotel_id) |
| `hotel_reservations` | Stays; `rate_per_night` is a price snapshot |
| `hotel_payments` | **Weak entity**, key (reservation_id, payment_no) |
| `hotel_reviews` | **Weak entity**, one review per reservation |

### Transport (9)

| Table | Purpose and key design point |
|---|---|
| `carriers` | Airlines, railways, cab operators, bus operators, metro operators |
| `stations` | Airports, railway stations, bus stands, metro stations |
| `transport_bookings` | **Supertype**: one row per leg (mode, carrier, times, fare, status) |
| `flight_details` | Subtype: flight number, cabin class, terminal, baggage |
| `train_details` | Subtype: train number and name, class, coach |
| `cab_details` | Subtype: vehicle, driver, pickup and drop address, distance |
| `bus_details` | Subtype: bus type and number |
| `metro_details` | Subtype: line, ticket type, number of stops |
| `transport_passengers` | **Weak entity**, key (transport_id, passenger_no); unique seat per booking |

### Smart layer (2)

| Table | Purpose |
|---|---|
| `audit_log` | Who changed what, from which value to which value (filled by AFTER triggers) |
| `trip_alerts` | `budget_80` and `budget_exceeded` alerts, at most one of each per trip |

### Views and procedures

| Object | What it does |
|---|---|
| `v_reservation_summary` | Nights, total cost, amount paid and balance due per hotel reservation |
| `v_trip_transport` | Every transport leg with route, duration, passengers and fare |
| `v_trip_timeline` | One chronological list of transport, hotel check-in/out and activities |
| `v_trip_cost_summary` | Budget versus booked versus actually spent |
| `sp_create_trip` | Transaction: trip + owner membership + one row per day |
| `sp_book_room` | Transaction: lock the room (`SELECT ... FOR UPDATE`), insert, set confirmation code |

### Referential-action policy

* **CASCADE** for data a parent owns: a trip's days, items, legs, reservations; a reservation's payments.
* **RESTRICT** for shared reference data: a carrier or category in use, a user who owns trips.
* **SET NULL** for optional links: an itinerary item or place that is deleted keeps its bookings and expenses.

---

## 5. The role of the Amenities table

* `amenities` is a **strong lookup entity**: the master list of facilities, each stored once.
* `hotel_amenities` is the **associative entity** that resolves the many-to-many relationship between hotels and amenities. Key: (hotel_id, amenity_id). Both foreign keys are `ON DELETE CASCADE`.
* `is_complimentary` sits **on the link**, not on either table, because it depends on the pair: Wi-Fi can be free at one hotel and paid at another.
* Both sides are optional. In the sample data, Gym is offered by no hotel.

```
hotels 1 --- N hotel_amenities N --- 1 amenities
               (hotel_id, amenity_id, is_complimentary)
```

If a reference PDF describes amenities differently, the usual variants are: (1) hotel-level junction table, **implemented**; (2) amenities attached to room types, which would add `room_type_amenities (room_type_id, amenity_id)`; (3) amenities as a text column in `hotels`, which breaks first normal form. Say clearly in the viva that the submitted ER diagram is the final design and the implementation follows it. Demo `06` Section A has four amenity queries.

---

## 6. Triggers (31 triggers, 18 families)

A trigger is a small program stored in the database that MySQL runs automatically when a row is inserted, updated or deleted. A **BEFORE** trigger checks the row and can reject it with `SIGNAL SQLSTATE '45000'`. An **AFTER** trigger reacts once the row is saved, for example by writing an audit entry.

Why triggers when CHECK and foreign keys exist? CHECK sees only the columns of its own row, and a foreign key only proves that a row exists. Rules that need other rows or tables need a trigger.

| No. | Family | Table and event | Rule in plain English | Demo test |
|---|---|---|---|---|
| 1 | `trg_exp_item_trip` | expenses, BEFORE insert/update | An expense linked to an itinerary item must belong to the same trip | 02 C9 |
| 2 | `trg_hotels_place_type` | hotels, BEFORE | A hotel row must point at a place of type Hotel | 02 C10 |
| 3 | `trg_res_validate` | hotel_reservations, BEFORE | Room not in maintenance; guests fit the room type; stay inside trip dates; booker is owner or editor; no overlapping booking of the same room | 02 C3-C7, D3 |
| 4 | `trg_hreview_completed` | hotel_reviews, BEFORE | Only a completed stay can be reviewed | 02 C8 |
| 5 | `trg_days_validate` | itinerary_days, BEFORE | `day_date` = trip start + day_number - 1 and not after the trip end | 02 C2 |
| 6 | `trg_items_no_overlap` | itinerary_items, BEFORE | Timed activities on one day must not overlap | 02 C1 |
| 7 | `trg_transport_validate` | transport_bookings, BEFORE | Carrier type matches the mode; every mode except cab needs two different stations of the right kind; linked item belongs to the same trip; booker is owner or editor | 04 X1-X4, X6, X7 |
| 8-12 | `trg_flight_mode`, `trg_train_mode`, `trg_cab_mode`, `trg_bus_mode`, `trg_metro_mode` | the five subtype tables, BEFORE | A subtype row may exist only for a booking of the matching mode | 04 X8 |
| 13 | `trg_trips_audit_au` | trips, AFTER update | Log changes of budget and status | 06 C4 |
| 14 | `trg_res_audit_au` | hotel_reservations, AFTER update | Log status changes | 06 C4 |
| 15 | `trg_transport_audit_au` | transport_bookings, AFTER update | Log status changes | 06 C4 |
| 16 | `trg_exp_audit_au` | expenses, AFTER update | Log amount changes | 06 C4 |
| 17 | `trg_exp_audit_ad` | expenses, AFTER delete | Log the deleted amount | 06 C4 |
| 18 | `trg_exp_budget_alert_ai` / `_au` | expenses, AFTER insert/update | At 80 percent of the budget, or above it, raise one alert of that type per trip | 06 C1-C3 |

Count: 12 core + 12 transport + 7 smart = **31**. Every BEFORE family has an insert trigger (`_bi`) and an update trigger (`_bu`) with the same body.

**Overlap rule used twice** (activities and room bookings): two ranges overlap when `new_start < other_end AND new_end > other_start`. The comparison is strict, so back-to-back items and a check-in on another guest's check-out day are allowed.

**Prompt to ask an AI to explain a trigger.** Copy the source with `SHOW CREATE TRIGGER trg_res_validate_bi;` and give:

```
You are a database teacher. Explain this MySQL trigger to a second-year student in simple
English. Cover: 1) when it fires (table, BEFORE or AFTER, INSERT/UPDATE/DELETE), 2) what it
checks or does, step by step, 3) what error or side effect the user sees, 4) one example that
passes and one that fails, 5) why a CHECK constraint or foreign key cannot do the same job.
Keep it under 200 words. Trigger source: <paste here>
```

Always verify an AI explanation by running the matching rule test; it is a draft, not proof.

---

## 7. Sample data (399 rows)

Five fictional trips, six users, 24 places, 8 hotels, 32 rooms, 8 hotel reservations, 14 transport legs (3 flights, 1 train, 5 cabs, 3 buses, 2 metro) with 33 passengers.

| Trip | Dates | Status | Budget (Rs) | What it demonstrates |
|---|---|---|---|---|
| Goa Beach Escape | 26-30 Dec 2026 | planned | 60,000 | 2 flights, 2 airport cabs, a city bus; confirmed + cancelled reservation; a failed payment |
| Rajasthan Heritage Tour | 10-14 Nov 2026 | planned | 85,000 | Train, Jaipur metro, intercity cab, pending flight; two hotels |
| Munnar Monsoon Getaway | 14-17 Aug 2026 | completed | 40,000 | Settlement query, cab legs, hotel review |
| Hampi and Coorg Road Trip | 19-23 Oct 2026 | ongoing | 35,000 | Self-drive (no transport bookings); budget alert demo |
| Manali Winter Break | 8-12 Jan 2027 | planned | 50,000 | Delhi metro, Volvo bus both ways; cascade-delete demo |

All people, hotels, drivers and phone numbers are fictional. Carrier and station names are real organisations used as illustrative labels; **every time, number and fare is sample data, not a live schedule or price.** Demo passwords are SHA2 hashes only.

## 8. Queries (25) and key expected results

| File | Queries |
|---|---|
| `02` | Q1 day-wise itinerary; Q2 budget vs actual; Q3 spend by category; Q4 settlement; Q5 reservation view; Q6 free rooms (NOT EXISTS); Q7 hotel performance; Q8 best destinations (HAVING); Q9 running total (window function); Q10 members (GROUP_CONCAT); Q11 unbooked items; Q12 owner-is-member integrity |
| `04` | T1 legs of a trip; T2 spend by mode; T3 passenger manifest; T4 items with no booking; T5 fare per passenger by mode; T6 public vs cab vs air (CASE); T7 transport share of budget |
| `06` | A1 amenity usage; A2 free Wi-Fi and parking (HAVING COUNT DISTINCT); A3 amenities per hotel; A4 CASCADE; B1 trip timeline (view); B2 budget dashboard (view) |

Key expected results (computed from the data):

* **Q2 budget vs actual:** Goa 60,000 / 30,000 / 30,000; Rajasthan 85,000 / 14,600 / 70,400; Munnar 40,000 / 30,600 / 9,400; Hampi 35,000 / 22,100 / 12,900; Manali 50,000 / 5,500 / 44,500.
* **Q4 settlement, Munnar (10,200 each):** Sneha paid 21,900 (+11,700); Karthik 6,000 (-4,200); Ananya 2,700 (-7,500).
* **Q6:** six free Goa rooms for 26-29 Dec (Seaside Palms 101 and 202; Casa Azul 101, 102, 201, 202).
* **T5 fare per passenger:** flight 4,000.00; cab 1,092.31; bus 840.00; train 1,000.00; metro 18.00.
* **B2 dashboard:** Goa booked 45,240 (75.4% of budget); Rajasthan 37,630 (44.3%); Munnar 20,500 (51.3%); Hampi 14,000 (40.0%); Manali 17,060 (34.1%).
* **Alerts (06 C1-C3):** adding 10,000 to the Hampi trip raises `budget_80` (32,100 of 35,000); a further 5,000 raises `budget_exceeded` (37,100); a third expense creates no duplicate.

---

## 9. Technology stack (details in `docs/Tech_Stack_and_Roadmap.pdf`)

| Layer | Choice | Status |
|---|---|---|
| Database | MySQL Community Server 8.4 LTS, InnoDB, utf8mb4 (8.0 reached end of life in April 2026) | Required |
| Client and modelling | MySQL Workbench | Required |
| Language | SQL, MySQL dialect (DDL, DML, DQL, TCL, triggers, procedures, views) | Required |
| Version control | Git and GitHub | Required |
| App (stretch) | Python 3.12, Streamlit, mysql-connector-python, pandas, Plotly, python-dotenv | Optional |
| Reproducible setup | Docker Compose with `mysql:8.4` | Optional |
| AI trigger explainer | Claude API via the `anthropic` package | Optional |

Why: the database does the work (rules in the database apply to every client); everything is free; plain SQL is easy to explain; the core needs no second language or server.

## 10. How we divide the work (three members)

| | Member A: Core and hotels | Member B: Transport | Member C: Smart layer, queries, report |
|---|---|---|---|
| Owns | `sql/01`, 21 tables, 12 triggers, 2 procedures | `sql/03`, 9 tables, 12 triggers, `v_trip_transport` | `sql/05`, 2 tables, 7 AFTER triggers, 2 views, queries |
| Builds | Verify the schema against the ER diagram column by column; EER diagram; data dictionary (core); Git owner | Verify transport rules and data; data dictionary (transport); transport demo | Alerts and audit demo; dashboards; report; slides; optional Streamlit app |
| Presents in the viva | ER diagram, IS-A, weak entities, composite key, **amenities**, hotel triggers, hotel booking demo | Supertype and subtypes, **public transport**, transport triggers and demo | Views, **AFTER triggers**, alerts and audit demo, query results |
| Reviews | Member B's SQL | Member C's SQL | Member A's SQL |

**Rules:** one Git branch per member, merge by pull request; a 15-minute sync every second day; nobody edits another member's script without telling the owner; every member must be able to explain all 18 trigger families at overview level.

| Phase | Days | Goal | Done when |
|---|---|---|---|
| 0 Setup | 1-2 | MySQL running, Workbench connected, repo cloned | `00_build_everything.sql` runs on every laptop |
| 1 Core + hotels | 2-3 | Compare tables with the ER diagram | A signs off |
| 2 Transport + smart layer | 3-5 | Read and test every trigger of your module | Quick check 32 / 41 / 31 / 4 |
| 3 Testing + evidence | 5-8 | Run all demo files, screenshots, EER export | Every expected result matches |
| 4 App (optional) | 8-12 | Streamlit dashboard, booking form, Rule Lab, AI explainer | App runs from a clean clone |
| 5 Report + viva | 12-14 | Report, slides, rehearsal on a clean laptop | Demo runs in 12 minutes without errors |

## 11. Feasibility (short)

| Area | Verdict | Why |
|---|---|---|
| Technical | Feasible | Every feature (keys, CHECK, triggers with SIGNAL, views, transactions, row locking) exists natively in MySQL |
| Operational | Feasible | Three laptops with MySQL Server and Workbench; setup under 30 minutes; scripts rebuild from scratch |
| Economic | Feasible, Rs 0 | All tools are free; only the optional AI explainer needs an API key |
| Schedule | Feasible | Database layer is scripted; remaining work is running, screenshots, report, rehearsal (about 14 days, fewer without the app) |
| Data and legal | Feasible | Fictional sample data; no real personal data; no card numbers stored |

Main risks: server not running or version mismatch (check on day one), scripts run out of order (use `00_build_everything.sql`), team members editing the same script (one owner per module, pull requests).

## 12. What to explain to the professor

**The five-minute story** (in this order):

1. **Problem.** Groups plan trips across many bookings and share costs; data is scattered and rules are easy to break.
2. **Design.** 32 tables in three modules. Show the EER diagram. Point out IS-A (places to hotels, transport to five subtypes), weak entities (payments, reviews, passengers), the composite foreign key, and the amenities junction table.
3. **Rules inside the database.** 31 triggers. BEFORE triggers reject bad data (double booking, overlapping activities, wrong carrier type); AFTER triggers react (audit log, budget alerts). Explain why a CHECK constraint cannot do this.
4. **Live demo (12 minutes).** A: quick check, double booking and capacity rejection, `sp_book_room`, amenities queries. B: T1, T5, T6 and the carrier and station rejections. C: timeline and budget dashboard views, then the alert and audit demo with rollback.
5. **Honesty.** Limitations (below) and what you would do next (indexes from EXPLAIN, role-based accounts, a scheduled event for trip status, the Streamlit app).

**Concepts every member must be able to explain:** ER to relational mapping; strong vs weak entity; IS-A mapping; many-to-many with an attribute; composite key and composite foreign key; CASCADE vs RESTRICT vs SET NULL; why DECIMAL for money; third normal form and derived data in views; BEFORE vs AFTER triggers, `NEW` and `OLD`, `SIGNAL`; transactions and `FOR UPDATE`; why the overlap formula uses strict comparisons.

**Likely questions and short answers**

| Question | Answer |
|---|---|
| Why is `hotels` separate from `places`? | A hotel is a kind of place with extra attributes; the shared key avoids repeating data and a trigger ensures only Hotel places get a hotel row |
| Why is `hotel_payments` a weak entity? | A payment is meaningless without its reservation, so its key includes reservation_id |
| What is the composite foreign key for? | A room can never get a room type of another hotel |
| Why store `rate_per_night` on the reservation? | It freezes the price at booking time |
| Why is `is_complimentary` on `hotel_amenities`? | It depends on the hotel and amenity pair, not on either alone |
| How do you stop two people booking the same room? | `sp_book_room` locks the room row with `FOR UPDATE` inside a transaction, and the validation trigger rejects any overlapping live reservation |
| Trigger or procedure? | A procedure runs only when called; a trigger runs automatically and cannot be bypassed |
| Can a trigger change the table it fires on? | No (error 1442); that is why the alert trigger writes to `trip_alerts` |
| Do cascaded deletes fire triggers? | No, InnoDB cascades do not activate triggers |
| Which normal form? | Third normal form; computed values live in views |

## 13. Limitations

* The SQL has been verified by simulation, not yet by a run on the team's MySQL server (acceptance test: the quick-check counts).
* Demo passwords use SHA2; a real system needs bcrypt or argon2.
* The settlement query splits costs equally among all members, including viewers.
* All times, flight and train numbers and fares are sample values.
* The older generic `bookings` table still holds some records for transport items that are also stored in `transport_bookings`; new transport must go through the transport module.
* Audit triggers record direct updates and deletes only, because cascaded deletes do not fire triggers.
* No multi-currency support and no ferry or tram mode.

## 14. Team checklist

- [ ] MySQL Server 8.4 LTS running on every laptop; Workbench connects
- [ ] `00_build_everything.sql` run; quick check shows 32 / 41 / 31 / 4
- [ ] Member A: schema compared with the ER diagram; EER diagram exported
- [ ] Member B: transport demo (`04`) run; every expected result matched
- [ ] Member C: alert and audit demo (`06`) run; dashboards checked
- [ ] Screenshots of every result saved in `docs/`
- [ ] Data dictionary written (A: core, B: transport, C: smart layer)
- [ ] Report and slides finished; 12-minute demo rehearsed on a clean laptop
- [ ] Optional: Streamlit app and AI trigger explainer

**Team members:** ______________ (A), ______________ (B), ______________ (C)
