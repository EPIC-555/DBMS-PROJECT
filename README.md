# DBMS-PROJECT â€” Travel Itinerary and Expense Organizer

A MySQL relational database (`travel_itinerary_db`) that lets travellers plan trips
day by day, track bookings and expenses, split group costs, and reserve hotel rooms
with payments and reviews. Built for MySQL 8.0.16+ / 8.4 LTS and MySQL Workbench.

## Contents

| File | What it is |
|------|------------|
| `01_travel_itinerary_v2_full.sql` | Base schema: 21 tables, 27 FKs, 12 triggers, 1 view, 2 procedures, 312 sample rows |
| `02_demo_queries.sql` | Demo: 12 queries (Q1â€“Q12), 14 rule tests (C1â€“C14), procedure demo (D1â€“D5) |
| `03_transport_module.sql` | Transport module: +9 tables, +13 FKs, +12 triggers, +1 view |
| `05_smart_features.sql` | Smart layer: audit log + budget alerts: +2 tables, +1 FK, +7 triggers, +2 views |
| `Feasibility Study and Implementation Plan ... .pdf` | Project plan, design decisions and expected outputs |

## How to run

Run the scripts **in order** in MySQL Workbench (File â†’ Open SQL Script â†’ lightning bolt).
Each script ends with a quick-check grid that is the acceptance test.

```
01_travel_itinerary_v2_full.sql   ->  tables 21, foreign keys 27, triggers 12, views 1
03_transport_module.sql           ->  tables 30, foreign keys 40, triggers 24, views 2
05_smart_features.sql             ->  tables 32, foreign keys 41, triggers 31, views 4
02_demo_queries.sql               ->  run section by section (Ctrl+Enter / Cmd+Enter)
```

For `02`, run Sections A and B statement by statement and compare the result grids
with the expected outputs in the PDF. Section C deliberately fails on every statement
(the database rejecting bad data); run it one statement at a time. Section D calls the
stored procedures.

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
- **Composite foreign key:** `rooms (room_type_id, hotel_id)` â†’ `room_types`.
- **Normalised to 3NF:** derived values (nights, totals, balance due, remaining budget)
  are never stored; they are computed in the views.
- **Rules in the database:** 31 triggers enforce business rules regardless of which tool
  writes the data. `ON DELETE` is CASCADE for owned children, RESTRICT for shared master
  data and SET NULL for optional links.

## Views

- `v_reservation_summary` â€” nights, total cost, amount paid and balance due per reservation
- `v_trip_transport` â€” one row per transport leg with route and duration
- `v_trip_timeline` â€” one chronological list of transport, hotel and activity events
- `v_trip_cost_summary` â€” booked value versus actual spend versus budget per trip

## Stored procedures

- `sp_create_trip(owner, title, start, end, budget, OUT trip_id)` â€” creates the trip,
  the owner's membership and one itinerary day per date, in a single transaction
- `sp_book_room(trip, room, booker, check_in, check_out, guests, OUT reservation_id)` â€”
  locks the room row, inserts the reservation and assigns a confirmation code

## Verified

Validated against MySQL 8.4.13: every acceptance count matches, all 14 rule tests are
rejected as expected, the CASCADE/SET NULL behaviour works, both procedures run, and the
audit and budget-alert triggers fire correctly.
