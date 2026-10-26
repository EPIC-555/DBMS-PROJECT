# AGENTS.md â€” DBMS-PROJECT (Travel Itinerary and Expense Organizer)

## What this repo is
A MySQL relational-database project: `travel_itinerary_db`, implemented for MySQL Workbench.
It turns an ER diagram into a working schema with triggers, procedures, views and sample data.

## Repository layout / script order (IMPORTANT)
Scripts are numbered "add-ons" and MUST run in order:

1. `01_travel_itinerary_v2_full.sql` â€” base: 21 tables, 27 FKs, 12 triggers, 1 view, 2 procedures, 312 sample rows
2. `02_demo_queries.sql` â€” 12 queries (Q1-Q12), 14 rule tests (C1-C14), procedure demo
3. `03_transport_module.sql` â€” transport (flight/train/cab/bus/metro): +9 tables, +13 FKs, +12 triggers, +1 view
4. `04_*.sql` â€” (not present)
5. `05_smart_features.sql` â€” audit_log + trip_alerts: +2 tables, +1 FK, +7 triggers, +2 views

Running totals after 05: **32 tables, 41 FKs, 31 triggers, 4 views**.

### Gotcha
`03` DROPs views/triggers that `05` creates (because they depend on transport tables).
So after re-running `03`, you MUST re-run `05`.

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
- `Feasibility Study and Implementation Plan Travel Itinerary and Expense Organizer.pdf`
  is Revision 2 (26 Oct 2026): updated to the current 32/41/31/4 scope, documents the
  transport module and smart layer, and records the MySQL 8.4.13 verification.
- It is generated from `feasibility_plan_source.html` with WeasyPrint:
  `python3 -c "from weasyprint import HTML; HTML('feasibility_plan_source.html').write_pdf('Feasibility Study and Implementation Plan Travel Itinerary and Expense Organizer.pdf')"`
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

## Expected acceptance counts (quick check at end of each script)
- after 01: tables 21, FKs 27, triggers 12, views 1
- after 03: tables 30, FKs 40, triggers 24, views 2
- after 05: tables 32, FKs 41, triggers 31, views 4

## Documented expected outputs (from the Feasibility PDF)
- Q2 budget vs actual: Goa 60000/30000, Rajasthan 85000/14600, Munnar 40000/30600, Hampi 35000/22100, Manali 50000/5500
- Q4 Munnar settlement (total 30600, 3 ways = 10200): Sneha +11700, Karthik -4200, Ananya -7500
- Q5 view v_reservation_summary: 8 rows (res 1..8) with nights/total/paid/balance per PDF page 10
- Q12 owner-is-member integrity: returns 0 rows
