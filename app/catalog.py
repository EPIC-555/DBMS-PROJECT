"""The demo catalog: the project's own queries and rule tests, exposed as data.

Every entry mirrors a statement in 02_demo_queries.sql, 04_transport_demo.sql or
06_demo_amenities_views_triggers.sql, so the dashboard shows exactly what the
submitted SQL files show.
"""

from __future__ import annotations

# ---------------------------------------------------------------- queries
# Each query: id, title, sql, params (positional, %s), note (the expected result
# documented in the SQL file), section.
QUERIES: list[dict] = [
    # ---- 02_demo_queries.sql, Section B (Q1-Q12) ----
    {
        "id": "Q1",
        "section": "Core",
        "title": "Day-wise itinerary of a trip",
        "note": "4-table join with a LEFT JOIN for the optional place.",
        "sql": """
            SELECT d.day_number, d.day_date, i.seq_no,
                   TIME_FORMAT(i.start_time,'%H:%i') AS starts,
                   TIME_FORMAT(i.end_time,'%H:%i')   AS ends,
                   ac.name AS category, i.title,
                   COALESCE(p.name,'-') AS place, i.estimated_cost, i.status
              FROM itinerary_days d
              JOIN itinerary_items i      ON i.day_id = d.day_id
              JOIN activity_categories ac ON ac.category_id = i.category_id
              LEFT JOIN places p          ON p.place_id = i.place_id
             WHERE d.trip_id = %s
             ORDER BY d.day_number, i.seq_no
        """,
        "params": [1],
        "param_labels": ["trip_id"],
    },
    {
        "id": "Q2",
        "section": "Core",
        "title": "Budget versus actual spend",
        "note": "Goa 60000/30000, Rajasthan 85000/14600, Munnar 40000/30600, "
                "Hampi 35000/22100, Manali 50000/5500.",
        "sql": """
            SELECT t.trip_id, t.title, t.status, t.budget_total,
                   COALESCE(SUM(e.amount),0) AS actual_spend,
                   t.budget_total - COALESCE(SUM(e.amount),0) AS remaining_budget,
                   ROUND(100*COALESCE(SUM(e.amount),0)/NULLIF(t.budget_total,0),1) AS pct_used
              FROM trips t LEFT JOIN expenses e ON e.trip_id = t.trip_id
             GROUP BY t.trip_id, t.title, t.status, t.budget_total
             ORDER BY t.trip_id
        """,
        "params": [],
    },
    {
        "id": "Q3",
        "section": "Core",
        "title": "Spend by expense category per trip",
        "note": "GROUP BY over expenses joined to categories.",
        "sql": """
            SELECT t.title, ec.name AS category, SUM(e.amount) AS total, COUNT(*) AS entries
              FROM expenses e
              JOIN trips t               ON t.trip_id = e.trip_id
              JOIN expense_categories ec ON ec.expense_category_id = e.expense_category_id
             GROUP BY t.trip_id, t.title, ec.name
             ORDER BY t.trip_id, total DESC
        """,
        "params": [],
    },
    {
        "id": "Q4",
        "section": "Core",
        "title": "Settlement: who owes whom (equal split)",
        "note": "Munnar: each member owes 10200. Sneha +11700, Karthik -4200, Ananya -7500.",
        "sql": """
            SELECT u.full_name, COALESCE(p.paid,0) AS paid,
                   ROUND(tot.total/mc.cnt,2) AS fair_share,
                   ROUND(COALESCE(p.paid,0) - tot.total/mc.cnt,2) AS net_balance
              FROM trip_members tm
              JOIN users u ON u.user_id = tm.user_id
              LEFT JOIN (SELECT paid_by, SUM(amount) AS paid FROM expenses
                          WHERE trip_id = %s GROUP BY paid_by) p ON p.paid_by = tm.user_id
              CROSS JOIN (SELECT SUM(amount) AS total FROM expenses WHERE trip_id = %s) tot
              CROSS JOIN (SELECT COUNT(*) AS cnt FROM trip_members WHERE trip_id = %s) mc
             WHERE tm.trip_id = %s
             ORDER BY net_balance DESC
        """,
        "params": [3, 3, 3, 3],
        "param_labels": ["trip_id"],
        "hide_params": True,
    },
    {
        "id": "Q5",
        "section": "View",
        "title": "Hotel reservation summary (VIEW)",
        "note": "Nights, total, paid and balance are derived in v_reservation_summary.",
        "sql": "SELECT * FROM v_reservation_summary ORDER BY reservation_id",
        "params": [],
    },
    {
        "id": "Q6",
        "section": "Core",
        "title": "Rooms still free (NOT EXISTS anti-join)",
        "note": "Six free Goa rooms for 26-29 Dec; maintenance rooms excluded.",
        "sql": """
            SELECT p.name AS hotel, rt.name AS room_type, r.room_number,
                   rt.max_occupancy, rt.base_rate
              FROM rooms r
              JOIN room_types rt  ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id
              JOIN places p       ON p.place_id = r.hotel_id
              JOIN destinations d ON d.destination_id = p.destination_id
             WHERE d.name = %s AND r.status = 'available'
               AND NOT EXISTS (SELECT 1 FROM hotel_reservations hr
                                WHERE hr.room_id = r.room_id AND hr.status <> 'cancelled'
                                  AND %s < hr.check_out AND %s > hr.check_in)
             ORDER BY p.name, r.room_number
        """,
        "params": ["Goa", "2026-12-26", "2026-12-29"],
        "param_labels": ["destination", "check_in", "check_out"],
    },
    {
        "id": "Q7",
        "section": "Core",
        "title": "Hotel performance (stays, nights, revenue, rating)",
        "note": "Aggregates the view joined to hotel_reviews.",
        "sql": """
            SELECT v.hotel_name, COUNT(*) AS live_reservations, SUM(v.nights) AS nights,
                   SUM(v.total_cost) AS booked_value, ROUND(AVG(hrv.rating),1) AS avg_rating
              FROM v_reservation_summary v
              LEFT JOIN hotel_reviews hrv ON hrv.reservation_id = v.reservation_id
             WHERE v.status <> 'cancelled'
             GROUP BY v.hotel_name ORDER BY booked_value DESC
        """,
        "params": [],
    },
    {
        "id": "Q8",
        "section": "Core",
        "title": "Best-rated destinations (HAVING)",
        "note": "Only destinations with at least two reviews.",
        "sql": """
            SELECT d.name, ROUND(AVG(r.rating),2) AS avg_rating, COUNT(*) AS reviews
              FROM destinations d JOIN reviews r ON r.destination_id = d.destination_id
             GROUP BY d.destination_id, d.name HAVING COUNT(*) >= 2
             ORDER BY avg_rating DESC
        """,
        "params": [],
    },
    {
        "id": "Q9",
        "section": "Core",
        "title": "Running total of spend (window function)",
        "note": "SUM(...) OVER (PARTITION BY trip ORDER BY date).",
        "sql": """
            SELECT trip_id, expense_date, description, amount,
                   SUM(amount) OVER (PARTITION BY trip_id ORDER BY expense_date, expense_id) AS running_total
              FROM expenses WHERE trip_id IN (3,4)
             ORDER BY trip_id, expense_date, expense_id
        """,
        "params": [],
    },
    {
        "id": "Q10",
        "section": "Core",
        "title": "Trips with members and roles (GROUP_CONCAT)",
        "note": "One row per trip with its member list.",
        "sql": """
            SELECT t.title, t.start_date, t.status,
                   GROUP_CONCAT(CONCAT(u.full_name,' (',tm.role,')')
                                ORDER BY tm.role SEPARATOR ', ') AS members
              FROM trips t
              JOIN trip_members tm ON tm.trip_id = t.trip_id
              JOIN users u         ON u.user_id = tm.user_id
             GROUP BY t.trip_id, t.title, t.start_date, t.status ORDER BY t.start_date
        """,
        "params": [],
    },
    {
        "id": "Q11",
        "section": "Core",
        "title": "Transport/adventure items with NO booking (LEFT JOIN ... IS NULL)",
        "note": "Anti-join over the legacy bookings table.",
        "sql": """
            SELECT t.title AS trip, d.day_date, i.title AS item, ac.name AS category
              FROM itinerary_items i
              JOIN itinerary_days d       ON d.day_id = i.day_id
              JOIN trips t                ON t.trip_id = d.trip_id
              JOIN activity_categories ac ON ac.category_id = i.category_id
              LEFT JOIN bookings b        ON b.item_id = i.item_id
             WHERE ac.name IN ('Transport','Adventure') AND b.booking_id IS NULL
             ORDER BY d.day_date
        """,
        "params": [],
    },
    {
        "id": "Q12",
        "section": "Integrity",
        "title": "Owner-is-member integrity check",
        "note": "Expected: 0 rows. No constraint can enforce this, so the query proves it.",
        "sql": """
            SELECT t.trip_id, t.title FROM trips t
              LEFT JOIN trip_members tm ON tm.trip_id = t.trip_id
                   AND tm.user_id = t.owner_id AND tm.role = 'owner'
             WHERE tm.trip_id IS NULL
        """,
        "params": [],
    },
    # ---- 04_transport_demo.sql, Section B (T1-T7) ----
    {
        "id": "T1",
        "section": "Transport",
        "title": "Every transport leg of a trip (VIEW)",
        "note": "Goa: 5 legs (flight 95 min, cab 60, bus 25, cab 50, return flight 85).",
        "sql": """
            SELECT transport_id, transport_mode, carrier, route, depart_at,
                   duration_min, passengers, fare, status
              FROM v_trip_transport WHERE trip_id = %s ORDER BY depart_at
        """,
        "params": [1],
        "param_labels": ["trip_id"],
    },
    {
        "id": "T2",
        "section": "Transport",
        "title": "Spend per trip and mode",
        "note": "Goa: flight 17000, cab 2200, bus 40. Rajasthan: flight 7000, train 3000, cab 5000, metro 30.",
        "sql": """
            SELECT trip_title, transport_mode, COUNT(*) AS legs, SUM(fare) AS total_fare
              FROM v_trip_transport WHERE status <> 'cancelled'
             GROUP BY trip_id, trip_title, transport_mode ORDER BY trip_id, transport_mode
        """,
        "params": [],
    },
    {
        "id": "T3",
        "section": "Transport",
        "title": "Passenger manifest of a bus booking",
        "note": "Manali Volvo bus: 2 rows, Ananya L5 and Sneha L6.",
        "sql": """
            SELECT tp.passenger_no, tp.full_name, tp.age, tp.seat_no,
                   CONCAT(c.name, ', ', bd.bus_type, ' ', bd.bus_number) AS bus
              FROM transport_passengers tp
              JOIN transport_bookings tb ON tb.transport_id = tp.transport_id
              JOIN carriers c            ON c.carrier_id = tb.carrier_id
              JOIN bus_details bd        ON bd.transport_id = tb.transport_id
             WHERE tp.transport_id = %s ORDER BY tp.passenger_no
        """,
        "params": [13],
        "param_labels": ["transport_id"],
    },
    {
        "id": "T4",
        "section": "Transport",
        "title": "Transport items with NO transport booking",
        "note": "3 rows: the self-drive Hampi and Coorg trip.",
        "sql": """
            SELECT t.title AS trip, d.day_date, i.title AS item
              FROM itinerary_items i
              JOIN itinerary_days d       ON d.day_id = i.day_id
              JOIN trips t                ON t.trip_id = d.trip_id
              JOIN activity_categories ac ON ac.category_id = i.category_id
             WHERE ac.name = 'Transport'
               AND NOT EXISTS (SELECT 1 FROM transport_bookings tb WHERE tb.item_id = i.item_id)
             ORDER BY d.day_date
        """,
        "params": [],
    },
    {
        "id": "T5",
        "section": "Transport",
        "title": "Fare comparison by mode (cost per passenger)",
        "note": "flight 4000.00, cab 1092.31, bus 840.00, train 1000.00, metro 18.00 per passenger.",
        "sql": """
            SELECT transport_mode, COUNT(*) AS bookings, SUM(fare) AS total_fare,
                   ROUND(AVG(fare),2) AS avg_fare, SUM(passengers) AS passengers,
                   ROUND(SUM(fare)/SUM(passengers),2) AS fare_per_passenger
              FROM v_trip_transport WHERE status <> 'cancelled'
             GROUP BY transport_mode ORDER BY total_fare DESC
        """,
        "params": [],
    },
    {
        "id": "T6",
        "section": "Transport",
        "title": "Public transport vs private cab vs air (CASE)",
        "note": "Air 3 legs/24000, private cab 5/14200, public transport 6/8130.",
        "sql": """
            SELECT CASE WHEN transport_mode IN ('train','bus','metro') THEN 'Public transport'
                        WHEN transport_mode = 'flight' THEN 'Air' ELSE 'Private cab' END AS category,
                   COUNT(*) AS legs, SUM(fare) AS total_fare, SUM(passengers) AS passengers
              FROM v_trip_transport WHERE status <> 'cancelled'
             GROUP BY category ORDER BY total_fare DESC
        """,
        "params": [],
    },
    {
        "id": "T7",
        "section": "Transport",
        "title": "Share of each trip's budget spent on transport",
        "note": "Goa 19240 (32.1%), Rajasthan 15030 (17.7%), Munnar 7000 (17.5%), Manali 5060 (10.1%), Hampi 0.",
        "sql": """
            SELECT t.title, t.budget_total, COALESCE(SUM(tb.fare),0) AS transport_cost,
                   ROUND(100*COALESCE(SUM(tb.fare),0)/t.budget_total,1) AS pct_of_budget
              FROM trips t
              LEFT JOIN transport_bookings tb ON tb.trip_id = t.trip_id AND tb.status <> 'cancelled'
             GROUP BY t.trip_id, t.title, t.budget_total ORDER BY pct_of_budget DESC
        """,
        "params": [],
    },
    # ---- 06_demo_amenities_views_triggers.sql, Sections A and B ----
    {
        "id": "A1",
        "section": "Amenities",
        "title": "How many hotels offer each amenity, and how many free",
        "note": "Wi-Fi 8/7/1, Breakfast 7/6/1, Parking 6/6/0, Spa 5/0/5, Gym 0/0/0.",
        "sql": """
            SELECT a.name AS amenity, COUNT(ha.hotel_id) AS hotels_offering,
                   COALESCE(SUM(ha.is_complimentary),0) AS free_at,
                   COUNT(ha.hotel_id) - COALESCE(SUM(ha.is_complimentary),0) AS paid_at
              FROM amenities a LEFT JOIN hotel_amenities ha ON ha.amenity_id = a.amenity_id
             GROUP BY a.amenity_id, a.name ORDER BY hotels_offering DESC, a.name
        """,
        "params": [],
    },
    {
        "id": "A2",
        "section": "Amenities",
        "title": "Hotels offering BOTH free Wi-Fi and free parking",
        "note": "5 hotels; HAVING COUNT(DISTINCT amenity) = 2.",
        "sql": """
            SELECT p.name AS hotel, d.name AS destination
              FROM hotel_amenities ha
              JOIN amenities a    ON a.amenity_id = ha.amenity_id
              JOIN places p       ON p.place_id = ha.hotel_id
              JOIN destinations d ON d.destination_id = p.destination_id
             WHERE a.name IN ('Wi-Fi','Parking') AND ha.is_complimentary = TRUE
             GROUP BY p.place_id, p.name, d.name HAVING COUNT(DISTINCT a.name) = 2
             ORDER BY d.name
        """,
        "params": [],
    },
    {
        "id": "A3",
        "section": "Amenities",
        "title": "Amenity list per hotel (paid ones marked)",
        "note": "GROUP_CONCAT with a conditional label.",
        "sql": """
            SELECT p.name AS hotel, h.star_rating AS stars,
                   GROUP_CONCAT(CONCAT(a.name, IF(ha.is_complimentary, '', ' (paid)'))
                                ORDER BY a.name SEPARATOR ', ') AS amenities
              FROM hotels h
              JOIN places p           ON p.place_id = h.hotel_id
              JOIN hotel_amenities ha ON ha.hotel_id = h.hotel_id
              JOIN amenities a        ON a.amenity_id = ha.amenity_id
             GROUP BY h.hotel_id, p.name, h.star_rating ORDER BY h.star_rating DESC, p.name
        """,
        "params": [],
    },
    {
        "id": "B1",
        "section": "View",
        "title": "Trip timeline: transport + hotel + activities (VIEW)",
        "note": "Goa: 15 rows, 26 Dec 08:30 flight through 30 Dec 14:45 flight.",
        "sql": """
            SELECT happens_at, event_type, description, status
              FROM v_trip_timeline WHERE trip_id = %s ORDER BY happens_at
        """,
        "params": [1],
        "param_labels": ["trip_id"],
    },
    {
        "id": "B2",
        "section": "View",
        "title": "Budget dashboard: booked vs spent (VIEW)",
        "note": "Goa booked 45240 (75.4%); Rajasthan 37630 (44.3%); Munnar 20500 (51.3%); "
                "Hampi 14000 (40.0%); Manali 17060 (34.1%).",
        "sql": """
            SELECT trip_id, title, budget_total, hotel_booked, transport_booked, total_booked,
                   booked_pct_of_budget, actual_spend, remaining_budget
              FROM v_trip_cost_summary ORDER BY trip_id
        """,
        "params": [],
    },
]


# ---------------------------------------------------------------- rule tests
# Each test: id, title, sql, params, expect (the documented failure), kind.
# kind "reject" -> statement must fail; "count" -> runs and is compared/displayed.
# Everything the API runs for these is wrapped in a transaction that is rolled
# back, so a passing test never changes the data.
RULE_TESTS: list[dict] = [
    {
        "id": "C1", "section": "Core rules",
        "title": "Overlapping timed items on the same day",
        "expect": "ERROR 1644: Timed items on the same day must not overlap",
        "sql": "INSERT INTO itinerary_items (day_id, seq_no, category_id, title, start_time, end_time) "
               "VALUES (2, 9, 1, 'Clashing activity', '10:00', '11:00')",
        "params": [],
    },
    {
        "id": "C2", "section": "Core rules",
        "title": "Itinerary day outside the trip dates",
        "expect": "ERROR 1644: day_date is outside the trip dates",
        "sql": "INSERT INTO itinerary_days (trip_id, day_number, day_date) VALUES (1, 6, '2026-12-31')",
        "params": [],
    },
    {
        "id": "C3", "section": "Core rules",
        "title": "Double booking of the same room",
        "expect": "ERROR 1644: Room is already reserved for these dates",
        "sql": "INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, "
               "num_guests, rate_per_night) VALUES (1, 3, 2, '2026-12-28', '2026-12-30', 2, 7000)",
        "params": [],
    },
    {
        "id": "C4", "section": "Core rules",
        "title": "Too many guests for the room type",
        "expect": "ERROR 1644: Number of guests exceeds the room type capacity",
        "sql": "INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, "
               "num_guests, rate_per_night) VALUES (1, 4, 2, '2026-12-26', '2026-12-28', 5, 7000)",
        "params": [],
    },
    {
        "id": "C5", "section": "Core rules",
        "title": "Room under maintenance cannot be reserved",
        "expect": "ERROR 1644: Room is under maintenance and cannot be reserved",
        "sql": "INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, "
               "num_guests, rate_per_night) VALUES (1, 2, 2, '2026-12-26', '2026-12-28', 2, 4500)",
        "params": [],
    },
    {
        "id": "C6", "section": "Core rules",
        "title": "A viewer tries to book a room",
        "expect": "ERROR 1644: Only a trip owner or editor can book a room",
        "sql": "INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, "
               "num_guests, rate_per_night) VALUES (1, 4, 4, '2026-12-26', '2026-12-28', 2, 7000)",
        "params": [],
    },
    {
        "id": "C7", "section": "Core rules",
        "title": "Stay outside the trip dates",
        "expect": "ERROR 1644: Stay must be inside the trip dates",
        "sql": "INSERT INTO hotel_reservations (trip_id, room_id, booked_by, check_in, check_out, "
               "num_guests, rate_per_night) VALUES (1, 4, 2, '2027-02-01', '2027-02-03', 2, 7000)",
        "params": [],
    },
    {
        "id": "C8", "section": "Core rules",
        "title": "Review of a stay that is not completed",
        "expect": "ERROR 1644: Only a completed stay can be reviewed",
        "sql": "INSERT INTO hotel_reviews (reservation_id, rating) VALUES (6, 5)",
        "params": [],
    },
    {
        "id": "C9", "section": "Core rules",
        "title": "Expense linked to an item of another trip",
        "expect": "ERROR 1644: Expense item must belong to the same trip as the expense",
        "sql": "INSERT INTO expenses (trip_id, item_id, expense_category_id, paid_by, amount, expense_date) "
               "VALUES (2, 1, 1, 3, 500, '2026-11-10')",
        "params": [],
    },
    {
        "id": "C10", "section": "Core rules",
        "title": "Hotel row for a place that is not a Hotel",
        "expect": "ERROR 1644: A hotel row must point at a place whose place_type is Hotel",
        "sql": "INSERT INTO hotels (hotel_id, star_rating) VALUES (1, 3)",
        "params": [],
    },
    {
        "id": "C11a", "section": "Constraints",
        "title": "CHECK: rating above 5",
        "expect": "ERROR 3819: Check constraint 'chk_reviews_rating' is violated",
        "sql": "INSERT INTO reviews (user_id, destination_id, rating) VALUES (1, 2, 6)",
        "params": [],
    },
    {
        "id": "C11b", "section": "Constraints",
        "title": "CHECK: negative expense amount",
        "expect": "ERROR 3819: Check constraint 'chk_expenses_amount' is violated",
        "sql": "INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount, expense_date) "
               "VALUES (1, 1, 2, -50, '2026-10-01')",
        "params": [],
    },
    {
        "id": "C12", "section": "Constraints",
        "title": "UNIQUE: duplicate user email",
        "expect": "ERROR 1062: Duplicate entry for key 'uk_users_email'",
        "sql": "INSERT INTO users (email, password_hash, full_name) "
               "VALUES ('priya.nair@example.com','x','Dup')",
        "params": [],
    },
    {
        "id": "C13a", "section": "Referential actions",
        "title": "RESTRICT: delete a user who owns trips",
        "expect": "ERROR 1451: foreign key violation (RESTRICT)",
        "sql": "DELETE FROM users WHERE user_id = 2",
        "params": [],
    },
    {
        "id": "C13b", "section": "Referential actions",
        "title": "RESTRICT: delete an expense category in use",
        "expect": "ERROR 1451: foreign key violation (RESTRICT)",
        "sql": "DELETE FROM expense_categories WHERE expense_category_id = 1",
        "params": [],
    },
    {
        "id": "X1", "section": "Transport rules",
        "title": "Carrier type does not match the mode",
        "expect": "ERROR 1644: Carrier type does not match the transport mode",
        "sql": "INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, "
               "origin_station_id, destination_station_id, depart_at, arrive_at) "
               "VALUES (1, 'flight', 4, 2, 1, 2, '2026-12-27 08:00', '2026-12-27 09:30')",
        "params": [],
    },
    {
        "id": "X2", "section": "Transport rules",
        "title": "Same origin and destination station",
        "expect": "ERROR 1644: Origin and destination must be different",
        "sql": "INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, "
               "origin_station_id, destination_station_id, depart_at, arrive_at) "
               "VALUES (1, 'flight', 1, 2, 1, 1, '2026-12-27 08:00', '2026-12-27 09:30')",
        "params": [],
    },
    {
        "id": "X3", "section": "Transport rules",
        "title": "Station type does not match the mode",
        "expect": "ERROR 1644: Station type does not match the transport mode",
        "sql": "INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, "
               "origin_station_id, destination_station_id, depart_at, arrive_at) "
               "VALUES (5, 'bus', 8, 6, 1, 2, '2027-01-10 08:00', '2027-01-10 12:00')",
        "params": [],
    },
    {
        "id": "X4", "section": "Transport rules",
        "title": "A metro leg without stations",
        "expect": "ERROR 1644: This mode needs an origin and a destination station",
        "sql": "INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, "
               "depart_at, arrive_at) VALUES (5, 'metro', 10, 6, '2027-01-09 09:00', '2027-01-09 09:30')",
        "params": [],
    },
    {
        "id": "X5", "section": "Transport rules",
        "title": "CHECK: arrival before departure",
        "expect": "ERROR 3819: Check constraint 'chk_tb_times' is violated",
        "sql": "INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, "
               "depart_at, arrive_at) VALUES (1, 'cab', 4, 2, '2026-12-27 10:00', '2026-12-27 09:00')",
        "params": [],
    },
    {
        "id": "X6", "section": "Transport rules",
        "title": "A viewer tries to book transport",
        "expect": "ERROR 1644: Only a trip owner or editor can book transport",
        "sql": "INSERT INTO transport_bookings (trip_id, transport_mode, carrier_id, booked_by, "
               "depart_at, arrive_at) VALUES (1, 'cab', 4, 4, '2026-12-27 10:00', '2026-12-27 11:00')",
        "params": [],
    },
    {
        "id": "X7", "section": "Transport rules",
        "title": "Link a booking to an itinerary item of another trip",
        "expect": "ERROR 1644: Itinerary item belongs to a different trip",
        "sql": "INSERT INTO transport_bookings (trip_id, item_id, transport_mode, carrier_id, booked_by, "
               "depart_at, arrive_at) VALUES (2, 1, 'cab', 5, 3, '2026-11-11 10:00', '2026-11-11 11:00')",
        "params": [],
    },
    {
        "id": "X8", "section": "Transport rules",
        "title": "Subtype guard: bus details on a metro booking",
        "expect": "ERROR 1644: bus_details requires a booking whose mode is bus",
        "sql": "INSERT INTO bus_details (transport_id, bus_type) VALUES (7, 'ordinary')",
        "params": [],
    },
    {
        "id": "X9", "section": "Transport rules",
        "title": "UNIQUE: same seat twice on one booking",
        "expect": "ERROR 1062: Duplicate entry for key 'uk_tp_seat'",
        "sql": "INSERT INTO transport_passengers (transport_id, passenger_no, full_name, seat_no) "
               "VALUES (1, 3, 'Extra Guest', '14A')",
        "params": [],
    },
    {
        "id": "X10", "section": "Transport rules",
        "title": "RESTRICT: delete a carrier in use",
        "expect": "ERROR 1451: foreign key violation (RESTRICT)",
        "sql": "DELETE FROM carriers WHERE carrier_id = 1",
        "params": [],
    },
]


# ---------------------------------------------------------------- cascade demos
# These succeed; the API counts before and after inside one rolled-back
# transaction, so the dashboard can show CASCADE / SET NULL behaving.
CASCADE_DEMOS: list[dict] = [
    {
        "id": "C14",
        "section": "Referential actions",
        "title": "CASCADE: deleting a trip removes its children",
        "description": "DELETE FROM trips WHERE trip_id = 5 cascades to members, days, "
                       "items, bookings, expenses and reservations.",
        "before_sql": "SELECT (SELECT COUNT(*) FROM itinerary_days WHERE trip_id=5) AS days, "
                      "(SELECT COUNT(*) FROM expenses WHERE trip_id=5) AS expenses, "
                      "(SELECT COUNT(*) FROM hotel_reservations WHERE trip_id=5) AS reservations",
        "delete_sql": "DELETE FROM trips WHERE trip_id = 5",
        "after_sql": "SELECT (SELECT COUNT(*) FROM itinerary_days WHERE trip_id=5) AS days, "
                     "(SELECT COUNT(*) FROM expenses WHERE trip_id=5) AS expenses, "
                     "(SELECT COUNT(*) FROM hotel_reservations WHERE trip_id=5) AS reservations",
    },
    {
        "id": "A4",
        "section": "Referential actions",
        "title": "CASCADE on the M:N link: delete an amenity",
        "description": "Deleting Spa removes all 5 hotel_amenities links.",
        "before_sql": "SELECT COUNT(*) AS links FROM hotel_amenities "
                      "WHERE amenity_id = (SELECT amenity_id FROM amenities WHERE name='Spa')",
        "delete_sql": "DELETE FROM amenities WHERE name = 'Spa'",
        "after_sql": "SELECT COUNT(*) AS links FROM hotel_amenities WHERE amenity_id = 5",
    },
    {
        "id": "X11",
        "section": "Referential actions",
        "title": "CASCADE: deleting a trip removes transport legs",
        "description": "Trip 3's 2 cab legs, cab_details rows and 6 passengers all go.",
        "before_sql": "SELECT (SELECT COUNT(*) FROM transport_bookings WHERE trip_id=3) AS legs, "
                      "(SELECT COUNT(*) FROM cab_details WHERE transport_id IN (10,11)) AS cab_rows, "
                      "(SELECT COUNT(*) FROM transport_passengers WHERE transport_id IN (10,11)) AS passengers",
        "delete_sql": "DELETE FROM trips WHERE trip_id = 3",
        "after_sql": "SELECT (SELECT COUNT(*) FROM transport_bookings WHERE trip_id=3) AS legs, "
                     "(SELECT COUNT(*) FROM cab_details WHERE transport_id IN (10,11)) AS cab_rows, "
                     "(SELECT COUNT(*) FROM transport_passengers WHERE transport_id IN (10,11)) AS passengers",
    },
    {
        "id": "SETNULL",
        "section": "Referential actions",
        "title": "SET NULL: deleting a place keeps its itinerary items",
        "description": "Deleting place 2 (Fort Aguada) sets itinerary_items.place_id to NULL.",
        "before_sql": "SELECT item_id, title, place_id FROM itinerary_items WHERE place_id = 2",
        "delete_sql": "DELETE FROM places WHERE place_id = 2",
        "after_sql": "SELECT item_id, title, place_id FROM itinerary_items WHERE title = 'Visit Fort Aguada'",
    },
]


# ---------------------------------------------------------------- alert demo
# 06 Section C: AFTER triggers raise budget alerts. Steps run in order inside a
# single rolled-back transaction.
ALERT_DEMO = {
    "title": "Budget alerts (AFTER triggers)",
    "description": "Trip 4 (Hampi) has budget 35000 and 22100 already spent. Each step "
                   "adds an expense and the AFTER trigger raises at most one alert per type.",
    "steps": [
        {"label": "Add 10000 -> reaches 80% of budget",
         "sql": "INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount, expense_date, description) "
                "VALUES (4, 6, 5, 10000, '2026-10-22', 'Test: souvenirs and coffee beans')",
         "expect": "budget_80 alert: spending 32100.00 reached 80% of 35000.00"},
        {"label": "Add 5000 more -> passes the budget",
         "sql": "INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount, expense_date, description) "
                "VALUES (4, 6, 5, 5000, '2026-10-22', 'Test: extra night stay')",
         "expect": "budget_exceeded alert: spending 37100.00 exceeded 35000.00"},
        {"label": "Add 100 more -> no duplicate alert",
         "sql": "INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount, expense_date, description) "
                "VALUES (4, 1, 5, 100, '2026-10-22', 'Test: parking')",
         "expect": "still 2 alerts (UNIQUE (trip_id, alert_type) plus INSERT IGNORE)"},
    ],
    "read_sql": "SELECT trip_id, alert_type, message FROM trip_alerts ORDER BY alert_id",
}


# ---------------------------------------------------------------- audit demo
# 06 Section C: AFTER triggers write the audit trail.
AUDIT_DEMO = {
    "title": "Audit trail (AFTER triggers)",
    "description": "Four updates and one delete each write a row into audit_log.",
    "steps": [
        {"label": "expenses 4: amount 3500 -> 4000",
         "sql": "UPDATE expenses SET amount = 4000 WHERE expense_id = 4"},
        {"label": "trips 1: budget 60000 -> 65000 and status planned -> ongoing",
         "sql": "UPDATE trips SET budget_total = 65000, status = 'ongoing' WHERE trip_id = 1"},
        {"label": "transport_bookings 9: status pending -> cancelled",
         "sql": "UPDATE transport_bookings SET status = 'cancelled' WHERE transport_id = 9"},
        {"label": "hotel_reservations 3: status pending -> confirmed",
         "sql": "UPDATE hotel_reservations SET status = 'confirmed' WHERE reservation_id = 3"},
        {"label": "expenses 7: DELETE",
         "sql": "DELETE FROM expenses WHERE expense_id = 7"},
    ],
    "read_sql": "SELECT audit_id, table_name, record_id, action, field_name, old_value, new_value "
                "FROM audit_log ORDER BY audit_id",
}
