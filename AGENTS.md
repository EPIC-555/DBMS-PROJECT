# AGENTS.md â€” DBMS-PROJECT (Travel Itinerary and Expense Organizer)

## What this repo is
A MySQL relational-database project: `travel_itinerary_db`, implemented for MySQL Workbench.
It turns an ER diagram into a working schema with triggers, procedures, views and sample data.

## Repository layout / script order (IMPORTANT)
Scripts are numbered "add-ons" and MUST run in order:

1. `01_travel_itinerary_v2_full.sql` â€” base: 21 tables, 27 FKs, 12 triggers, 1 view, 2 procedures, 312 sample rows
2. `02_demo_queries.sql` â€” 12 queries (Q1-Q12), 14 rule tests (C1-C14), procedure demo
3. `03_transport_module.sql` â€” transport (flight/train/cab/bus/metro): +9 tables, +13 FKs, +12 triggers, +1 view
4. `04_transport_demo.sql` â€” transport demo: 7 queries (T1-T7), 10 rule tests (X1-X10)
5. `05_smart_features.sql` â€” audit_log + trip_alerts: +2 tables, +1 FK, +7 triggers, +2 views
6. `06_demo_amenities_views_triggers.sql` â€” amenities, dashboard views, alerts + audit-trail demo
7. `07_recommendation_engine.sql` â€” recommendation layer: trip suggestions (adds 1 table, 3 views, 1 procedure)

Running totals after 05: **32 tables, 41 FKs, 31 triggers, 4 views**.
Running totals after 07: **33 tables, 42 FKs, 31 triggers, 7 views, 3 procedures**.

### Gotcha
`03` DROPs views/triggers that `05` creates (because they depend on transport tables).
So after re-running `03`, you MUST re-run `05`. `07` does NOT depend on `03`, so it
survives a `03` re-run; run it last regardless.

## Design conventions
- Engine InnoDB, charset utf8mb4.
- Money = DECIMAL(10,2) (never FLOAT). Statuses/roles = ENUM.
- IS-A pattern: `hotels.hotel_id` is BOTH PK and FK -> `places.place_id` (shared key).
  Same pattern for transport: `transport_bookings` supertype + 5 subtype tables.
- Weak entities: `hotel_payments(reservation_id,payment_no)`,
  `hotel_reviews(reservation_id,review_no)`, `transport_passengers(transport_id,passenger_no)`.
- Composite FK: `rooms(room_type_id,hotel_id)` -> `room_types(room_type_id,hotel_id)`.
- Derived values (nights, totals, balance, remaining budget) are NEVER stored; computed in views/queries.
- ON DELETE: CASCADE for owned children, RESTRICT for shared master data, SET NULL for optional links.
- Rules enforced by BEFORE triggers (SIGNAL SQLSTATE '45000'); reactions by AFTER triggers.

## Application layer (app/)
A FastAPI service over the database. Business rules stay in MySQL; the API validates
input and shapes JSON. Modules: `app/db.py` (pooled connection + query helpers),
`app/recommender.py` (calls the views and procedures), `app/main.py` (routes).
Run: `uvicorn app.main:app --reload`. Config comes from `.env` (see `.env.example`);
never commit the real `.env`. Tests in `tests/test_api.py` run against a live MySQL.

## Recommendation model (07)
Scores each destination a user has NOT visited, out of 100: quality 30 (avg rating),
crowd 15 (review count), wishlist 15 (save count), personal taste 20 (user saved or
rated it 4+), in season 20. `destination_season_months` normalises the free-text
`destinations.best_season` into month numbers so "what suits me in March?" is a query.
Weights are literal constants in the view and procedure â€” change them and the ranking
changes, so keep the two copies in step.

## Verified environment
MySQL 8.4 LTS. Local test container:
`docker run -d --name dbms-mysql -e MYSQL_ROOT_PASSWORD=rootpw -p 3307:3306 mysql:8.4 --log-bin-trust-function-creators=1`
Load: `mysql -h127.0.0.1 -P3307 -uroot -prootpw < script.sql`

## Fixes applied / gotchas found
- FIXED: `05_smart_features.sql` claimed "safe to re-run" but did NOT drop its 7 triggers,
  so a second run failed with ERROR 1359 (Trigger already exists). Added the 7
  `DROP TRIGGER IF EXISTS` statements. This matters because `03` drops 05's triggers/views.
- NOTE: `02_demo_queries.sql` Section A asserts "21 tables + 1 view" / 27 FKs / 12 triggers.
  That is only true right after `01`. If 02 is run after the full 01->03->05 stack, the
  counts are 32 / 41 / 31 / 4. Intended order per the demo header is 01 then 02.

## Plan document (PDF)
- `FEASIBILITY.pdf` is Revision 2 (26 Oct 2026): updated to the current 32/41/31/4 scope, documents the
  transport module and smart layer, and records the MySQL 8.4.13 verification.
- It is generated from `feasibility_plan_source.html` with WeasyPrint:
  `python3 -c "from weasyprint import HTML; HTML('feasibility_plan_source.html').write_pdf('FEASIBILITY.pdf')"`
  Edit the HTML, not the PDF, when changing the document.

## Verified on MySQL 8.4.13 (all passing)
- 01 -> 21/27/12/1 ; 03 -> 30/40/24/2 ; 05 -> 32/41/31/4. All idempotent (double re-runs OK).
- Base-layer row counts match the PDF exactly; base tables total 312 rows.
- 02 Section B: Q2, Q4, Q5, Q6, Q8, Q11, Q12 outputs match the PDF's documented expected values.
- 02 Section C: all 14 rule tests rejected with the documented errors (1644 / 3819 / 1062 / 1451);
  CASCADE + SET NULL behave; C14 counts = 5 days / 7 items / 2 expenses / 1 reservation.
- 02 Section D: sp_create_trip creates trip + owner member + one day per date; sp_book_room
  returns reservation HB000009 and rejects the overlapping re-booking.
- Transport triggers (03): carrier/mode, station/mode, same-station, booker-role, subtype-guard
  and chk_tb_times all reject; valid cab bookings (no stations) succeed.
- Smart layer (05): audit_log records status changes; trip_alerts fire at 80% and over budget.
- 04 (transport demo): T1-T7 outputs match the file comments; all 10 X-tests rejected
  (1644 carrier/mode, 1644 same station, 1644 station/mode, 1644 metro needs stations,
  3819 chk_tb_times, 1644 booker role, 1644 item-trip, 1644 subtype guard, 1062 seat,
  1451 carrier RESTRICT); valid legs pass.
- 06 (amenities/views/triggers): counts 32/41/31/4; A1-A4 amenity results match; A4 cascade
  5->0; B1 timeline 15 rows; B2 cost summary matches; C1-C3 alerts 80%/exceeded/no dup;
  C4 audit 6 rows; ROLLBACK leaves 0 alerts and 0 audit rows. No errors in 06.
- 07 (recommendation): counts 33/42/31/7 + 3 procedures. Suggestions exclude visited
  destinations (user 2 never gets Goa). Ranking verified: user 2 for March returns
  Jaipur 67, Coorg 58, Munnar 53, Udaipur 50 (Udaipur carries 'already on your wishlist').
  Season flag flips with the month (Manali in season in Jan, not in Jul). Re-run is
  idempotent and survives a `03` re-run.
- API: 16/16 tests pass against MySQL 8.4.13 (`pytest -q`), endpoints also verified over
  real HTTP. Three bugs found and fixed during testing: (1) CALL leaves extra result sets,
  which if undrained corrupts the pool and later raises 'MySQL Connection not available';
  (2) DECIMAL columns serialised as JSON strings, now floats; (3) the create-trip test
  left rows behind, now deleted via the cascade.

## Expected acceptance counts (quick check at end of each script)
- after 01: tables 21, FKs 27, triggers 12, views 1
- after 03: tables 30, FKs 40, triggers 24, views 2
- after 05: tables 32, FKs 41, triggers 31, views 4

## Documented expected outputs (from the Feasibility PDF)
- Q2 budget vs actual: Goa 60000/30000, Rajasthan 85000/14600, Munnar 40000/30600, Hampi 35000/22100, Manali 50000/5500
- Q4 Munnar settlement (total 30600, 3 ways = 10200): Sneha +11700, Karthik -4200, Ananya -7500
- Q5 view v_reservation_summary: 8 rows (res 1..8) with nights/total/paid/balance per PDF page 10
- Q12 owner-is-member integrity: returns 0 rows
