-- =====================================================================
--  DEMO 04: transport module (flights, trains, cabs, buses, metro)
--  Run 01, 03 and 05 first. Run statement by statement with Ctrl+Enter.
--  Expected results are in the comments (computed from the sample data).
-- =====================================================================
USE travel_itinerary_db;

-- ########## SECTION A: structure ##########
SELECT trigger_name, event_object_table, action_timing, event_manipulation FROM information_schema.triggers
 WHERE trigger_schema = 'travel_itinerary_db'
   AND event_object_table IN ('transport_bookings','flight_details','train_details','cab_details','bus_details','metro_details')
   AND action_timing = 'BEFORE'
 ORDER BY event_object_table, trigger_name;                  -- 12 rows (6 families x insert/update)

-- ########## SECTION B: queries ##########

-- T1. Every transport leg of the Goa trip in time order (the view joins 9 tables)
SELECT transport_id, transport_mode, carrier, route, depart_at, duration_min, passengers, fare, status
  FROM v_trip_transport WHERE trip_id = 1 ORDER BY depart_at;
-- 5 legs: flight 95 min, cab 60, city bus 25 (Calangute to Anjuna), cab 50, return flight 85

-- T2. Spend per trip and mode (cancelled legs ignored; modes sort in ENUM order flight, train, cab, bus, metro)
SELECT trip_title, transport_mode, COUNT(*) AS legs, SUM(fare) AS total_fare
  FROM v_trip_transport WHERE status <> 'cancelled'
 GROUP BY trip_id, trip_title, transport_mode ORDER BY trip_id, transport_mode;
-- Goa: flight 17000, cab 2200, bus 40 | Rajasthan: flight 7000, train 3000, cab 5000, metro 30 | Munnar: cab 7000 | Manali: bus 5000, metro 60

-- T3. Passenger manifest of the Volvo bus to Manali (booking 13)
SELECT tp.passenger_no, tp.full_name, tp.age, tp.seat_no,
       CONCAT(c.name, ', ', bd.bus_type, ' ', bd.bus_number) AS bus
  FROM transport_passengers tp
  JOIN transport_bookings tb ON tb.transport_id = tp.transport_id
  JOIN carriers c            ON c.carrier_id = tb.carrier_id
  JOIN bus_details bd        ON bd.transport_id = tb.transport_id
 WHERE tp.transport_id = 13 ORDER BY tp.passenger_no;          -- 2 rows: Ananya L5, Sneha L6

-- T4. Itinerary items of category Transport that have NO transport booking (anti-join)
SELECT t.title AS trip, d.day_date, i.title AS item
  FROM itinerary_items i
  JOIN itinerary_days d       ON d.day_id = i.day_id
  JOIN trips t                ON t.trip_id = d.trip_id
  JOIN activity_categories ac ON ac.category_id = i.category_id
 WHERE ac.name = 'Transport'
   AND NOT EXISTS (SELECT 1 FROM transport_bookings tb WHERE tb.item_id = i.item_id)
 ORDER BY d.day_date;                                          -- 3 rows: the self-drive Hampi and Coorg trip

-- T5. Fare comparison by mode, including cost per passenger
SELECT transport_mode, COUNT(*) AS bookings, SUM(fare) AS total_fare, ROUND(AVG(fare),2) AS avg_fare,
       SUM(passengers) AS passengers, ROUND(SUM(fare)/SUM(passengers),2) AS fare_per_passenger
  FROM v_trip_transport WHERE status <> 'cancelled' GROUP BY transport_mode ORDER BY total_fare DESC;
-- flight 3 legs / 24000 / avg 8000.00 / 6 pax / 4000.00 per pax; cab 5 legs / 14200 / avg 2840.00 / 13 pax / 1092.31 per pax; bus 3 legs / 5040 / avg 1680.00 / 6 pax / 840.00 per pax; train 1 legs / 3000 / avg 3000.00 / 3 pax / 1000.00 per pax; metro 2 legs / 90 / avg 45.00 / 5 pax / 18.00 per pax

-- T6. Public transport versus private cab versus air (CASE grouping)
SELECT CASE WHEN transport_mode IN ('train','bus','metro') THEN 'Public transport'
            WHEN transport_mode = 'flight' THEN 'Air' ELSE 'Private cab' END AS category,
       COUNT(*) AS legs, SUM(fare) AS total_fare, SUM(passengers) AS passengers
  FROM v_trip_transport WHERE status <> 'cancelled' GROUP BY category ORDER BY total_fare DESC;
-- Air 3 legs / 24000 ; Private cab 5 legs / 14200 ; Public transport 6 legs / 8130

-- T7. Share of each trip's budget that goes to transport (LEFT JOIN keeps trips with no transport)
SELECT t.title, t.budget_total, COALESCE(SUM(tb.fare),0) AS transport_cost,
       ROUND(100*COALESCE(SUM(tb.fare),0)/t.budget_total,1) AS pct_of_budget
  FROM trips t LEFT JOIN transport_bookings tb ON tb.trip_id = t.trip_id AND tb.status <> 'cancelled'
 GROUP BY t.trip_id, t.title, t.budget_total ORDER BY pct_of_budget DESC;
-- Goa 19240 (32.1%); Rajasthan 15030 (17.7%); Munnar 7000 (17.5%); Manali 5060 (10.1%); Hampi 0

-- ########## SECTION C: the database rejects bad transport data ##########
-- Everything is inside one transaction that is rolled back at the end.
START TRANSACTION;

-- X1  carrier type must match the mode (carrier 4 is a cab operator, but the mode is flight)
INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, origin_station_id, destination_station_id, depart_at, arrive_at)
VALUES (1, 'flight', 4, 2, 1, 2, '2026-12-27 08:00', '2026-12-27 09:30');
-- ERROR 1644: Carrier type does not match the transport mode

-- X2  same origin and destination
INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, origin_station_id, destination_station_id, depart_at, arrive_at)
VALUES (1, 'flight', 1, 2, 1, 1, '2026-12-27 08:00', '2026-12-27 09:30');
-- ERROR 1644: Origin and destination must be different

-- X3  a bus journey between two airports
INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, origin_station_id, destination_station_id, depart_at, arrive_at)
VALUES (5, 'bus', 8, 6, 1, 2, '2027-01-10 08:00', '2027-01-10 12:00');
-- ERROR 1644: Station type does not match the transport mode

-- X4  a metro leg without stations
INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, depart_at, arrive_at)
VALUES (5, 'metro', 10, 6, '2027-01-09 09:00', '2027-01-09 09:30');
-- ERROR 1644: This mode needs an origin and a destination station

-- X5  arrival before departure (CHECK constraint)
INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, depart_at, arrive_at)
VALUES (1, 'cab', 4, 2, '2026-12-27 10:00', '2026-12-27 09:00');
-- ERROR 3819: Check constraint 'chk_tb_times' is violated

-- X6  a viewer (Sneha, user 4) tries to book for trip 1
INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, depart_at, arrive_at)
VALUES (1, 'cab', 4, 4, '2026-12-27 10:00', '2026-12-27 11:00');
-- ERROR 1644: Only a trip owner or editor can book transport

-- X7  link a trip 2 booking to an itinerary item of trip 1 (item 1)
INSERT INTO transport_bookings (trip_id, item_id, transport_mode, carrier_id, booked_by, depart_at, arrive_at)
VALUES (2, 1, 'cab', 5, 3, '2026-11-11 10:00', '2026-11-11 11:00');
-- ERROR 1644: Itinerary item belongs to a different trip

-- X8  bus details attached to a metro booking (id 7)
INSERT INTO bus_details (transport_id, bus_type) VALUES (7, 'ordinary');
-- ERROR 1644: bus_details requires a booking whose mode is bus

-- X9  same seat twice on one booking (14A is already taken on flight booking 1)
INSERT INTO transport_passengers (transport_id, passenger_no, full_name, seat_no) VALUES (1, 3, 'Extra Guest', '14A');
-- ERROR 1062: Duplicate entry for key 'uk_tp_seat'

-- X10 delete a carrier that is in use
DELETE FROM carriers WHERE carrier_id = 1;
-- ERROR 1451: foreign key violation (RESTRICT)

-- X11 CASCADE: deleting trip 3 removes its transport legs, subtype rows and passengers
SELECT (SELECT COUNT(*) FROM transport_bookings WHERE trip_id = 3) AS legs_before,
       (SELECT COUNT(*) FROM cab_details WHERE transport_id IN (10,11)) AS cab_rows_before,
       (SELECT COUNT(*) FROM transport_passengers WHERE transport_id IN (10,11)) AS passengers_before;   -- 2, 2, 6
DELETE FROM trips WHERE trip_id = 3;
SELECT (SELECT COUNT(*) FROM transport_bookings WHERE trip_id = 3) AS legs_after,
       (SELECT COUNT(*) FROM cab_details WHERE transport_id IN (10,11)) AS cab_rows_after,
       (SELECT COUNT(*) FROM transport_passengers WHERE transport_id IN (10,11)) AS passengers_after;    -- 0, 0, 0

-- X12 SET NULL: deleting itinerary item 1 keeps the bookings but unlinks them
DELETE FROM itinerary_items WHERE item_id = 1;
SELECT transport_id, transport_mode, item_id FROM transport_bookings WHERE transport_id IN (1,2);      -- item_id is NULL for both

ROLLBACK;   -- undoes everything in Section C

-- ########## SECTION D: add a new public-transport leg the right way ##########
-- A city bus back from Anjuna to Calangute for the Goa trip (trip 1, owner Priya = user 2)
INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, origin_station_id, destination_station_id, depart_at, arrive_at, status, fare, confirmation_code)
VALUES (1, 'bus', 7, 2, 10, 9, '2026-12-28 19:10', '2026-12-28 19:35', 'confirmed', 40, 'KTC-DEMO-01');
SET @new_leg = LAST_INSERT_ID();
INSERT INTO bus_details (transport_id, bus_type, bus_number) VALUES (@new_leg, 'city_bus', 'GA-03-KTC-204');
INSERT INTO transport_passengers (transport_id, passenger_no, full_name, user_id) VALUES (@new_leg, 1, 'Priya Nair', 2), (@new_leg, 2, 'Rohan Mehta', 3);
SELECT transport_id, transport_mode, route, duration_min, passengers, fare FROM v_trip_transport WHERE transport_id = @new_leg;
DELETE FROM transport_bookings WHERE transport_id = @new_leg;     -- cascades to bus_details and passengers
