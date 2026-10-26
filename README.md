# DBMS-PROJECT — Travel Itinerary and Expense Organizer

A MySQL relational database (`travel_itinerary_db`) that lets travellers plan trips
day by day, track bookings and expenses, split group costs, and reserve hotel rooms
with payments and reviews. Built for MySQL 8.0.16+ / 8.4 LTS and MySQL Workbench.

## Contents

| File | What it is |
|------|------------|
| `01_travel_itinerary_v2_full.sql` | Base schema: 21 tables, 27 FKs, 12 triggers, 1 view, 2 procedures, 312 sample rows |
| `02_demo_queries.sql` | Demo: 12 queries (Q1–Q12), 14 rule tests (C1–C14), procedure demo (D1–D5) |
| `03_transport_module.sql` | Transport module: +9 tables, +13 FKs, +12 triggers, +1 view |
| `04_transport_demo.sql` | Transport demo: 7 queries (T1–T7), 10 rule tests (X1–X10) |
| `05_smart_features.sql` | Smart layer: audit log + budget alerts: +2 tables, +1 FK, +7 triggers, +2 views |
| `06_demo_amenities_views_triggers.sql` | Amenities, dashboard views, alerts and audit-trail demo (A1–A4, B1–B2, C1–C4, D) |
| `FEASIBILITY.pdf` | Project plan, design decisions and expected outputs |
| `feasibility_plan_source.html` | Editable HTML source the PDF is generated from |

## How to run

Run the scripts **in order** in MySQL Workbench (File → Open SQL Script → lightning bolt).
Each script ends with a quick-check grid that is the acceptance test.

```
01_travel_itinerary_v2_full.sql   ->  tables 21, foreign keys 27, triggers 12, views 1
03_transport_module.sql           ->  tables 30, foreign keys 40, triggers 24, views 2
05_smart_features.sql             ->  tables 32, foreign keys 41, triggers 31, views 4
```

The demo scripts (`02`, `04`, `06`) are run **statement by statement** (Ctrl+Enter /
Cmd+Enter) and are not part of the build. Their sections that deliberately trigger errors
must be run one statement at a time; the MySQL CLI stops at the first error otherwise.

- `02` — Sections A and B: queries. Section C: 14 rule tests, each rejected on purpose.
  Section D: stored procedures.
- `04` — Sections A and B: transport queries. Section C: 10 rule tests (X1–X10).
- `06` — Section A: amenities. Section B: dashboard views. Section C: budget alerts and
  audit trail (inside a transaction that is rolled back). Section D: trigger source.

### Re-running

All scripts are safe to re-run. Note that `03` drops the views and audit triggers that
`05` creates (they depend on the transport tables), so **after re-running `03` you must
re-run `05`**. `01` starts with `DROP DATABASE`, so it rebuilds everything from scratch.

## Schema at a glance

Modules and their tables:

- **People:** `users`
- **Catalogue:** `destinations`, `places`, `activity_categories`, `expense_categories`, `amenities`
- **Trip planning:** `trips`, `trip_members`, `itinerary_days`, `itinerary_items`, `bookings`
- **Money:** `expenses`
- **Community:** `reviews`, `saved_destinations`
- **Hotel module:** `hotels`, `hotel_amenities`, `room_types`, `rooms`, `hotel_reservations`, `hotel_payments`, `hotel_reviews`
- **Transport module (03):** `transport_bookings`, `flight_details`, `train_details`, `cab_details`, `bus_details`, `metro_details`, `transport_passengers`, `carriers`, `stations`
- **Smart layer (05):** `audit_log`, `trip_alerts`

Design highlights:

- **IS-A modelling:** `hotels.hotel_id` is both the primary key and a foreign key to
  `places.place_id`. The same pattern drives `transport_bookings` (supertype) with five
  mode-specific subtype tables.
- **Weak entities:** `hotel_payments`, `hotel_reviews`, `transport_passengers`.
- **Composite foreign key:** `rooms (room_type_id, hotel_id)` → `room_types`.
- **Normalised to 3NF:** derived values (nights, totals, balance due, remaining budget)
  are never stored; they are computed in the views.
- **Rules in the database:** 31 triggers enforce business rules regardless of which tool
  writes the data. `ON DELETE` is CASCADE for owned children, RESTRICT for shared master
  data and SET NULL for optional links.

## Views

- `v_reservation_summary` — nights, total cost, amount paid and balance due per reservation
- `v_trip_transport` — one row per transport leg with route and duration
- `v_trip_timeline` — one chronological list of transport, hotel and activity events
- `v_trip_cost_summary` — booked value versus actual spend versus budget per trip

## Stored procedures

- `sp_create_trip(owner, title, start, end, budget, OUT trip_id)` — creates the trip,
  the owner's membership and one itinerary day per date, in a single transaction
- `sp_book_room(trip, room, booker, check_in, check_out, guests, OUT reservation_id)` —
  locks the room row, inserts the reservation and assigns a confirmation code

## Verified

Validated against MySQL 8.4.13: every acceptance count matches, all rule tests in `02`,
`04` and `06` are rejected as expected, the CASCADE/SET NULL behaviour works, both
procedures run, and the audit and budget-alert triggers fire correctly. All scripts are
idempotent — re-running `03` then `05` reproduces the same object counts.
