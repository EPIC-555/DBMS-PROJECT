-- =====================================================================
--  DEMO SCRIPT for travel_itinerary_db  (run 01_travel_itinerary_v2_full.sql first)
--  Run section by section: put the cursor on a statement and press Ctrl+Enter
--  (Cmd+Enter on Mac). Screenshots of each result are your "working" proof.
-- =====================================================================
USE travel_itinerary_db;

-- ########## SECTION A: structure is really there ##########
SHOW TABLES;                                                          -- 21 tables + 1 view

SELECT table_name, table_rows FROM information_schema.tables
 WHERE table_schema = 'travel_itinerary_db' AND table_type = 'BASE TABLE' ORDER BY table_name;

SELECT constraint_name, table_name, referenced_table_name, delete_rule, update_rule
  FROM information_schema.referential_constraints
 WHERE constraint_schema = 'travel_itinerary_db' ORDER BY table_name;   -- 27 rows

SELECT trigger_name, event_object_table, action_timing, event_manipulation
  FROM information_schema.triggers WHERE trigger_schema = 'travel_itinerary_db'
 ORDER BY event_object_table, trigger_name;                            -- 12 rows

-- ########## SECTION B: queries ##########

-- Q1. Day-wise itinerary of trip 1 (4-table join, LEFT JOIN for optional place)
SELECT d.day_number, d.day_date, i.seq_no,
       TIME_FORMAT(i.start_time,'%H:%i') AS starts, TIME_FORMAT(i.end_time,'%H:%i') AS ends,
       ac.name AS category, i.title, COALESCE(p.name,'-') AS place, i.estimated_cost, i.status
  FROM itinerary_days d
  JOIN itinerary_items i       ON i.day_id = d.day_id
  JOIN activity_categories ac  ON ac.category_id = i.category_id
  LEFT JOIN places p           ON p.place_id = i.place_id
 WHERE d.trip_id = 1
 ORDER BY d.day_number, i.seq_no;

-- Q2. Budget vs actual spend (derived attributes actual_spend / remaining_budget)
SELECT t.trip_id, t.title, t.status, t.budget_total,
       COALESCE(SUM(e.amount),0)                         AS actual_spend,
       t.budget_total - COALESCE(SUM(e.amount),0)        AS remaining_budget,
       ROUND(100*COALESCE(SUM(e.amount),0)/NULLIF(t.budget_total,0),1) AS pct_used
  FROM trips t LEFT JOIN expenses e ON e.trip_id = t.trip_id
 GROUP BY t.trip_id, t.title, t.status, t.budget_total
 ORDER BY t.trip_id;

-- Q3. Spend by expense category for each trip
SELECT t.title, ec.name AS category, SUM(e.amount) AS total, COUNT(*) AS entries
  FROM expenses e
  JOIN trips t               ON t.trip_id = e.trip_id
  JOIN expense_categories ec ON ec.expense_category_id = e.expense_category_id
 GROUP BY t.trip_id, t.title, ec.name
 ORDER BY t.trip_id, total DESC;

-- Q4. Settlement: who owes / is owed (equal split among all members) for trip 3
SELECT u.full_name, COALESCE(p.paid,0) AS paid, ROUND(tot.total/mc.cnt,2) AS fair_share,
       ROUND(COALESCE(p.paid,0) - tot.total/mc.cnt,2) AS net_balance
  FROM trip_members tm
  JOIN users u ON u.user_id = tm.user_id
  LEFT JOIN (SELECT paid_by, SUM(amount) AS paid FROM expenses WHERE trip_id = 3 GROUP BY paid_by) p ON p.paid_by = tm.user_id
  CROSS JOIN (SELECT SUM(amount) AS total FROM expenses WHERE trip_id = 3) tot
  CROSS JOIN (SELECT COUNT(*) AS cnt FROM trip_members WHERE trip_id = 3) mc
 WHERE tm.trip_id = 3
 ORDER BY net_balance DESC;       -- positive = gets money back, negative = owes

-- Q5. Hotel reservation summary from the VIEW (nights, total, paid, balance are derived)
SELECT * FROM v_reservation_summary ORDER BY reservation_id;

-- Q6. Rooms still free in Goa for 26-29 Dec 2026 (NOT EXISTS anti-join, skips maintenance rooms)
--     Select the SET line and the SELECT together and run both (the @variables must exist).
SET @ci = '2026-12-26', @co = '2026-12-29';
SELECT p.name AS hotel, rt.name AS room_type, r.room_number, rt.max_occupancy, rt.base_rate
  FROM rooms r
  JOIN room_types rt  ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id
  JOIN places p       ON p.place_id = r.hotel_id
  JOIN destinations d ON d.destination_id = p.destination_id
 WHERE d.name = 'Goa' AND r.status = 'available'
   AND NOT EXISTS (SELECT 1 FROM hotel_reservations hr
                    WHERE hr.room_id = r.room_id AND hr.status <> 'cancelled'
                      AND @ci < hr.check_out AND @co > hr.check_in)
 ORDER BY p.name, r.room_number;

-- Q7. Hotel performance: stays, nights, revenue and average guest rating
SELECT v.hotel_name, COUNT(*) AS live_reservations, SUM(v.nights) AS nights, SUM(v.total_cost) AS booked_value,
       ROUND(AVG(hrv.rating),1) AS avg_rating
  FROM v_reservation_summary v
  LEFT JOIN hotel_reviews hrv ON hrv.reservation_id = v.reservation_id
 WHERE v.status <> 'cancelled'
 GROUP BY v.hotel_name ORDER BY booked_value DESC;

-- Q8. Best-rated destinations (GROUP BY + HAVING)
SELECT d.name, ROUND(AVG(r.rating),2) AS avg_rating, COUNT(*) AS reviews
  FROM destinations d JOIN reviews r ON r.destination_id = d.destination_id
 GROUP BY d.destination_id, d.name HAVING COUNT(*) >= 2
 ORDER BY avg_rating DESC;

-- Q9. Running total of spend per trip (window function)
SELECT trip_id, expense_date, description, amount,
       SUM(amount) OVER (PARTITION BY trip_id ORDER BY expense_date, expense_id) AS running_total
  FROM expenses WHERE trip_id IN (3,4) ORDER BY trip_id, expense_date, expense_id;

-- Q10. Trips with their members and roles (GROUP_CONCAT)
SELECT t.title, t.start_date, t.status,
       GROUP_CONCAT(CONCAT(u.full_name,' (',tm.role,')') ORDER BY tm.role SEPARATOR ', ') AS members
  FROM trips t JOIN trip_members tm ON tm.trip_id = t.trip_id JOIN users u ON u.user_id = tm.user_id
 GROUP BY t.trip_id, t.title, t.start_date, t.status ORDER BY t.start_date;

-- Q11. Transport/adventure items that still have NO booking (LEFT JOIN ... IS NULL)
SELECT t.title AS trip, d.day_date, i.title AS item, ac.name AS category
  FROM itinerary_items i
  JOIN itinerary_days d       ON d.day_id = i.day_id
  JOIN trips t                ON t.trip_id = d.trip_id
  JOIN activity_categories ac ON ac.category_id = i.category_id
  LEFT JOIN bookings b        ON b.item_id = i.item_id
 WHERE ac.name IN ('Transport','Adventure') AND b.booking_id IS NULL
 ORDER BY d.day_date;

-- Q12. Integrity check for the rule no constraint can enforce: every owner must be a member with role 'owner'
SELECT t.trip_id, t.title FROM trips t
  LEFT JOIN trip_members tm ON tm.trip_id = t.trip_id AND tm.user_id = t.owner_id AND tm.role = 'owner'
 WHERE tm.trip_id IS NULL;        -- expected: 0 rows

-- ########## SECTION C: triggers and constraints REJECT bad data ##########
-- Each statement below must FAIL with the message shown. Everything is inside one
-- transaction that is rolled back at the end, so nothing is saved either way.
START TRANSACTION;

-- C1  overlapping timed items on the same day (trip 1, day 2 already has 09:00-12:00)
INSERT INTO itinerary_items (day_id, seq_no, category_id, title, start_time, end_time)
VALUES (2, 9, 1, 'Clashing activity', '10:00', '11:00');
-- ERROR 1644: Timed items on the same day must not overlap

-- C2  day outside the trip, and day_date that does not match day_number (trip 1 runs 26-30 Dec)
INSERT INTO itinerary_days (trip_id, day_number, day_date) VALUES (1, 6, '2026-12-31');
-- ERROR 1644: day_date is outside the trip dates
INSERT INTO itinerary_days (trip_id, day_number, day_date) VALUES (1, 7, '2026-12-30');
-- ERROR 1644: day_date must equal trip start_date + day_number - 1

-- C3  double booking of room 3 (already reserved 26-30 Dec, reservation 1)
INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, num_guests, rate_per_night)
VALUES (1, 3, 2, '2026-12-28', '2026-12-30', 2, 7000);
-- ERROR 1644: Room is already reserved for these dates

-- C4  too many guests (Deluxe Sea View sleeps 3)
INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, num_guests, rate_per_night)
VALUES (1, 4, 2, '2026-12-26', '2026-12-28', 5, 7000);
-- ERROR 1644: Number of guests exceeds the room type capacity

-- C5  room under maintenance (room 2)
INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, num_guests, rate_per_night)
VALUES (1, 2, 2, '2026-12-26', '2026-12-28', 2, 4500);
-- ERROR 1644: Room is under maintenance and cannot be reserved

-- C6  a viewer (Sneha, user 4) tries to book for trip 1
INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, num_guests, rate_per_night)
VALUES (1, 4, 4, '2026-12-26', '2026-12-28', 2, 7000);
-- ERROR 1644: Only a trip owner or editor can book a room

-- C7  stay outside the trip dates
INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, num_guests, rate_per_night)
VALUES (1, 4, 2, '2027-02-01', '2027-02-03', 2, 7000);
-- ERROR 1644: Stay must be inside the trip dates

-- C8  review for a stay that is not completed (reservation 6 is checked_in)
INSERT INTO hotel_reviews (reservation_id, rating) VALUES (6, 5);
-- ERROR 1644: Only a completed stay can be reviewed

-- C9  expense linked to an item of another trip (item 1 belongs to trip 1, expense is for trip 2)
INSERT INTO expenses (trip_id, item_id, expense_category_id, paid_by, amount, expense_date)
VALUES (2, 1, 1, 3, 500, '2026-11-10');
-- ERROR 1644: Expense item must belong to the same trip as the expense

-- C10 a hotel row for a place that is not a Hotel (place 1 = Baga Beach)
INSERT INTO hotels (hotel_id, star_rating) VALUES (1, 3);
-- ERROR 1644: A hotel row must point at a place whose place_type is Hotel

-- C11 CHECK constraints
INSERT INTO reviews (user_id, destination_id, rating) VALUES (1, 2, 6);         -- ERROR 3819 chk_reviews_rating
INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount, expense_date)
VALUES (1, 1, 2, -50, '2026-10-01');                                             -- ERROR 3819 chk_expenses_amount

-- C12 UNIQUE / PRIMARY KEY
INSERT INTO users (email, password_hash, full_name) VALUES ('priya.nair@example.com','x','Dup');  -- ERROR 1062

-- C13 referential actions
DELETE FROM users WHERE user_id = 2;                 -- ERROR 1451 RESTRICT: Priya still owns trips
DELETE FROM expense_categories WHERE expense_category_id = 1;   -- ERROR 1451 RESTRICT: category in use

-- C14 CASCADE and SET NULL (these succeed; we count before and after, then roll back)
SELECT (SELECT COUNT(*) FROM itinerary_days WHERE trip_id=5)  AS days_before,
       (SELECT COUNT(*) FROM itinerary_items i JOIN itinerary_days d ON d.day_id=i.day_id WHERE d.trip_id=5) AS items_before,
       (SELECT COUNT(*) FROM expenses WHERE trip_id=5)        AS expenses_before,
       (SELECT COUNT(*) FROM hotel_reservations WHERE trip_id=5) AS reservations_before;
DELETE FROM trips WHERE trip_id = 5;                  -- cascades to members, days, items, bookings, expenses, reservations
SELECT (SELECT COUNT(*) FROM itinerary_days WHERE trip_id=5)  AS days_after,
       (SELECT COUNT(*) FROM expenses WHERE trip_id=5)        AS expenses_after,
       (SELECT COUNT(*) FROM hotel_reservations WHERE trip_id=5) AS reservations_after;   -- all 0

-- SET NULL: deleting a place keeps the itinerary item
SELECT item_id, title, place_id FROM itinerary_items WHERE place_id = 2;           -- Fort Aguada item
DELETE FROM places WHERE place_id = 2;
SELECT item_id, title, place_id FROM itinerary_items WHERE title = 'Visit Fort Aguada';   -- place_id is now NULL

ROLLBACK;     -- undoes everything done in Section C

-- ########## SECTION D: stored procedures (real transactions) ##########
-- D1  create a trip: trip + owner membership + one itinerary_days row per date, all-or-nothing
CALL sp_create_trip(2, 'Demo: Weekend in Udaipur', '2027-02-05', '2027-02-07', 30000, @new_trip);
SELECT @new_trip AS new_trip_id;
SELECT * FROM trip_members WHERE trip_id = @new_trip;
SELECT * FROM itinerary_days WHERE trip_id = @new_trip;          -- 3 rows created automatically

-- D2  book a room with row locking (room 31 = Palace Suite, Lake View Palace Inn)
CALL sp_book_room(@new_trip, 31, 2, '2027-02-05', '2027-02-07', 2, @res1);
SELECT * FROM v_reservation_summary WHERE reservation_id = @res1;     -- code HB0000nn, 2 nights x 11000

-- D3  same room, overlapping dates -> rejected and rolled back
CALL sp_book_room(@new_trip, 31, 2, '2027-02-06', '2027-02-07', 2, @res2);
-- ERROR 1644: Room is already reserved for these dates

-- D4  record a payment, then watch the view's derived columns change
INSERT INTO hotel_payments (reservation_id, payment_no, amount, method, status, transaction_ref)
VALUES (@res1, 1, 5000, 'upi', 'success', 'UPI-DEMO-0001');
SELECT reservation_id, total_cost, amount_paid, balance_due FROM v_reservation_summary WHERE reservation_id = @res1;

-- D5  clean up the demo rows (CASCADE removes days, members, reservation and payment)
DELETE FROM trips WHERE trip_id = @new_trip;
