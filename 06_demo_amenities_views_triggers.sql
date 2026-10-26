-- =====================================================================
--  DEMO 06: amenities, dashboards (views), audit trail and budget alerts
--  Run 01, 03 and 05 first. Run statement by statement with Ctrl+Enter.
-- =====================================================================
USE travel_itinerary_db;

-- Expected after 01 + 03 + 05: tables 32, foreign keys 41, triggers 31, views 4
SELECT 'tables' AS what, COUNT(*) AS n FROM information_schema.tables WHERE table_schema='travel_itinerary_db' AND table_type='BASE TABLE'
UNION ALL SELECT 'foreign keys', COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema='travel_itinerary_db'
UNION ALL SELECT 'triggers', COUNT(*) FROM information_schema.triggers WHERE trigger_schema='travel_itinerary_db'
UNION ALL SELECT 'views', COUNT(*) FROM information_schema.views WHERE table_schema='travel_itinerary_db';

-- ########## SECTION A: the role of AMENITIES in the ER diagram ##########
-- amenities       = strong entity: ONE master list of facilities (Wi-Fi, Pool, Spa ...), each stored once.
-- hotel_amenities = associative entity for the M:N link hotels <-> amenities. Its own attribute
--                   is_complimentary says whether THIS hotel gives THAT facility free of charge.
-- Hence is_complimentary lives on the link, not on amenities (Wi-Fi is free at one hotel, paid at another)
-- and not on hotels (one hotel has many facilities).

-- A1. How many hotels offer each amenity, and how many give it free (LEFT JOIN keeps unused amenities)
SELECT a.name AS amenity, COUNT(ha.hotel_id) AS hotels_offering,
       COALESCE(SUM(ha.is_complimentary),0) AS free_at, COUNT(ha.hotel_id) - COALESCE(SUM(ha.is_complimentary),0) AS paid_at
  FROM amenities a LEFT JOIN hotel_amenities ha ON ha.amenity_id = a.amenity_id
 GROUP BY a.amenity_id, a.name ORDER BY hotels_offering DESC, a.name;
-- Wi-Fi 8/7/1 ; Breakfast 7/6/1 ; Parking 6/6/0 ; Air Conditioning 5/4/1 ; Spa 5/0/5 ; Swimming Pool 2/1/1 ; Airport Shuttle 1/0/1 ; Gym 0/0/0

-- A2. Hotels that offer BOTH free Wi-Fi and free parking (GROUP BY ... HAVING COUNT(DISTINCT) = 2)
SELECT p.name AS hotel, d.name AS destination
  FROM hotel_amenities ha
  JOIN amenities a    ON a.amenity_id = ha.amenity_id
  JOIN places p       ON p.place_id = ha.hotel_id
  JOIN destinations d ON d.destination_id = p.destination_id
 WHERE a.name IN ('Wi-Fi','Parking') AND ha.is_complimentary = TRUE
 GROUP BY p.place_id, p.name, d.name HAVING COUNT(DISTINCT a.name) = 2 ORDER BY d.name;
-- 5 hotels: Seaside Palms (Goa), Pink City Haveli (Jaipur), Pine Cone Lodge (Manali), Misty Hills (Munnar), Coffee Mist (Coorg)

-- A3. Amenity list per hotel, paid ones marked
SELECT p.name AS hotel, h.star_rating AS stars,
       GROUP_CONCAT(CONCAT(a.name, IF(ha.is_complimentary, '', ' (paid)')) ORDER BY a.name SEPARATOR ', ') AS amenities
  FROM hotels h JOIN places p ON p.place_id = h.hotel_id
  JOIN hotel_amenities ha ON ha.hotel_id = h.hotel_id JOIN amenities a ON a.amenity_id = ha.amenity_id
 GROUP BY h.hotel_id, p.name, h.star_rating ORDER BY h.star_rating DESC, p.name;

-- A4. ON DELETE CASCADE on both sides of the link (rolled back afterwards)
START TRANSACTION;
SELECT COUNT(*) AS links_before FROM hotel_amenities WHERE amenity_id = (SELECT amenity_id FROM amenities WHERE name = 'Spa');   -- 5
DELETE FROM amenities WHERE name = 'Spa';
SELECT COUNT(*) AS links_after FROM hotel_amenities WHERE amenity_id = 5;                                                      -- 0
ROLLBACK;

-- ########## SECTION B: dashboards built on views ##########

-- B1. Everything that happens on the Goa trip, in time order (transport + hotel + activities)
SELECT happens_at, event_type, description, status FROM v_trip_timeline WHERE trip_id = 1 ORDER BY happens_at;
-- 15 rows: 5 transport legs, hotel check-in and check-out, 8 activities (26 Dec 08:30 flight ... 30 Dec 14:45 flight)

-- B2. Budget dashboard: booked (hotels + transport) versus actually spent
SELECT trip_id, title, budget_total, hotel_booked, transport_booked, total_booked, booked_pct_of_budget, actual_spend, remaining_budget
  FROM v_trip_cost_summary ORDER BY trip_id;
-- trip 1: hotel 26000, transport 19240, total 45240 (75.4%), spent 30000, remaining 30000
-- trip 2: hotel 22600, transport 15030, total 37630 (44.3%), spent 14600, remaining 70400
-- trip 3: hotel 13500, transport 7000, total 20500 (51.3%), spent 30600, remaining 9400
-- trip 4: hotel 14000, transport 0, total 14000 (40.0%), spent 22100, remaining 12900
-- trip 5: hotel 12000, transport 5060, total 17060 (34.1%), spent 5500, remaining 44500

-- ########## SECTION C: AFTER triggers REACT (alerts and audit trail) ##########
-- Everything is inside one transaction and rolled back at the end.
START TRANSACTION;

-- C1  spending reaches 80 percent of the budget (trip 4: budget 35000, spent so far 22100)
INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount, expense_date, description)
VALUES (4, 6, 5, 10000, '2026-10-22', 'Test: souvenirs and coffee beans');
SELECT trip_id, alert_type, message FROM trip_alerts;
-- 1 row: budget_80 - Spending 32100.00 has reached 80 percent of the budget of 35000.00

-- C2  spending passes the budget
INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount, expense_date, description)
VALUES (4, 6, 5, 5000, '2026-10-22', 'Test: extra night stay');
SELECT trip_id, alert_type, message FROM trip_alerts ORDER BY alert_id;
-- 2 rows: budget_80 and budget_exceeded - Spending 37100.00 has exceeded the budget of 35000.00

-- C3  one more expense: no duplicate alert (UNIQUE (trip_id, alert_type) plus INSERT IGNORE)
INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount, expense_date, description)
VALUES (4, 1, 5, 100, '2026-10-22', 'Test: parking');
SELECT COUNT(*) AS alerts_for_trip_4 FROM trip_alerts WHERE trip_id = 4;      -- still 2

-- C4  audit trail: change some data, then read the history
UPDATE expenses SET amount = 4000 WHERE expense_id = 4;                              -- 3500.00 -> 4000.00
UPDATE trips SET budget_total = 65000, status = 'ongoing' WHERE trip_id = 1;         -- two audit rows
UPDATE transport_bookings SET status = 'cancelled' WHERE transport_id = 9;           -- pending -> cancelled
UPDATE hotel_reservations SET status = 'confirmed' WHERE reservation_id = 3;         -- pending -> confirmed
DELETE FROM expenses WHERE expense_id = 7;                                           -- 2000.00 deleted
SELECT audit_id, table_name, record_id, action, field_name, old_value, new_value, changed_by FROM audit_log ORDER BY audit_id;
-- 6 rows: expenses 4 amount | trips 1 budget_total | trips 1 status | transport_bookings 9 status | hotel_reservations 3 status | expenses 7 DELETE

ROLLBACK;     -- everything above disappears, including the alerts and the audit rows
SELECT (SELECT COUNT(*) FROM trip_alerts) AS alerts_after, (SELECT COUNT(*) FROM audit_log) AS audit_after;   -- 0, 0

-- ########## SECTION D: show the trigger code itself (for the viva) ##########
SELECT trigger_name, event_object_table AS on_table, action_timing AS timing, event_manipulation AS event
  FROM information_schema.triggers WHERE trigger_schema = 'travel_itinerary_db'
 ORDER BY action_timing, event_object_table, trigger_name;                  -- 31 rows
SHOW CREATE TRIGGER trg_exp_budget_alert_ai;                                 -- open the Create Trigger cell to read the source
SHOW CREATE TRIGGER trg_res_validate_bi;
