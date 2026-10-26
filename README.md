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
| `04_transport_demo.sql` | Transport demo: 7 queries (T1â€“T7), 10 rule tests (X1â€“X10) |
| `05_smart_features.sql` | Smart layer: audit log + budget alerts: +2 tables, +1 FK, +7 triggers, +2 views |
| `06_demo_amenities_views_triggers.sql` | Amenities, dashboard views, alerts and audit-trail demo (A1â€“A4, B1â€“B2, C1â€“C4, D) |
| `07_recommendation_engine.sql` | Recommendation layer: trip suggestions from reviews, wishlists, history and season |
| `FEASIBILITY.pdf` | Project plan, design decisions and expected outputs |
| `feasibility_plan_source.html` | Editable HTML source the PDF is generated from |

## How to run

Run the scripts **in order** in MySQL Workbench (File â†’ Open SQL Script â†’ lightning bolt).
Each script ends with a quick-check grid that is the acceptance test.

```
01_travel_itinerary_v2_full.sql   ->  tables 21, foreign keys 27, triggers 12, views 1
03_transport_module.sql           ->  tables 30, foreign keys 40, triggers 24, views 2
05_smart_features.sql             ->  tables 32, foreign keys 41, triggers 31, views 4
07_recommendation_engine.sql      ->  tables 33, foreign keys 42, triggers 31, views 7
```

The demo scripts (`02`, `04`, `06`) are run **statement by statement** (Ctrl+Enter /
Cmd+Enter) and are not part of the build. Their sections that deliberately trigger errors
must be run one statement at a time; the MySQL CLI stops at the first error otherwise.

- `02` â€” Sections A and B: queries. Section C: 14 rule tests, each rejected on purpose.
  Section D: stored procedures.
- `04` â€” Sections A and B: transport queries. Section C: 10 rule tests (X1â€“X10).
- `06` â€” Section A: amenities. Section B: dashboard views. Section C: budget alerts and
  audit trail (inside a transaction that is rolled back). Section D: trigger source.

### Re-running

All scripts are safe to re-run. Note that `03` drops the views and audit triggers that
`05` creates (they depend on the transport tables), so **after re-running `03` you must
re-run `05`**. Run `07` last; it is safe to re-run and its objects survive a `03` re-run.
`01` starts with `DROP DATABASE`, so it rebuilds everything from scratch.

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
- `v_destination_stats` â€” one row per destination: rating, saves, places, hotels, nightly rate, popularity
- `v_user_interest_profile` â€” per user: destinations visited, wishlist backlog, favourite activity categories
- `v_trip_suggestions` â€” per user: ranked destinations they have not visited, with a score and a reason

## Stored procedures

- `sp_create_trip(owner, title, start, end, budget, OUT trip_id)` â€” creates the trip,
  the owner's membership and one itinerary day per date, in a single transaction
- `sp_book_room(trip, room, booker, check_in, check_out, guests, OUT reservation_id)` â€”
  locks the room row, inserts the reservation and assigns a confirmation code
- `sp_suggest_trips(user, travel_month, min_score, limit)` â€” ranked trip suggestions
  for one user, for a chosen month

## Trip suggestions (script 07)

The app suggests where a user should go next. It scores every destination the user
has **not** already visited, out of 100:

| Signal | Points | Source |
|--------|--------|--------|
| Destination quality | up to 30 | average review rating |
| Crowd approval | up to 15 | number of reviews |
| Wishlist interest | up to 15 | how many users saved it |
| Personal taste | up to 20 | the user saved or rated it 4+ |
| In season | up to 20 | `destination_season_months` vs the travel month |

`destinations.best_season` is free text ("November to February"), so script 07 adds a
`destination_season_months` lookup that maps each destination to month numbers. That
makes "what suits me in March?" a plain query.

Each suggestion carries a plain-language `reason`, for example
*"highly rated, already on your wishlist, in season, rooms from 3,800 per night"*.

## API

A small FastAPI service (`app/`) exposes the database. Business rules stay in MySQL;
the API only validates input and shapes JSON.

```bash
pip install -r requirements.txt
cp .env.example .env          # fill in your MySQL settings
uvicorn app.main:app --reload # http://127.0.0.1:8000/docs
```

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/health` | Liveness plus database version |
| GET | `/api/destinations` | All destinations with signals |
| GET | `/api/destinations/{id}` | One destination, its places and season months |
| GET | `/api/users` | Interest profile for every user |
| GET | `/api/users/{id}/profile` | One user's interests |
| GET | `/api/users/{id}/suggestions` | **Ranked trip suggestions** (`travel_month`, `min_score`, `limit`) |
| POST | `/api/trips` | Create a trip via `sp_create_trip` |
| GET | `/api/trips/{id}` | Cost summary for a trip |

```bash
curl "http://127.0.0.1:8000/api/users/2/suggestions?travel_month=3&min_score=50"
```

Tests run against a real MySQL server (no mocks):

```bash
pytest -q
```

## Verified

Validated against MySQL 8.4.13: every acceptance count matches, all rule tests in `02`,
`04` and `06` are rejected as expected, the CASCADE/SET NULL behaviour works, all three
procedures run, and the audit and budget-alert triggers fire correctly. All scripts are
idempotent â€” re-running `03` then `05` then `07` reproduces the same object counts.
The API passes 16 end-to-end tests against the live database and leaves no test rows
behind.
