-- =====================================================================
--  ONE-CLICK BUILD: runs scripts 01 + 03 + 05 in order.
--  Result: 32 tables, 41 foreign keys, 31 triggers, 4 views, 399 sample rows.
--  Open in MySQL Workbench and press the lightning-bolt (Execute) once.
-- =====================================================================

-- =====================================================================
--  TRAVEL ITINERARY AND EXPENSE ORGANIZER  (travel_itinerary_db, version 2)
--  Implements the 21-entity ER diagram: tables, 27 foreign keys,
--  12 triggers, 1 view, 2 stored procedures and sample data.
--
--  Target : MySQL 8.0.16+ or MySQL 8.4 LTS (CHECK constraints are enforced
--           from 8.0.16).  Run this whole file once in MySQL Workbench
--           (File > Open SQL Script > lightning-bolt "Execute").
--  NOTE   : It starts with DROP DATABASE, so it rebuilds from scratch.
-- =====================================================================
DROP DATABASE IF EXISTS travel_itinerary_db;
CREATE DATABASE travel_itinerary_db CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE travel_itinerary_db;

-- ---------------------------- PEOPLE ---------------------------------
CREATE TABLE users (
  user_id       INT AUTO_INCREMENT PRIMARY KEY,
  email         VARCHAR(100) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name     VARCHAR(80)  NOT NULL,
  role          ENUM('user','admin') NOT NULL DEFAULT 'user',
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_users_email UNIQUE (email)
) ENGINE=InnoDB;

-- ------------------- CATALOGUE: DESTINATIONS / PLACES -----------------
CREATE TABLE destinations (
  destination_id INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(80) NOT NULL,
  country     VARCHAR(60) NOT NULL,
  description TEXT NULL,
  best_season VARCHAR(40) NULL,
  CONSTRAINT uk_dest_name_country UNIQUE (name, country)
) ENGINE=InnoDB;

CREATE TABLE places (
  place_id       INT AUTO_INCREMENT PRIMARY KEY,
  destination_id INT NOT NULL,
  name           VARCHAR(100) NOT NULL,
  address        VARCHAR(200) NULL,
  place_type     VARCHAR(40) NULL,
  CONSTRAINT uk_places_dest_name UNIQUE (destination_id, name),
  CONSTRAINT fk_places_destination FOREIGN KEY (destination_id)
    REFERENCES destinations(destination_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE activity_categories (
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  name        VARCHAR(40) NOT NULL,
  CONSTRAINT uk_actcat_name UNIQUE (name)
) ENGINE=InnoDB;

CREATE TABLE expense_categories (
  expense_category_id INT AUTO_INCREMENT PRIMARY KEY,
  name                VARCHAR(40) NOT NULL,
  CONSTRAINT uk_expcat_name UNIQUE (name)
) ENGINE=InnoDB;

CREATE TABLE amenities (
  amenity_id INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(40) NOT NULL,
  CONSTRAINT uk_amenities_name UNIQUE (name)
) ENGINE=InnoDB;

-- -------------------------- TRIP PLANNING -----------------------------
CREATE TABLE trips (
  trip_id      INT AUTO_INCREMENT PRIMARY KEY,
  owner_id     INT NOT NULL,
  title        VARCHAR(100) NOT NULL,
  start_date   DATE NOT NULL,
  end_date     DATE NOT NULL,
  budget_total DECIMAL(10,2) NOT NULL DEFAULT 0,
  status       ENUM('planned','ongoing','completed','cancelled') NOT NULL DEFAULT 'planned',
  is_public    BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT chk_trips_budget CHECK (budget_total >= 0),
  CONSTRAINT chk_trips_dates  CHECK (end_date >= start_date),
  CONSTRAINT fk_trips_owner FOREIGN KEY (owner_id)
    REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE trip_members (
  trip_id   INT NOT NULL,
  user_id   INT NOT NULL,
  role      ENUM('owner','editor','viewer') NOT NULL DEFAULT 'viewer',
  joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (trip_id, user_id),
  CONSTRAINT fk_tm_trip FOREIGN KEY (trip_id) REFERENCES trips(trip_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_tm_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE itinerary_days (
  day_id     INT AUTO_INCREMENT PRIMARY KEY,
  trip_id    INT NOT NULL,
  day_number INT NOT NULL,
  day_date   DATE NOT NULL,
  notes      VARCHAR(255) NULL,
  CONSTRAINT uk_days_date UNIQUE (trip_id, day_date),
  CONSTRAINT uk_days_num  UNIQUE (trip_id, day_number),
  CONSTRAINT chk_days_num CHECK (day_number >= 1),
  CONSTRAINT fk_days_trip FOREIGN KEY (trip_id) REFERENCES trips(trip_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE itinerary_items (
  item_id        INT AUTO_INCREMENT PRIMARY KEY,
  day_id         INT NOT NULL,
  seq_no         INT NOT NULL,
  category_id    INT NOT NULL,
  place_id       INT NULL,
  title          VARCHAR(100) NOT NULL,
  start_time     TIME NULL,
  end_time       TIME NULL,
  estimated_cost DECIMAL(10,2) NOT NULL DEFAULT 0,
  status         ENUM('planned','done','skipped') NOT NULL DEFAULT 'planned',
  notes          TEXT NULL,
  CONSTRAINT uk_items_day_seq UNIQUE (day_id, seq_no),
  CONSTRAINT chk_items_cost CHECK (estimated_cost >= 0),
  CONSTRAINT chk_items_seq  CHECK (seq_no >= 1),
  CONSTRAINT chk_items_time CHECK (start_time IS NULL OR end_time IS NULL OR end_time > start_time),
  CONSTRAINT fk_items_day      FOREIGN KEY (day_id)      REFERENCES itinerary_days(day_id)           ON DELETE CASCADE  ON UPDATE CASCADE,
  CONSTRAINT fk_items_category FOREIGN KEY (category_id) REFERENCES activity_categories(category_id) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_items_place    FOREIGN KEY (place_id)    REFERENCES places(place_id)                 ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE bookings (
  booking_id        INT AUTO_INCREMENT PRIMARY KEY,
  item_id           INT NOT NULL,
  provider          VARCHAR(80) NOT NULL,
  confirmation_code VARCHAR(40) NULL,
  status            ENUM('pending','confirmed','cancelled') NOT NULL DEFAULT 'pending',
  amount            DECIMAL(10,2) NOT NULL DEFAULT 0,
  CONSTRAINT uk_bookings_item UNIQUE (item_id),
  CONSTRAINT chk_bookings_amount CHECK (amount >= 0),
  CONSTRAINT fk_bookings_item FOREIGN KEY (item_id) REFERENCES itinerary_items(item_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ------------------------------- MONEY --------------------------------
CREATE TABLE expenses (
  expense_id          INT AUTO_INCREMENT PRIMARY KEY,
  trip_id             INT NOT NULL,
  item_id             INT NULL,
  expense_category_id INT NOT NULL,
  paid_by             INT NOT NULL,
  amount              DECIMAL(10,2) NOT NULL,
  expense_date        DATE NOT NULL,
  description         VARCHAR(200) NULL,
  CONSTRAINT chk_expenses_amount CHECK (amount > 0),
  CONSTRAINT fk_exp_trip     FOREIGN KEY (trip_id)             REFERENCES trips(trip_id)                         ON DELETE CASCADE  ON UPDATE CASCADE,
  CONSTRAINT fk_exp_item     FOREIGN KEY (item_id)             REFERENCES itinerary_items(item_id)               ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_exp_category FOREIGN KEY (expense_category_id) REFERENCES expense_categories(expense_category_id) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_exp_payer    FOREIGN KEY (paid_by)             REFERENCES users(user_id)                         ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ----------------------------- COMMUNITY ------------------------------
CREATE TABLE reviews (
  user_id        INT NOT NULL,
  destination_id INT NOT NULL,
  rating         TINYINT NOT NULL,
  comment        TEXT NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, destination_id),
  CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5),
  CONSTRAINT fk_rev_user FOREIGN KEY (user_id)        REFERENCES users(user_id)               ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_rev_dest FOREIGN KEY (destination_id) REFERENCES destinations(destination_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE saved_destinations (
  user_id        INT NOT NULL,
  destination_id INT NOT NULL,
  saved_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, destination_id),
  CONSTRAINT fk_sd_user FOREIGN KEY (user_id)        REFERENCES users(user_id)               ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_sd_dest FOREIGN KEY (destination_id) REFERENCES destinations(destination_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ------------------------ HOTEL BOOKING MODULE ------------------------
-- IS-A: a hotel is a special kind of place (shares the place's primary key)
CREATE TABLE hotels (
  hotel_id       INT NOT NULL PRIMARY KEY,
  star_rating    TINYINT NOT NULL,
  phone          VARCHAR(20) NULL,
  email          VARCHAR(100) NULL,
  check_in_time  TIME NOT NULL DEFAULT '14:00:00',
  check_out_time TIME NOT NULL DEFAULT '11:00:00',
  CONSTRAINT chk_hotels_star CHECK (star_rating BETWEEN 1 AND 5),
  CONSTRAINT fk_hotels_place FOREIGN KEY (hotel_id) REFERENCES places(place_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE hotel_amenities (
  hotel_id        INT NOT NULL,
  amenity_id      INT NOT NULL,
  is_complimentary BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (hotel_id, amenity_id),
  CONSTRAINT fk_ha_hotel   FOREIGN KEY (hotel_id)   REFERENCES hotels(hotel_id)     ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_ha_amenity FOREIGN KEY (amenity_id) REFERENCES amenities(amenity_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE room_types (
  room_type_id  INT AUTO_INCREMENT PRIMARY KEY,
  hotel_id      INT NOT NULL,
  name          VARCHAR(60) NOT NULL,
  bed_type      ENUM('single','twin','double','queen','king') NOT NULL,
  max_occupancy INT NOT NULL,
  base_rate     DECIMAL(10,2) NOT NULL,
  CONSTRAINT uk_rt_hotel_name UNIQUE (hotel_id, name),
  CONSTRAINT uk_rt_id_hotel   UNIQUE (room_type_id, hotel_id),   -- target of rooms' composite FK
  CONSTRAINT chk_rt_occ  CHECK (max_occupancy >= 1),
  CONSTRAINT chk_rt_rate CHECK (base_rate >= 0),
  CONSTRAINT fk_rt_hotel FOREIGN KEY (hotel_id) REFERENCES hotels(hotel_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE rooms (
  room_id      INT AUTO_INCREMENT PRIMARY KEY,
  hotel_id     INT NOT NULL,
  room_type_id INT NOT NULL,
  room_number  VARCHAR(10) NOT NULL,
  floor_no     INT NOT NULL,
  status       ENUM('available','maintenance') NOT NULL DEFAULT 'available',
  CONSTRAINT uk_rooms_hotel_number UNIQUE (hotel_id, room_number),
  CONSTRAINT chk_rooms_floor CHECK (floor_no >= 0),
  -- composite FK: a room's hotel must be the hotel of its room type
  CONSTRAINT fk_rooms_type_hotel FOREIGN KEY (room_type_id, hotel_id)
    REFERENCES room_types(room_type_id, hotel_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE hotel_reservations (
  reservation_id    INT AUTO_INCREMENT PRIMARY KEY,
  trip_id           INT NOT NULL,
  room_id           INT NOT NULL,
  booked_by         INT NOT NULL,
  check_in          DATE NOT NULL,
  check_out         DATE NOT NULL,
  num_guests        INT NOT NULL,
  rate_per_night    DECIMAL(10,2) NOT NULL,   -- price snapshot at booking time
  status            ENUM('pending','confirmed','cancelled','checked_in','completed') NOT NULL DEFAULT 'pending',
  confirmation_code VARCHAR(20) NULL,
  special_requests  VARCHAR(255) NULL,
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_res_code UNIQUE (confirmation_code),
  CONSTRAINT chk_res_dates  CHECK (check_out > check_in),
  CONSTRAINT chk_res_guests CHECK (num_guests >= 1),
  CONSTRAINT chk_res_rate   CHECK (rate_per_night >= 0),
  INDEX idx_res_room_dates (room_id, check_in, check_out),
  CONSTRAINT fk_res_trip   FOREIGN KEY (trip_id)   REFERENCES trips(trip_id) ON DELETE CASCADE  ON UPDATE CASCADE,
  CONSTRAINT fk_res_room   FOREIGN KEY (room_id)   REFERENCES rooms(room_id) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_res_booker FOREIGN KEY (booked_by) REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- WEAK ENTITY: payment_no is only a partial key, identified through the reservation
CREATE TABLE hotel_payments (
  reservation_id  INT NOT NULL,
  payment_no      INT NOT NULL,
  amount          DECIMAL(10,2) NOT NULL,
  method          ENUM('card','upi','netbanking','cash') NOT NULL,
  status          ENUM('success','failed','refunded') NOT NULL,
  transaction_ref VARCHAR(40) NULL,
  paid_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (reservation_id, payment_no),
  CONSTRAINT chk_pay_amount CHECK (amount > 0),
  CONSTRAINT chk_pay_no     CHECK (payment_no >= 1),
  CONSTRAINT fk_pay_res FOREIGN KEY (reservation_id) REFERENCES hotel_reservations(reservation_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- WEAK ENTITY (1:1): one review per reservation, key = reservation_id
CREATE TABLE hotel_reviews (
  reservation_id INT NOT NULL PRIMARY KEY,
  rating         TINYINT NOT NULL,
  title          VARCHAR(100) NULL,
  comment        TEXT NULL,
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_hrev_rating CHECK (rating BETWEEN 1 AND 5),
  CONSTRAINT fk_hrev_res FOREIGN KEY (reservation_id) REFERENCES hotel_reservations(reservation_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ======================= TRIGGERS (6 families x insert/update = 12) =======================
DELIMITER $$

CREATE TRIGGER trg_exp_item_trip_bi BEFORE INSERT ON expenses FOR EACH ROW
BEGIN
  DECLARE v_item_trip INT;
  IF NEW.item_id IS NOT NULL THEN
    SELECT d.trip_id INTO v_item_trip
      FROM itinerary_items i JOIN itinerary_days d ON d.day_id = i.day_id
     WHERE i.item_id = NEW.item_id;
    IF v_item_trip <> NEW.trip_id THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expense item must belong to the same trip as the expense';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_exp_item_trip_bu BEFORE UPDATE ON expenses FOR EACH ROW
BEGIN
  DECLARE v_item_trip INT;
  IF NEW.item_id IS NOT NULL THEN
    SELECT d.trip_id INTO v_item_trip
      FROM itinerary_items i JOIN itinerary_days d ON d.day_id = i.day_id
     WHERE i.item_id = NEW.item_id;
    IF v_item_trip <> NEW.trip_id THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expense item must belong to the same trip as the expense';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_hotels_place_type_bi BEFORE INSERT ON hotels FOR EACH ROW
BEGIN
  DECLARE v_type VARCHAR(40);
  SELECT place_type INTO v_type FROM places WHERE place_id = NEW.hotel_id;
  IF v_type IS NULL OR v_type <> 'Hotel' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A hotel row must point at a place whose place_type is Hotel';
  END IF;
END$$

CREATE TRIGGER trg_hotels_place_type_bu BEFORE UPDATE ON hotels FOR EACH ROW
BEGIN
  DECLARE v_type VARCHAR(40);
  SELECT place_type INTO v_type FROM places WHERE place_id = NEW.hotel_id;
  IF v_type IS NULL OR v_type <> 'Hotel' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A hotel row must point at a place whose place_type is Hotel';
  END IF;
END$$

CREATE TRIGGER trg_res_validate_bi BEFORE INSERT ON hotel_reservations FOR EACH ROW
BEGIN
  DECLARE v_room_status VARCHAR(20);
  DECLARE v_cap INT;
  DECLARE v_ts DATE;
  DECLARE v_te DATE;
  DECLARE v_cnt INT;
  IF NEW.status <> 'cancelled' THEN
    -- room must exist, not be under maintenance, and fit the guests
    SELECT r.status, rt.max_occupancy INTO v_room_status, v_cap
      FROM rooms r
      JOIN room_types rt ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id
     WHERE r.room_id = NEW.room_id;
    IF v_room_status = 'maintenance' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room is under maintenance and cannot be reserved';
    END IF;
    IF NEW.num_guests > v_cap THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Number of guests exceeds the room type capacity';
    END IF;
    -- stay must lie inside the trip dates (check-out may be the day after the last day)
    SELECT start_date, end_date INTO v_ts, v_te FROM trips WHERE trip_id = NEW.trip_id;
    IF NEW.check_in < v_ts OR NEW.check_out > DATE_ADD(v_te, INTERVAL 1 DAY) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stay must be inside the trip dates';
    END IF;
    -- only an owner or editor of the trip may book
    SELECT COUNT(*) INTO v_cnt FROM trip_members
     WHERE trip_id = NEW.trip_id AND user_id = NEW.booked_by AND role IN ('owner','editor');
    IF v_cnt = 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a trip owner or editor can book a room';
    END IF;
    -- no double booking of the same room on overlapping nights
    SELECT COUNT(*) INTO v_cnt FROM hotel_reservations h
     WHERE h.room_id = NEW.room_id AND h.status <> 'cancelled'
       AND h.reservation_id <> COALESCE(NEW.reservation_id, 0)
       AND NEW.check_in < h.check_out AND NEW.check_out > h.check_in;
    IF v_cnt > 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room is already reserved for these dates';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_res_validate_bu BEFORE UPDATE ON hotel_reservations FOR EACH ROW
BEGIN
  DECLARE v_room_status VARCHAR(20);
  DECLARE v_cap INT;
  DECLARE v_ts DATE;
  DECLARE v_te DATE;
  DECLARE v_cnt INT;
  IF NEW.status <> 'cancelled' THEN
    -- room must exist, not be under maintenance, and fit the guests
    SELECT r.status, rt.max_occupancy INTO v_room_status, v_cap
      FROM rooms r
      JOIN room_types rt ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id
     WHERE r.room_id = NEW.room_id;
    IF v_room_status = 'maintenance' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room is under maintenance and cannot be reserved';
    END IF;
    IF NEW.num_guests > v_cap THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Number of guests exceeds the room type capacity';
    END IF;
    -- stay must lie inside the trip dates (check-out may be the day after the last day)
    SELECT start_date, end_date INTO v_ts, v_te FROM trips WHERE trip_id = NEW.trip_id;
    IF NEW.check_in < v_ts OR NEW.check_out > DATE_ADD(v_te, INTERVAL 1 DAY) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stay must be inside the trip dates';
    END IF;
    -- only an owner or editor of the trip may book
    SELECT COUNT(*) INTO v_cnt FROM trip_members
     WHERE trip_id = NEW.trip_id AND user_id = NEW.booked_by AND role IN ('owner','editor');
    IF v_cnt = 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a trip owner or editor can book a room';
    END IF;
    -- no double booking of the same room on overlapping nights
    SELECT COUNT(*) INTO v_cnt FROM hotel_reservations h
     WHERE h.room_id = NEW.room_id AND h.status <> 'cancelled'
       AND h.reservation_id <> COALESCE(NEW.reservation_id, 0)
       AND NEW.check_in < h.check_out AND NEW.check_out > h.check_in;
    IF v_cnt > 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room is already reserved for these dates';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_hreview_completed_bi BEFORE INSERT ON hotel_reviews FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(20);
  SELECT status INTO v_status FROM hotel_reservations WHERE reservation_id = NEW.reservation_id;
  IF v_status IS NULL OR v_status <> 'completed' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a completed stay can be reviewed';
  END IF;
END$$

CREATE TRIGGER trg_hreview_completed_bu BEFORE UPDATE ON hotel_reviews FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(20);
  SELECT status INTO v_status FROM hotel_reservations WHERE reservation_id = NEW.reservation_id;
  IF v_status IS NULL OR v_status <> 'completed' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a completed stay can be reviewed';
  END IF;
END$$

CREATE TRIGGER trg_days_validate_bi BEFORE INSERT ON itinerary_days FOR EACH ROW
BEGIN
  DECLARE v_start DATE;
  DECLARE v_end DATE;
  SELECT start_date, end_date INTO v_start, v_end FROM trips WHERE trip_id = NEW.trip_id;
  IF v_start IS NOT NULL THEN
    IF NEW.day_date <> DATE_ADD(v_start, INTERVAL NEW.day_number - 1 DAY) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'day_date must equal trip start_date + day_number - 1';
    END IF;
    IF NEW.day_date > v_end THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'day_date is outside the trip dates';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_days_validate_bu BEFORE UPDATE ON itinerary_days FOR EACH ROW
BEGIN
  DECLARE v_start DATE;
  DECLARE v_end DATE;
  SELECT start_date, end_date INTO v_start, v_end FROM trips WHERE trip_id = NEW.trip_id;
  IF v_start IS NOT NULL THEN
    IF NEW.day_date <> DATE_ADD(v_start, INTERVAL NEW.day_number - 1 DAY) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'day_date must equal trip start_date + day_number - 1';
    END IF;
    IF NEW.day_date > v_end THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'day_date is outside the trip dates';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_items_no_overlap_bi BEFORE INSERT ON itinerary_items FOR EACH ROW
BEGIN
  DECLARE v_cnt INT;
  IF NEW.start_time IS NOT NULL AND NEW.end_time IS NOT NULL THEN
    SELECT COUNT(*) INTO v_cnt FROM itinerary_items i
     WHERE i.day_id = NEW.day_id
       AND i.item_id <> COALESCE(NEW.item_id, 0)
       AND i.start_time IS NOT NULL AND i.end_time IS NOT NULL
       AND NEW.start_time < i.end_time AND NEW.end_time > i.start_time;
    IF v_cnt > 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Timed items on the same day must not overlap';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_items_no_overlap_bu BEFORE UPDATE ON itinerary_items FOR EACH ROW
BEGIN
  DECLARE v_cnt INT;
  IF NEW.start_time IS NOT NULL AND NEW.end_time IS NOT NULL THEN
    SELECT COUNT(*) INTO v_cnt FROM itinerary_items i
     WHERE i.day_id = NEW.day_id
       AND i.item_id <> COALESCE(NEW.item_id, 0)
       AND i.start_time IS NOT NULL AND i.end_time IS NOT NULL
       AND NEW.start_time < i.end_time AND NEW.end_time > i.start_time;
    IF v_cnt > 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Timed items on the same day must not overlap';
    END IF;
  END IF;
END$$

-- ================= STORED PROCEDURES (transactions) =================
CREATE PROCEDURE sp_create_trip(
  IN p_owner INT, IN p_title VARCHAR(100), IN p_start DATE, IN p_end DATE,
  IN p_budget DECIMAL(10,2), OUT p_trip_id INT)
BEGIN
  DECLARE v_n INT DEFAULT 1;
  DECLARE v_days INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  INSERT INTO trips (owner_id, title, start_date, end_date, budget_total)
  VALUES (p_owner, p_title, p_start, p_end, p_budget);
  SET p_trip_id = LAST_INSERT_ID();
  -- application rule: the owner is also a member with role 'owner'
  INSERT INTO trip_members (trip_id, user_id, role) VALUES (p_trip_id, p_owner, 'owner');
  SET v_days = DATEDIFF(p_end, p_start) + 1;
  WHILE v_n <= v_days DO
    INSERT INTO itinerary_days (trip_id, day_number, day_date)
    VALUES (p_trip_id, v_n, DATE_ADD(p_start, INTERVAL v_n - 1 DAY));
    SET v_n = v_n + 1;
  END WHILE;
  COMMIT;
END$$

CREATE PROCEDURE sp_book_room(
  IN p_trip_id INT, IN p_room_id INT, IN p_booked_by INT,
  IN p_check_in DATE, IN p_check_out DATE, IN p_guests INT, OUT p_reservation_id INT)
BEGIN
  DECLARE v_room INT;
  DECLARE v_rate DECIMAL(10,2);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  -- lock the room row so two people cannot take the same room at once
  SELECT r.room_id, rt.base_rate INTO v_room, v_rate
    FROM rooms r
    JOIN room_types rt ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id
   WHERE r.room_id = p_room_id
     FOR UPDATE;
  INSERT INTO hotel_reservations
    (trip_id, room_id, booked_by, check_in, check_out, num_guests, rate_per_night, status)
  VALUES (p_trip_id, p_room_id, p_booked_by, p_check_in, p_check_out, p_guests, v_rate, 'pending');
  SET p_reservation_id = LAST_INSERT_ID();
  UPDATE hotel_reservations
     SET confirmation_code = CONCAT('HB', LPAD(p_reservation_id, 6, '0'))
   WHERE reservation_id = p_reservation_id;
  COMMIT;
END$$

DELIMITER ;

-- ============================== VIEW ================================
-- Derived hotel figures are computed here, never stored.
CREATE VIEW v_reservation_summary AS
SELECT hr.reservation_id,
       hr.confirmation_code,
       hr.trip_id,
       t.title                                         AS trip_title,
       p.name                                          AS hotel_name,
       d.name                                          AS destination,
       r.room_number,
       rt.name                                         AS room_type,
       hr.check_in,
       hr.check_out,
       DATEDIFF(hr.check_out, hr.check_in)             AS nights,
       hr.rate_per_night,
       DATEDIFF(hr.check_out, hr.check_in) * hr.rate_per_night AS total_cost,
       COALESCE(pay.amount_paid, 0)                    AS amount_paid,
       CASE WHEN hr.status = 'cancelled' THEN 0        -- nothing is owed on a cancelled stay
            ELSE DATEDIFF(hr.check_out, hr.check_in) * hr.rate_per_night - COALESCE(pay.amount_paid, 0)
       END                                             AS balance_due,
       hr.status
  FROM hotel_reservations hr
  JOIN trips t         ON t.trip_id = hr.trip_id
  JOIN rooms r         ON r.room_id = hr.room_id
  JOIN room_types rt   ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id
  JOIN hotels h        ON h.hotel_id = r.hotel_id
  JOIN places p        ON p.place_id = h.hotel_id
  JOIN destinations d  ON d.destination_id = p.destination_id
  LEFT JOIN (SELECT reservation_id, SUM(amount) AS amount_paid
               FROM hotel_payments WHERE status = 'success'
              GROUP BY reservation_id) pay ON pay.reservation_id = hr.reservation_id;

-- ============================ SAMPLE DATA ============================
-- Insert order follows the foreign keys (parents first).
-- Passwords are SHA2 demo hashes only. A real app must use bcrypt/argon2.
INSERT INTO users (user_id, email, password_hash, full_name, role) VALUES
  (1, 'aarav.sharma@example.com', SHA2('Aarav@123',256), 'Aarav Sharma', 'admin'),
  (2, 'priya.nair@example.com', SHA2('Priya@123',256), 'Priya Nair', 'user'),
  (3, 'rohan.mehta@example.com', SHA2('Rohan@123',256), 'Rohan Mehta', 'user'),
  (4, 'sneha.iyer@example.com', SHA2('Sneha@123',256), 'Sneha Iyer', 'user'),
  (5, 'karthik.reddy@example.com', SHA2('Karthik@123',256), 'Karthik Reddy', 'user'),
  (6, 'ananya.das@example.com', SHA2('Ananya@123',256), 'Ananya Das', 'user');

INSERT INTO destinations (destination_id, name, country, description, best_season) VALUES
  (1, 'Goa', 'India', 'Sun, sand and seafood on the Konkan coast.', 'November to February'),
  (2, 'Jaipur', 'India', 'The Pink City: forts, palaces and bazaars.', 'October to March'),
  (3, 'Munnar', 'India', 'Rolling tea estates in the Western Ghats.', 'September to May'),
  (4, 'Manali', 'India', 'Himalayan valley town for snow and adventure.', 'December to February'),
  (5, 'Hampi', 'India', 'Boulder-strewn UNESCO ruins of Vijayanagara.', 'October to February'),
  (6, 'Coorg', 'India', 'Coffee country with waterfalls and misty hills.', 'October to March'),
  (7, 'Udaipur', 'India', 'The City of Lakes with palaces on the water.', 'September to March');

INSERT INTO places (place_id, destination_id, name, address, place_type) VALUES
  (1, 1, 'Baga Beach', 'Baga, Bardez, Goa', 'Beach'),
  (2, 1, 'Fort Aguada', 'Candolim, Bardez, Goa', 'Fort'),
  (3, 1, 'Seaside Palms Resort', 'Calangute-Baga Road, Goa', 'Hotel'),
  (4, 1, 'Casa Azul Boutique Stay', 'Candolim, Goa', 'Hotel'),
  (5, 1, 'Thalassa Seafood Shack', 'Baga Beach Road, Goa', 'Restaurant'),
  (6, 2, 'Amber Fort', 'Devisinghpura, Amer, Jaipur', 'Fort'),
  (7, 2, 'Hawa Mahal', 'Badi Choupad, Jaipur', 'Monument'),
  (8, 2, 'Pink City Haveli', 'Chandpole Bazaar, Jaipur', 'Hotel'),
  (9, 2, 'Rajwada Thali House', 'MI Road, Jaipur', 'Restaurant'),
  (10, 3, 'Eravikulam National Park', 'Rajamala, Munnar', 'Park'),
  (11, 3, 'Tea Museum', 'Nallathanni Estate, Munnar', 'Museum'),
  (12, 3, 'Misty Hills Resort', 'Chithirapuram, Munnar', 'Hotel'),
  (13, 4, 'Solang Valley', 'Solang, Manali', 'Adventure'),
  (14, 4, 'Hadimba Devi Temple', 'Old Manali Road, Manali', 'Temple'),
  (15, 4, 'Pine Cone Lodge', 'Aleo, Manali', 'Hotel'),
  (16, 5, 'Virupaksha Temple', 'Hampi Bazaar, Hampi', 'Temple'),
  (17, 5, 'Vijaya Vitthala Temple', 'Hampi, Karnataka', 'Temple'),
  (18, 5, 'Tungabhadra Heritage Stay', 'Virupapura Gaddi, Hampi', 'Hotel'),
  (19, 6, 'Abbey Falls', 'Madikeri, Coorg', 'Waterfall'),
  (20, 6, 'Raja''s Seat', 'Madikeri, Coorg', 'Viewpoint'),
  (21, 6, 'Coffee Mist Homestay', 'Galibeedu, Coorg', 'Hotel'),
  (22, 7, 'City Palace', 'Lake Pichola Road, Udaipur', 'Palace'),
  (23, 7, 'Lake Pichola Boat Ride', 'Lake Pichola, Udaipur', 'Activity'),
  (24, 7, 'Lake View Palace Inn', 'Gangaur Ghat Road, Udaipur', 'Hotel');

INSERT INTO activity_categories (category_id, name) VALUES
  (1, 'Sightseeing'),
  (2, 'Food & Dining'),
  (3, 'Adventure'),
  (4, 'Transport'),
  (5, 'Accommodation'),
  (6, 'Shopping'),
  (7, 'Leisure');

INSERT INTO expense_categories (expense_category_id, name) VALUES
  (1, 'Transport'),
  (2, 'Food'),
  (3, 'Stay'),
  (4, 'Activities'),
  (5, 'Shopping'),
  (6, 'Miscellaneous');

INSERT INTO amenities (amenity_id, name) VALUES
  (1, 'Wi-Fi'),
  (2, 'Swimming Pool'),
  (3, 'Breakfast'),
  (4, 'Parking'),
  (5, 'Spa'),
  (6, 'Gym'),
  (7, 'Airport Shuttle'),
  (8, 'Air Conditioning');

INSERT INTO trips (trip_id, owner_id, title, start_date, end_date, budget_total, status, is_public) VALUES
  (1, 2, 'Goa Beach Escape', '2026-12-26', '2026-12-30', 60000, 'planned', TRUE),
  (2, 3, 'Rajasthan Heritage Tour', '2026-11-10', '2026-11-14', 85000, 'planned', TRUE),
  (3, 4, 'Munnar Monsoon Getaway', '2026-08-14', '2026-08-17', 40000, 'completed', FALSE),
  (4, 5, 'Hampi and Coorg Road Trip', '2026-10-19', '2026-10-23', 35000, 'ongoing', FALSE),
  (5, 6, 'Manali Winter Break', '2027-01-08', '2027-01-12', 50000, 'planned', TRUE);

INSERT INTO trip_members (trip_id, user_id, role) VALUES
  (1, 2, 'owner'),
  (1, 3, 'editor'),
  (1, 4, 'viewer'),
  (2, 3, 'owner'),
  (2, 2, 'editor'),
  (2, 5, 'viewer'),
  (3, 4, 'owner'),
  (3, 6, 'editor'),
  (3, 5, 'viewer'),
  (4, 5, 'owner'),
  (4, 3, 'editor'),
  (4, 6, 'viewer'),
  (5, 6, 'owner'),
  (5, 4, 'editor'),
  (5, 2, 'viewer');
-- Trigger checks day_date = start_date + day_number - 1
INSERT INTO itinerary_days (day_id, trip_id, day_number, day_date, notes) VALUES
  (1, 1, 1, '2026-12-26', 'Arrival day'),
  (2, 1, 2, '2026-12-27', NULL),
  (3, 1, 3, '2026-12-28', NULL),
  (4, 1, 4, '2026-12-29', NULL),
  (5, 1, 5, '2026-12-30', 'Departure day'),
  (6, 2, 1, '2026-11-10', NULL),
  (7, 2, 2, '2026-11-11', NULL),
  (8, 2, 3, '2026-11-12', 'Shopping then drive to Udaipur'),
  (9, 2, 4, '2026-11-13', NULL),
  (10, 2, 5, '2026-11-14', NULL),
  (11, 3, 1, '2026-08-14', NULL),
  (12, 3, 2, '2026-08-15', NULL),
  (13, 3, 3, '2026-08-16', 'Free day for sightseeing'),
  (14, 3, 4, '2026-08-17', NULL),
  (15, 4, 1, '2026-10-19', NULL),
  (16, 4, 2, '2026-10-20', NULL),
  (17, 4, 3, '2026-10-21', NULL),
  (18, 4, 4, '2026-10-22', 'Today: Coorg sightseeing'),
  (19, 4, 5, '2026-10-23', NULL),
  (20, 5, 1, '2027-01-08', NULL),
  (21, 5, 2, '2027-01-09', NULL),
  (22, 5, 3, '2027-01-10', 'Skiing day'),
  (23, 5, 4, '2027-01-11', NULL),
  (24, 5, 5, '2027-01-12', NULL);
-- Trigger checks that timed items in one day never overlap
INSERT INTO itinerary_items (item_id, day_id, seq_no, category_id, place_id, title, start_time, end_time, estimated_cost, status, notes) VALUES
  (1, 1, 1, 4, NULL, 'Flight Bengaluru to Goa and cab to hotel', '08:00', '12:00', 8500, 'planned', NULL),
  (2, 1, 2, 5, 3, 'Check-in at Seaside Palms Resort', '14:00', '15:00', 0, 'planned', 'Deluxe Sea View room'),
  (3, 1, 3, 2, 5, 'Dinner at Thalassa Seafood Shack', '20:00', '21:30', 2500, 'planned', NULL),
  (4, 2, 1, 1, 1, 'Morning at Baga Beach', '09:00', '12:00', 500, 'planned', NULL),
  (5, 2, 2, 2, 5, 'Seafood lunch', '13:00', '14:00', 1800, 'planned', NULL),
  (6, 2, 3, 3, 1, 'Parasailing and water sports', '15:00', '17:30', 3500, 'planned', 'Carry a change of clothes'),
  (7, 3, 1, 1, 2, 'Visit Fort Aguada', '10:00', '12:00', 300, 'planned', NULL),
  (8, 3, 2, 6, NULL, 'Anjuna flea market', '16:00', '19:00', 3000, 'planned', NULL),
  (9, 4, 1, 7, NULL, 'Spa and pool day', '10:00', '13:00', 4000, 'planned', NULL),
  (10, 4, 2, 2, NULL, 'Beach shack dinner', '19:30', '21:30', 3000, 'planned', NULL),
  (11, 5, 1, 5, 3, 'Check-out from Seaside Palms Resort', '11:00', '11:30', 0, 'planned', NULL),
  (12, 5, 2, 4, NULL, 'Cab to airport and flight home', '13:00', '17:00', 8500, 'planned', NULL),
  (13, 6, 1, 4, NULL, 'Train to Jaipur', '06:00', '14:00', 3000, 'planned', NULL),
  (14, 6, 2, 5, 8, 'Check-in at Pink City Haveli', '15:00', '15:30', 0, 'planned', NULL),
  (15, 6, 3, 2, 9, 'Dinner at Rajwada Thali House', '20:00', '21:30', 1600, 'planned', NULL),
  (16, 7, 1, 1, 6, 'Amber Fort and elephant-free fort walk', '09:00', '12:30', 1500, 'planned', NULL),
  (17, 7, 2, 2, 9, 'Lunch at Rajwada Thali House', '13:00', '14:00', 1000, 'planned', NULL),
  (18, 7, 3, 1, 7, 'Hawa Mahal and City walk', '16:00', '17:30', 200, 'planned', NULL),
  (19, 8, 1, 6, NULL, 'Johari Bazaar jewellery and textiles', '11:00', '14:00', 8000, 'planned', NULL),
  (20, 8, 2, 4, NULL, 'Drive from Jaipur to Udaipur', '15:00', '21:00', 5000, 'planned', NULL),
  (21, 9, 1, 1, 22, 'City Palace tour', '10:00', '13:00', 700, 'planned', NULL),
  (22, 9, 2, 7, 23, 'Sunset boat ride on Lake Pichola', '17:00', '18:30', 1200, 'planned', NULL),
  (23, 10, 1, 4, NULL, 'Flight Udaipur to Bengaluru', '14:00', '17:00', 7000, 'planned', NULL),
  (24, 11, 1, 4, NULL, 'Cab from Kochi to Munnar', '09:00', '13:00', 3500, 'done', NULL),
  (25, 11, 2, 5, 12, 'Check-in at Misty Hills Resort', '14:00', '14:30', 0, 'done', NULL),
  (26, 12, 1, 1, 10, 'Eravikulam National Park', '08:00', '12:00', 600, 'done', NULL),
  (27, 12, 2, 1, 11, 'Tea Museum visit', '14:00', '16:00', 300, 'done', NULL),
  (28, 13, 1, 3, NULL, 'Jeep safari to viewpoints', '09:00', '13:00', 2500, 'done', NULL),
  (29, 13, 2, 6, NULL, 'Spices and tea shopping', '16:00', '18:00', 1500, 'skipped', 'Skipped due to rain'),
  (30, 14, 1, 4, NULL, 'Cab from Munnar to Kochi airport', '10:00', '15:00', 3500, 'done', NULL),
  (31, 15, 1, 4, NULL, 'Drive Bengaluru to Hampi', '06:00', '14:00', 3000, 'done', NULL),
  (32, 15, 2, 5, 18, 'Check-in at Tungabhadra Heritage Stay', '15:00', '15:30', 0, 'done', NULL),
  (33, 16, 1, 1, 16, 'Virupaksha Temple at sunrise', '07:00', '09:30', 100, 'done', NULL),
  (34, 16, 2, 1, 17, 'Vijaya Vitthala Temple and stone chariot', '10:00', '13:00', 600, 'done', NULL),
  (35, 17, 1, 4, NULL, 'Drive Hampi to Coorg', '08:00', '17:00', 4000, 'done', NULL),
  (36, 17, 2, 5, 21, 'Check-in at Coffee Mist Homestay', '18:00', '18:30', 0, 'done', NULL),
  (37, 18, 1, 1, 19, 'Abbey Falls', '09:00', '11:00', 100, 'done', NULL),
  (38, 18, 2, 1, 20, 'Raja''s Seat at sunset', '16:30', '18:00', 50, 'planned', NULL),
  (39, 19, 1, 7, NULL, 'Coffee estate tour', '09:00', '12:00', 1200, 'planned', NULL),
  (40, 19, 2, 4, NULL, 'Drive back to Bengaluru', '13:00', '19:00', 3000, 'planned', NULL),
  (41, 20, 1, 4, NULL, 'Volvo bus Delhi to Manali', '07:00', '19:00', 2500, 'planned', NULL),
  (42, 20, 2, 5, 15, 'Check-in at Pine Cone Lodge', '20:00', '20:30', 0, 'planned', NULL),
  (43, 21, 1, 1, 14, 'Hadimba Devi Temple', '09:00', '11:00', 50, 'planned', NULL),
  (44, 21, 2, 6, NULL, 'Mall Road shopping', '15:00', '18:00', 2000, 'planned', NULL),
  (45, 22, 1, 3, 13, 'Skiing at Solang Valley', '09:00', '14:00', 4500, 'planned', NULL),
  (46, 23, 1, 7, NULL, 'Riverside cafes in Old Manali', '11:00', '15:00', 1500, 'planned', NULL),
  (47, 24, 1, 4, NULL, 'Return journey to Delhi', '08:00', '20:00', 2500, 'planned', NULL);

INSERT INTO bookings (booking_id, item_id, provider, confirmation_code, status, amount) VALUES
  (1, 1, 'IndiGo', 'IG-GOI4821', 'confirmed', 8500),
  (2, 6, 'Goa Water Sports Co', 'GWS-261227-07', 'confirmed', 3500),
  (3, 12, 'IndiGo', 'IG-BLR9937', 'confirmed', 8500),
  (4, 13, 'IRCTC', 'PNR-4821937650', 'confirmed', 3000),
  (5, 22, 'Lake Pichola Boat Club', NULL, 'pending', 1200),
  (6, 23, 'Air India Express', 'AX-UDR2210', 'pending', 7000),
  (7, 24, 'Kerala Cabs', 'KC-88231', 'confirmed', 3500),
  (8, 28, 'Munnar Jeep Tours', 'MJT-4410', 'confirmed', 2500),
  (9, 39, 'Coorg Estate Tours', 'CET-129', 'confirmed', 1200),
  (10, 41, 'RedBus', 'RB-77120931', 'confirmed', 2500),
  (11, 45, 'Solang Adventures', NULL, 'pending', 4500);
-- Trigger checks that a linked item belongs to the same trip
INSERT INTO expenses (expense_id, trip_id, item_id, expense_category_id, paid_by, amount, expense_date, description) VALUES
  (1, 1, 1, 1, 2, 8500, '2026-10-05', 'Flight tickets to Goa'),
  (2, 1, 2, 3, 2, 8000, '2026-10-10', 'Hotel advance'),
  (3, 1, 2, 3, 3, 10000, '2026-11-15', 'Hotel second instalment'),
  (4, 1, 6, 4, 2, 3500, '2026-10-12', 'Parasailing booking'),
  (5, 2, 13, 1, 3, 3000, '2026-10-08', 'Train tickets'),
  (6, 2, 14, 3, 3, 9600, '2026-10-20', 'Pink City Haveli, 2 nights'),
  (7, 2, NULL, 3, 2, 2000, '2026-10-21', 'Udaipur hotel advance'),
  (8, 3, 24, 1, 4, 3500, '2026-08-14', 'Cab Kochi to Munnar'),
  (9, 3, 25, 3, 4, 13500, '2026-08-14', 'Misty Hills Resort, 3 nights'),
  (10, 3, 26, 4, 6, 600, '2026-08-15', 'Eravikulam entry tickets'),
  (11, 3, 27, 4, 6, 300, '2026-08-15', 'Tea Museum tickets'),
  (12, 3, 28, 4, 5, 2500, '2026-08-16', 'Jeep safari'),
  (13, 3, NULL, 2, 4, 4200, '2026-08-16', 'Group meals'),
  (14, 3, NULL, 2, 6, 1800, '2026-08-15', 'Lunch and snacks'),
  (15, 3, 30, 1, 5, 3500, '2026-08-17', 'Cab to Kochi airport'),
  (16, 3, NULL, 6, 4, 700, '2026-08-17', 'Tips and parking'),
  (17, 4, 31, 1, 5, 3000, '2026-10-19', 'Fuel and tolls to Hampi'),
  (18, 4, 32, 3, 5, 6400, '2026-10-21', 'Hampi stay paid at check-out'),
  (19, 4, 33, 4, 3, 100, '2026-10-20', 'Virupaksha Temple entry'),
  (20, 4, 34, 4, 3, 600, '2026-10-20', 'Vitthala Temple tickets'),
  (21, 4, NULL, 2, 6, 2400, '2026-10-20', 'Lunch and dinner in Hampi'),
  (22, 4, 35, 1, 5, 4000, '2026-10-21', 'Fuel Hampi to Coorg'),
  (23, 4, 36, 3, 5, 4000, '2026-10-21', 'Coorg homestay advance'),
  (24, 4, NULL, 2, 3, 1500, '2026-10-22', 'Breakfast and coffee'),
  (25, 4, 37, 4, 6, 100, '2026-10-22', 'Abbey Falls entry'),
  (26, 5, 41, 1, 6, 2500, '2026-10-18', 'Volvo tickets'),
  (27, 5, 42, 3, 6, 3000, '2026-10-18', 'Pine Cone Lodge advance');

INSERT INTO reviews (user_id, destination_id, rating, comment) VALUES
  (2, 1, 5, 'Beautiful beaches and great seafood.'),
  (3, 1, 4, 'Lively nightlife but crowded in December.'),
  (4, 3, 5, 'Misty tea gardens, perfect monsoon trip.'),
  (6, 3, 4, 'Lovely views, roads get slippery.'),
  (5, 5, 5, 'The ruins are stunning at sunrise.'),
  (3, 5, 4, 'Plan at least two full days.'),
  (2, 2, 4, 'Amber Fort is a must-see.'),
  (5, 6, 5, 'Coffee estates and waterfalls everywhere.');

INSERT INTO saved_destinations (user_id, destination_id) VALUES
  (2, 7),
  (2, 4),
  (4, 1),
  (6, 5),
  (3, 6),
  (5, 7),
  (1, 1);
-- Subtype of places (IS-A): every hotel_id is a place of type Hotel
INSERT INTO hotels (hotel_id, star_rating, phone, email, check_in_time, check_out_time) VALUES
  (3, 4, '+91 832 2410001', 'stay@seasidepalms.example', '14:00:00', '11:00:00'),
  (4, 3, '+91 832 2410202', 'hello@casaazul.example', '14:00:00', '11:00:00'),
  (8, 4, '+91 141 2300112', 'book@pinkcityhaveli.example', '13:00:00', '11:00:00'),
  (12, 4, '+91 4865 230011', 'stay@mistyhills.example', '12:00:00', '10:00:00'),
  (15, 3, '+91 1902 252014', 'info@pineconelodge.example', '13:00:00', '10:00:00'),
  (18, 3, '+91 8394 241010', 'hello@tungabhadrastay.example', '12:00:00', '11:00:00'),
  (21, 4, '+91 8272 228800', 'stay@coffeemist.example', '14:00:00', '11:00:00'),
  (24, 5, '+91 294 2420044', 'reserve@lakeviewpalace.example', '14:00:00', '12:00:00');

INSERT INTO hotel_amenities (hotel_id, amenity_id, is_complimentary) VALUES
  (3, 1, TRUE),
  (3, 2, TRUE),
  (3, 3, FALSE),
  (3, 4, TRUE),
  (3, 5, FALSE),
  (3, 8, TRUE),
  (4, 1, TRUE),
  (4, 3, TRUE),
  (4, 8, TRUE),
  (8, 1, TRUE),
  (8, 3, TRUE),
  (8, 4, TRUE),
  (8, 5, FALSE),
  (8, 8, TRUE),
  (12, 1, TRUE),
  (12, 3, TRUE),
  (12, 4, TRUE),
  (12, 5, FALSE),
  (15, 1, TRUE),
  (15, 4, TRUE),
  (15, 8, FALSE),
  (18, 1, FALSE),
  (18, 3, TRUE),
  (18, 4, TRUE),
  (21, 1, TRUE),
  (21, 3, TRUE),
  (21, 4, TRUE),
  (21, 5, FALSE),
  (24, 1, TRUE),
  (24, 2, FALSE),
  (24, 3, TRUE),
  (24, 5, FALSE),
  (24, 7, FALSE),
  (24, 8, TRUE);

INSERT INTO room_types (room_type_id, hotel_id, name, bed_type, max_occupancy, base_rate) VALUES
  (1, 3, 'Standard Double', 'double', 2, 4500),
  (2, 3, 'Deluxe Sea View', 'king', 3, 7000),
  (3, 4, 'Cozy Twin', 'twin', 2, 3200),
  (4, 4, 'Boutique King', 'king', 2, 4800),
  (5, 8, 'Heritage Queen', 'queen', 3, 4800),
  (6, 8, 'Royal Suite', 'king', 4, 8500),
  (7, 12, 'Valley Double', 'double', 3, 4500),
  (8, 12, 'Cloud Suite', 'king', 4, 7200),
  (9, 15, 'Pine Twin', 'twin', 2, 2800),
  (10, 15, 'Snow View Family', 'queen', 4, 3000),
  (11, 18, 'Heritage Double', 'double', 3, 3200),
  (12, 18, 'Riverside Deluxe', 'king', 3, 4200),
  (13, 21, 'Planter''s Room', 'double', 3, 3800),
  (14, 21, 'Estate Cottage', 'king', 4, 5500),
  (15, 24, 'Lake Facing Queen', 'queen', 2, 6500),
  (16, 24, 'Palace Suite', 'king', 3, 11000);
-- Room 102 of Seaside Palms (room_id 2) is under maintenance
INSERT INTO rooms (room_id, hotel_id, room_type_id, room_number, floor_no, status) VALUES
  (1, 3, 1, '101', 1, 'available'),
  (2, 3, 1, '102', 1, 'maintenance'),
  (3, 3, 2, '201', 2, 'available'),
  (4, 3, 2, '202', 2, 'available'),
  (5, 4, 3, '101', 1, 'available'),
  (6, 4, 3, '102', 1, 'available'),
  (7, 4, 4, '201', 2, 'available'),
  (8, 4, 4, '202', 2, 'available'),
  (9, 8, 5, '101', 1, 'available'),
  (10, 8, 5, '102', 1, 'available'),
  (11, 8, 6, '201', 2, 'available'),
  (12, 8, 6, '202', 2, 'available'),
  (13, 12, 7, '101', 1, 'available'),
  (14, 12, 7, '102', 1, 'available'),
  (15, 12, 8, '201', 2, 'available'),
  (16, 12, 8, '202', 2, 'available'),
  (17, 15, 9, '101', 1, 'available'),
  (18, 15, 9, '102', 1, 'available'),
  (19, 15, 10, '201', 2, 'available'),
  (20, 15, 10, '202', 2, 'available'),
  (21, 18, 11, '101', 1, 'available'),
  (22, 18, 11, '102', 1, 'available'),
  (23, 18, 12, '201', 2, 'available'),
  (24, 18, 12, '202', 2, 'available'),
  (25, 21, 13, '101', 1, 'available'),
  (26, 21, 13, '102', 1, 'available'),
  (27, 21, 14, '201', 2, 'available'),
  (28, 21, 14, '202', 2, 'available'),
  (29, 24, 15, '101', 1, 'available'),
  (30, 24, 15, '102', 1, 'available'),
  (31, 24, 16, '201', 2, 'available'),
  (32, 24, 16, '202', 2, 'available');
-- Trigger validates capacity, maintenance, trip dates, booker role and double booking
INSERT INTO hotel_reservations (reservation_id, trip_id, room_id, booked_by, check_in, check_out, num_guests, rate_per_night, status, confirmation_code, special_requests, created_at) VALUES
  (1, 1, 3, 2, '2026-12-26', '2026-12-30', 2, 6500, 'confirmed', 'HB000001', 'Late check-in after 10 PM', '2026-10-10 11:20:00'),
  (2, 2, 9, 3, '2026-11-10', '2026-11-12', 3, 4800, 'confirmed', 'HB000002', NULL, '2026-10-20 15:20:00'),
  (3, 2, 29, 2, '2026-11-12', '2026-11-14', 2, 6500, 'pending', 'HB000003', 'Lake-facing room please', '2026-10-21 12:10:00'),
  (4, 3, 13, 4, '2026-08-14', '2026-08-17', 3, 4500, 'completed', 'HB000004', NULL, '2026-07-25 09:00:00'),
  (5, 4, 21, 5, '2026-10-19', '2026-10-21', 3, 3200, 'completed', 'HB000005', NULL, '2026-10-01 18:40:00'),
  (6, 4, 25, 5, '2026-10-21', '2026-10-23', 3, 3800, 'checked_in', 'HB000006', 'Early check-in if possible', '2026-10-02 08:15:00'),
  (7, 5, 19, 6, '2027-01-08', '2027-01-12', 3, 3000, 'pending', 'HB000007', 'Room heater required', '2026-10-18 09:50:00'),
  (8, 1, 7, 2, '2026-12-26', '2026-12-30', 2, 4800, 'cancelled', 'HB000008', NULL, '2026-10-05 10:25:00');

INSERT INTO hotel_payments (reservation_id, payment_no, amount, method, status, transaction_ref, paid_at) VALUES
  (1, 1, 8000, 'upi', 'success', 'UPI2610101125', '2026-10-10 11:25:00'),
  (1, 2, 5000, 'card', 'failed', 'CARD-FAIL-7731', '2026-11-15 09:10:00'),
  (1, 3, 10000, 'upi', 'success', 'UPI2611150920', '2026-11-15 09:20:00'),
  (2, 1, 9600, 'card', 'success', 'CARD2610201530', '2026-10-20 15:30:00'),
  (3, 1, 2000, 'upi', 'success', 'UPI2610211215', '2026-10-21 12:15:00'),
  (4, 1, 13500, 'netbanking', 'success', 'NB2608141330', '2026-08-14 13:30:00'),
  (5, 1, 6400, 'cash', 'success', NULL, '2026-10-21 10:45:00'),
  (6, 1, 4000, 'upi', 'success', 'UPI2610211830', '2026-10-21 18:30:00'),
  (7, 1, 3000, 'upi', 'success', 'UPI2610181000', '2026-10-18 10:00:00'),
  (8, 1, 3000, 'upi', 'refunded', 'UPI2610051030', '2026-10-05 10:30:00');
-- Trigger allows reviews only for completed stays
INSERT INTO hotel_reviews (reservation_id, rating, title, comment, created_at) VALUES
  (4, 5, 'Perfect misty escape', 'Spotless rooms and the staff arranged a sunrise tea walk.', '2026-08-18 10:00:00'),
  (5, 4, 'Great heritage stay', 'Close to the temples. Wi-Fi was slow.', '2026-10-22 08:30:00');
-- ============================ QUICK CHECK ============================
SELECT 'tables' AS what, COUNT(*) AS n FROM information_schema.tables WHERE table_schema='travel_itinerary_db' AND table_type='BASE TABLE'
UNION ALL SELECT 'foreign keys', COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema='travel_itinerary_db'
UNION ALL SELECT 'triggers', COUNT(*) FROM information_schema.triggers WHERE trigger_schema='travel_itinerary_db'
UNION ALL SELECT 'views', COUNT(*) FROM information_schema.views WHERE table_schema='travel_itinerary_db';
-- Expected: tables 21, foreign keys 27, triggers 12, views 1


-- =====================================================================
--  TRANSPORT MODULE v2: flights, trains, cabs, buses and metro   (add-on 03)
--  Run AFTER 01_travel_itinerary_v2_full.sql.  Safe to re-run.
--  Adds 9 tables, 13 foreign keys, 12 triggers and 1 view.
--  Totals after this script: 30 tables, 40 foreign keys, 24 triggers, 2 views.
--
--  Design (same IS-A pattern as places -> hotels):
--    transport_bookings   = supertype: one row per leg (trip, carrier, times, fare, status)
--    flight_details / train_details / cab_details / bus_details / metro_details = subtypes
--                           that share transport_id as primary key AND foreign key
--    transport_passengers = weak entity (transport_id, passenger_no)
--    carriers, stations   = lookup tables (airlines ... metro operators; airports ... metro stations)
--  Public transport = train + bus + metro.  The older generic `bookings` table is kept for
--  activity tickets; transport legs are stored here with full detail.
--  NOTE: re-running this script drops the views and audit triggers of script 05 that depend
--  on these tables, so run 05 again afterwards.
-- =====================================================================
USE travel_itinerary_db;

DROP VIEW  IF EXISTS v_trip_timeline;        -- created in script 05, depends on this module
DROP VIEW  IF EXISTS v_trip_cost_summary;
DROP VIEW  IF EXISTS v_trip_transport;
DROP TABLE IF EXISTS transport_passengers;
DROP TABLE IF EXISTS metro_details;
DROP TABLE IF EXISTS bus_details;
DROP TABLE IF EXISTS cab_details;
DROP TABLE IF EXISTS train_details;
DROP TABLE IF EXISTS flight_details;
DROP TABLE IF EXISTS transport_bookings;
DROP TABLE IF EXISTS stations;
DROP TABLE IF EXISTS carriers;

CREATE TABLE carriers (
  carrier_id   INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(80) NOT NULL,
  carrier_type ENUM('airline','railway','cab_operator','bus_operator','metro_operator') NOT NULL,
  code         VARCHAR(10) NULL,
  CONSTRAINT uk_carriers_name UNIQUE (name)
) ENGINE=InnoDB;

CREATE TABLE stations (
  station_id   INT AUTO_INCREMENT PRIMARY KEY,
  code         VARCHAR(10)  NOT NULL,
  name         VARCHAR(100) NOT NULL,
  city         VARCHAR(60)  NOT NULL,
  station_type ENUM('airport','railway_station','bus_stand','metro_station') NOT NULL,
  CONSTRAINT uk_stations_type_code UNIQUE (station_type, code)
) ENGINE=InnoDB;

CREATE TABLE transport_bookings (
  transport_id           INT AUTO_INCREMENT PRIMARY KEY,
  trip_id                INT NOT NULL,
  item_id                INT NULL,
  transport_mode         ENUM('flight','train','cab','bus','metro') NOT NULL,
  carrier_id             INT NOT NULL,
  booked_by              INT NOT NULL,
  origin_station_id      INT NULL,      -- required for every mode except cab
  destination_station_id INT NULL,
  depart_at              DATETIME NOT NULL,
  arrive_at              DATETIME NOT NULL,
  status                 ENUM('pending','confirmed','cancelled','completed') NOT NULL DEFAULT 'pending',
  fare                   DECIMAL(10,2) NOT NULL DEFAULT 0,   -- total fare for all passengers
  confirmation_code      VARCHAR(30) NULL,
  created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_tb_code UNIQUE (confirmation_code),
  CONSTRAINT chk_tb_times CHECK (arrive_at > depart_at),
  CONSTRAINT chk_tb_fare  CHECK (fare >= 0),
  INDEX idx_tb_trip_depart (trip_id, depart_at),
  CONSTRAINT fk_tb_trip    FOREIGN KEY (trip_id)    REFERENCES trips(trip_id)           ON DELETE CASCADE  ON UPDATE CASCADE,
  CONSTRAINT fk_tb_item    FOREIGN KEY (item_id)    REFERENCES itinerary_items(item_id) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_tb_carrier FOREIGN KEY (carrier_id) REFERENCES carriers(carrier_id)     ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_tb_booker  FOREIGN KEY (booked_by)  REFERENCES users(user_id)           ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_tb_origin  FOREIGN KEY (origin_station_id)      REFERENCES stations(station_id) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_tb_dest    FOREIGN KEY (destination_station_id) REFERENCES stations(station_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE flight_details (
  transport_id  INT NOT NULL PRIMARY KEY,
  flight_number VARCHAR(10) NOT NULL,
  cabin_class   ENUM('economy','premium_economy','business','first') NOT NULL DEFAULT 'economy',
  terminal      VARCHAR(10) NULL,
  baggage_kg    INT NOT NULL DEFAULT 15,
  CONSTRAINT chk_flight_baggage CHECK (baggage_kg >= 0),
  CONSTRAINT fk_flight_tb FOREIGN KEY (transport_id) REFERENCES transport_bookings(transport_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE train_details (
  transport_id INT NOT NULL PRIMARY KEY,
  train_number VARCHAR(10) NOT NULL,
  train_name   VARCHAR(60) NULL,
  travel_class ENUM('2S','SL','CC','3A','2A','1A') NOT NULL,
  coach        VARCHAR(10) NULL,
  CONSTRAINT fk_train_tb FOREIGN KEY (transport_id) REFERENCES transport_bookings(transport_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE cab_details (
  transport_id   INT NOT NULL PRIMARY KEY,
  vehicle_type   ENUM('hatchback','sedan','suv','tempo_traveller') NOT NULL,
  driver_name    VARCHAR(60) NULL,
  driver_phone   VARCHAR(20) NULL,
  vehicle_number VARCHAR(20) NULL,
  pickup_address VARCHAR(200) NOT NULL,
  drop_address   VARCHAR(200) NOT NULL,
  distance_km    DECIMAL(7,1) NULL,
  trip_type      ENUM('one_way','round_trip','local') NOT NULL DEFAULT 'one_way',
  CONSTRAINT chk_cab_distance CHECK (distance_km IS NULL OR distance_km > 0),
  CONSTRAINT fk_cab_tb FOREIGN KEY (transport_id) REFERENCES transport_bookings(transport_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE bus_details (
  transport_id INT NOT NULL PRIMARY KEY,
  bus_type     ENUM('city_bus','ordinary','ac_seater','sleeper','volvo_ac') NOT NULL,
  bus_number   VARCHAR(20) NULL,
  CONSTRAINT fk_bus_tb FOREIGN KEY (transport_id) REFERENCES transport_bookings(transport_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE metro_details (
  transport_id INT NOT NULL PRIMARY KEY,
  line_name    VARCHAR(40) NOT NULL,
  ticket_type  ENUM('single','return','day_pass','smart_card') NOT NULL,
  num_stops    INT NULL,
  CONSTRAINT chk_metro_stops CHECK (num_stops IS NULL OR num_stops >= 1),
  CONSTRAINT fk_metro_tb FOREIGN KEY (transport_id) REFERENCES transport_bookings(transport_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- WEAK ENTITY: passenger_no is a partial key, identified through the transport booking
CREATE TABLE transport_passengers (
  transport_id  INT NOT NULL,
  passenger_no  INT NOT NULL,
  full_name     VARCHAR(80) NOT NULL,
  age           TINYINT UNSIGNED NULL,
  seat_no       VARCHAR(10) NULL,
  user_id       INT NULL,               -- set when the passenger is also an app user
  PRIMARY KEY (transport_id, passenger_no),
  CONSTRAINT uk_tp_seat UNIQUE (transport_id, seat_no),   -- several NULL seats are allowed (cabs, city buses)
  CONSTRAINT chk_tp_no  CHECK (passenger_no >= 1),
  CONSTRAINT chk_tp_age CHECK (age IS NULL OR age <= 120),
  CONSTRAINT fk_tp_tb   FOREIGN KEY (transport_id) REFERENCES transport_bookings(transport_id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_tp_user FOREIGN KEY (user_id)      REFERENCES users(user_id)                   ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ======================= TRIGGERS (6 families x insert/update = 12) =======================
DELIMITER $$

CREATE TRIGGER trg_transport_validate_bi BEFORE INSERT ON transport_bookings FOR EACH ROW
BEGIN
  DECLARE v_ctype VARCHAR(20);
  DECLARE v_exp_ctype VARCHAR(20);
  DECLARE v_otype VARCHAR(20);
  DECLARE v_dtype VARCHAR(20);
  DECLARE v_exp_st VARCHAR(20);
  DECLARE v_item_trip INT;
  DECLARE v_cnt INT;
  -- 1. the carrier type must suit the mode (an airline cannot run a cab)
  SELECT carrier_type INTO v_ctype FROM carriers WHERE carrier_id = NEW.carrier_id;
  SET v_exp_ctype = CASE NEW.transport_mode
        WHEN 'flight' THEN 'airline'      WHEN 'train' THEN 'railway'
        WHEN 'cab'    THEN 'cab_operator' WHEN 'bus'   THEN 'bus_operator'
        ELSE 'metro_operator' END;
  IF v_ctype <> v_exp_ctype THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Carrier type does not match the transport mode';
  END IF;
  -- 2. every mode except cab runs between two different stations of the matching kind
  IF NEW.transport_mode <> 'cab' THEN
    IF NEW.origin_station_id IS NULL OR NEW.destination_station_id IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This mode needs an origin and a destination station';
    END IF;
    IF NEW.origin_station_id = NEW.destination_station_id THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Origin and destination must be different';
    END IF;
    SET v_exp_st = CASE NEW.transport_mode
          WHEN 'flight' THEN 'airport'  WHEN 'train' THEN 'railway_station'
          WHEN 'bus'    THEN 'bus_stand' ELSE 'metro_station' END;
    SELECT station_type INTO v_otype FROM stations WHERE station_id = NEW.origin_station_id;
    SELECT station_type INTO v_dtype FROM stations WHERE station_id = NEW.destination_station_id;
    IF v_otype <> v_exp_st OR v_dtype <> v_exp_st THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Station type does not match the transport mode';
    END IF;
  END IF;
  -- 3. a linked itinerary item must belong to the same trip
  IF NEW.item_id IS NOT NULL THEN
    SELECT d.trip_id INTO v_item_trip
      FROM itinerary_items i JOIN itinerary_days d ON d.day_id = i.day_id
     WHERE i.item_id = NEW.item_id;
    IF v_item_trip <> NEW.trip_id THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Itinerary item belongs to a different trip';
    END IF;
  END IF;
  -- 4. only an owner or editor of the trip may book
  SELECT COUNT(*) INTO v_cnt FROM trip_members
   WHERE trip_id = NEW.trip_id AND user_id = NEW.booked_by AND role IN ('owner','editor');
  IF v_cnt = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a trip owner or editor can book transport';
  END IF;
END$$

CREATE TRIGGER trg_transport_validate_bu BEFORE UPDATE ON transport_bookings FOR EACH ROW
BEGIN
  DECLARE v_ctype VARCHAR(20);
  DECLARE v_exp_ctype VARCHAR(20);
  DECLARE v_otype VARCHAR(20);
  DECLARE v_dtype VARCHAR(20);
  DECLARE v_exp_st VARCHAR(20);
  DECLARE v_item_trip INT;
  DECLARE v_cnt INT;
  -- 1. the carrier type must suit the mode (an airline cannot run a cab)
  SELECT carrier_type INTO v_ctype FROM carriers WHERE carrier_id = NEW.carrier_id;
  SET v_exp_ctype = CASE NEW.transport_mode
        WHEN 'flight' THEN 'airline'      WHEN 'train' THEN 'railway'
        WHEN 'cab'    THEN 'cab_operator' WHEN 'bus'   THEN 'bus_operator'
        ELSE 'metro_operator' END;
  IF v_ctype <> v_exp_ctype THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Carrier type does not match the transport mode';
  END IF;
  -- 2. every mode except cab runs between two different stations of the matching kind
  IF NEW.transport_mode <> 'cab' THEN
    IF NEW.origin_station_id IS NULL OR NEW.destination_station_id IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This mode needs an origin and a destination station';
    END IF;
    IF NEW.origin_station_id = NEW.destination_station_id THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Origin and destination must be different';
    END IF;
    SET v_exp_st = CASE NEW.transport_mode
          WHEN 'flight' THEN 'airport'  WHEN 'train' THEN 'railway_station'
          WHEN 'bus'    THEN 'bus_stand' ELSE 'metro_station' END;
    SELECT station_type INTO v_otype FROM stations WHERE station_id = NEW.origin_station_id;
    SELECT station_type INTO v_dtype FROM stations WHERE station_id = NEW.destination_station_id;
    IF v_otype <> v_exp_st OR v_dtype <> v_exp_st THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Station type does not match the transport mode';
    END IF;
  END IF;
  -- 3. a linked itinerary item must belong to the same trip
  IF NEW.item_id IS NOT NULL THEN
    SELECT d.trip_id INTO v_item_trip
      FROM itinerary_items i JOIN itinerary_days d ON d.day_id = i.day_id
     WHERE i.item_id = NEW.item_id;
    IF v_item_trip <> NEW.trip_id THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Itinerary item belongs to a different trip';
    END IF;
  END IF;
  -- 4. only an owner or editor of the trip may book
  SELECT COUNT(*) INTO v_cnt FROM trip_members
   WHERE trip_id = NEW.trip_id AND user_id = NEW.booked_by AND role IN ('owner','editor');
  IF v_cnt = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a trip owner or editor can book transport';
  END IF;
END$$

CREATE TRIGGER trg_flight_mode_bi BEFORE INSERT ON flight_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'flight' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'flight_details requires a booking whose mode is flight';
  END IF;
END$$

CREATE TRIGGER trg_flight_mode_bu BEFORE UPDATE ON flight_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'flight' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'flight_details requires a booking whose mode is flight';
  END IF;
END$$

CREATE TRIGGER trg_train_mode_bi BEFORE INSERT ON train_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'train' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'train_details requires a booking whose mode is train';
  END IF;
END$$

CREATE TRIGGER trg_train_mode_bu BEFORE UPDATE ON train_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'train' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'train_details requires a booking whose mode is train';
  END IF;
END$$

CREATE TRIGGER trg_cab_mode_bi BEFORE INSERT ON cab_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'cab' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'cab_details requires a booking whose mode is cab';
  END IF;
END$$

CREATE TRIGGER trg_cab_mode_bu BEFORE UPDATE ON cab_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'cab' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'cab_details requires a booking whose mode is cab';
  END IF;
END$$

CREATE TRIGGER trg_bus_mode_bi BEFORE INSERT ON bus_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'bus' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'bus_details requires a booking whose mode is bus';
  END IF;
END$$

CREATE TRIGGER trg_bus_mode_bu BEFORE UPDATE ON bus_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'bus' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'bus_details requires a booking whose mode is bus';
  END IF;
END$$

CREATE TRIGGER trg_metro_mode_bi BEFORE INSERT ON metro_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'metro' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'metro_details requires a booking whose mode is metro';
  END IF;
END$$

CREATE TRIGGER trg_metro_mode_bu BEFORE UPDATE ON metro_details FOR EACH ROW
BEGIN
  DECLARE v_mode VARCHAR(10);
  SELECT transport_mode INTO v_mode FROM transport_bookings WHERE transport_id = NEW.transport_id;
  IF v_mode IS NULL OR v_mode <> 'metro' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'metro_details requires a booking whose mode is metro';
  END IF;
END$$

DELIMITER ;

-- ============================== VIEW ================================
CREATE VIEW v_trip_transport AS
SELECT tb.transport_id, tb.trip_id, t.title AS trip_title, tb.transport_mode, c.name AS carrier,
       CASE tb.transport_mode
         WHEN 'flight' THEN CONCAT(fd.flight_number, ' ', so.code, ' to ', sd.code)
         WHEN 'train'  THEN CONCAT(td.train_number, ' ', td.train_name, ' ', so.code, ' to ', sd.code)
         WHEN 'bus'    THEN CONCAT(bd.bus_type, ': ', so.name, ' to ', sd.name)
         WHEN 'metro'  THEN CONCAT(md.line_name, ': ', so.name, ' to ', sd.name)
         ELSE CONCAT(cd.pickup_address, ' to ', cd.drop_address)
       END AS route,
       tb.depart_at, tb.arrive_at,
       TIMESTAMPDIFF(MINUTE, tb.depart_at, tb.arrive_at) AS duration_min,
       (SELECT COUNT(*) FROM transport_passengers tp WHERE tp.transport_id = tb.transport_id) AS passengers,
       tb.fare, tb.status, tb.confirmation_code
  FROM transport_bookings tb
  JOIN trips t    ON t.trip_id = tb.trip_id
  JOIN carriers c ON c.carrier_id = tb.carrier_id
  LEFT JOIN stations so ON so.station_id = tb.origin_station_id
  LEFT JOIN stations sd ON sd.station_id = tb.destination_station_id
  LEFT JOIN flight_details fd ON fd.transport_id = tb.transport_id
  LEFT JOIN train_details  td ON td.transport_id = tb.transport_id
  LEFT JOIN cab_details    cd ON cd.transport_id = tb.transport_id
  LEFT JOIN bus_details    bd ON bd.transport_id = tb.transport_id
  LEFT JOIN metro_details  md ON md.transport_id = tb.transport_id;

-- ============================ SAMPLE DATA ============================
-- Carrier names are real organisations used as illustrative samples; times, numbers and fares are NOT live data
INSERT INTO carriers (carrier_id, name, carrier_type, code) VALUES
  (1, 'IndiGo', 'airline', '6E'),
  (2, 'Air India Express', 'airline', 'IX'),
  (3, 'Indian Railways', 'railway', 'IR'),
  (4, 'Goa Taxi Co', 'cab_operator', NULL),
  (5, 'Rajasthan Cab Services', 'cab_operator', NULL),
  (6, 'Kerala Cabs', 'cab_operator', NULL),
  (7, 'Kadamba Transport Corporation', 'bus_operator', 'KTC'),
  (8, 'Himachal Volvo Lines', 'bus_operator', 'HVL'),
  (9, 'Jaipur Metro Rail Corporation', 'metro_operator', 'JMRC'),
  (10, 'Delhi Metro Rail Corporation', 'metro_operator', 'DMRC');

INSERT INTO stations (station_id, code, name, city, station_type) VALUES
  (1, 'BLR', 'Kempegowda International Airport', 'Bengaluru', 'airport'),
  (2, 'GOI', 'Dabolim Airport', 'Goa', 'airport'),
  (3, 'JAI', 'Jaipur International Airport', 'Jaipur', 'airport'),
  (4, 'UDR', 'Maharana Pratap Airport', 'Udaipur', 'airport'),
  (5, 'COK', 'Cochin International Airport', 'Kochi', 'airport'),
  (6, 'DEL', 'Indira Gandhi International Airport', 'Delhi', 'airport'),
  (7, 'NDLS', 'New Delhi Railway Station', 'Delhi', 'railway_station'),
  (8, 'JP', 'Jaipur Junction', 'Jaipur', 'railway_station'),
  (9, 'CLG', 'Calangute Bus Stand', 'Goa', 'bus_stand'),
  (10, 'ANJ', 'Anjuna Bus Stop', 'Goa', 'bus_stand'),
  (11, 'KGT', 'Kashmere Gate ISBT', 'Delhi', 'bus_stand'),
  (12, 'MNL', 'Manali Bus Stand', 'Manali', 'bus_stand'),
  (13, 'NDM', 'New Delhi Metro Station', 'Delhi', 'metro_station'),
  (14, 'KGM', 'Kashmere Gate Metro Station', 'Delhi', 'metro_station'),
  (15, 'CHP', 'Chandpole Metro Station', 'Jaipur', 'metro_station'),
  (16, 'BCP', 'Badi Chaupar Metro Station', 'Jaipur', 'metro_station');
-- Trigger checks carrier type, station type, item trip and booker role. Trip 4 (own car) has no legs on purpose.
INSERT INTO transport_bookings (transport_id, trip_id, item_id, transport_mode, carrier_id, booked_by, origin_station_id, destination_station_id, depart_at, arrive_at, status, fare, confirmation_code) VALUES
  (1, 1, 1, 'flight', 1, 2, 1, 2, '2026-12-26 08:30:00', '2026-12-26 10:05:00', 'confirmed', 8500, 'IG-GOI4821'),
  (2, 1, 1, 'cab', 4, 2, NULL, NULL, '2026-12-26 11:00:00', '2026-12-26 12:00:00', 'confirmed', 1200, 'GT-26122601'),
  (3, 1, 8, 'bus', 7, 2, 9, 10, '2026-12-28 15:40:00', '2026-12-28 16:05:00', 'confirmed', 40, 'KTC-281226-11'),
  (4, 1, 12, 'cab', 4, 2, NULL, NULL, '2026-12-30 13:00:00', '2026-12-30 13:50:00', 'confirmed', 1000, 'GT-30122602'),
  (5, 1, 12, 'flight', 1, 2, 2, 1, '2026-12-30 14:45:00', '2026-12-30 16:10:00', 'confirmed', 8500, 'IG-BLR9937'),
  (6, 2, 13, 'train', 3, 3, 7, 8, '2026-11-10 06:05:00', '2026-11-10 10:50:00', 'confirmed', 3000, 'PNR-4821937650'),
  (7, 2, 18, 'metro', 9, 3, 15, 16, '2026-11-11 16:10:00', '2026-11-11 16:25:00', 'confirmed', 30, 'JMRC-QR-5521'),
  (8, 2, 20, 'cab', 5, 3, NULL, NULL, '2026-11-12 15:00:00', '2026-11-12 21:00:00', 'confirmed', 5000, 'RCS-77412'),
  (9, 2, 23, 'flight', 2, 2, 4, 1, '2026-11-14 14:30:00', '2026-11-14 16:15:00', 'pending', 7000, 'AX-UDR2210'),
  (10, 3, 24, 'cab', 6, 4, NULL, NULL, '2026-08-14 09:00:00', '2026-08-14 13:00:00', 'completed', 3500, 'KC-88231'),
  (11, 3, 30, 'cab', 6, 4, NULL, NULL, '2026-08-17 10:00:00', '2026-08-17 15:00:00', 'completed', 3500, 'KC-88290'),
  (12, 5, 41, 'metro', 10, 6, 13, 14, '2027-01-08 06:30:00', '2027-01-08 06:55:00', 'confirmed', 60, 'DMRC-SJT-7710'),
  (13, 5, 41, 'bus', 8, 6, 11, 12, '2027-01-08 07:30:00', '2027-01-08 19:00:00', 'confirmed', 2500, 'HVL-77120931'),
  (14, 5, 47, 'bus', 8, 6, 12, 11, '2027-01-12 08:00:00', '2027-01-12 20:00:00', 'pending', 2500, 'HVL-77120944');

INSERT INTO flight_details (transport_id, flight_number, cabin_class, terminal, baggage_kg) VALUES
  (1, '6E 6451', 'economy', 'T1', 15),
  (5, '6E 6452', 'economy', 'T1', 15),
  (9, 'IX 1274', 'economy', 'T2', 15);

INSERT INTO train_details (transport_id, train_number, train_name, travel_class, coach) VALUES
  (6, '12015', 'Ajmer Shatabdi', 'CC', 'C3');

INSERT INTO cab_details (transport_id, vehicle_type, driver_name, driver_phone, vehicle_number, pickup_address, drop_address, distance_km, trip_type) VALUES
  (2, 'sedan', 'Rakesh Naik', '+91 90000 10001', 'GA 03 T 4412', 'Goa Airport (Dabolim)', 'Seaside Palms Resort, Calangute-Baga Road', 45, 'one_way'),
  (4, 'sedan', 'Rakesh Naik', '+91 90000 10001', 'GA 03 T 4412', 'Seaside Palms Resort, Calangute-Baga Road', 'Goa Airport (Dabolim)', 45, 'one_way'),
  (8, 'suv', 'Mahesh Singh', '+91 90000 10002', 'RJ 14 TA 4521', 'Pink City Haveli, Chandpole Bazaar, Jaipur', 'Lake View Palace Inn, Udaipur', 395, 'one_way'),
  (10, 'sedan', 'Binu Thomas', '+91 90000 10003', 'KL 07 BC 2210', 'Cochin International Airport', 'Misty Hills Resort, Chithirapuram, Munnar', 110, 'one_way'),
  (11, 'sedan', 'Binu Thomas', '+91 90000 10003', 'KL 07 BC 2210', 'Misty Hills Resort, Chithirapuram, Munnar', 'Cochin International Airport', 110, 'one_way');

INSERT INTO bus_details (transport_id, bus_type, bus_number) VALUES
  (3, 'city_bus', 'GA-03-KTC-118'),
  (13, 'volvo_ac', 'HP-01-HV-7712'),
  (14, 'volvo_ac', 'HP-01-HV-7713');

INSERT INTO metro_details (transport_id, line_name, ticket_type, num_stops) VALUES
  (7, 'Pink Line', 'single', 2),
  (12, 'Yellow Line', 'single', 3);

INSERT INTO transport_passengers (transport_id, passenger_no, full_name, age, seat_no, user_id) VALUES
  (1, 1, 'Priya Nair', 29, '14A', 2),
  (1, 2, 'Rohan Mehta', 30, '14B', 3),
  (2, 1, 'Priya Nair', 29, NULL, 2),
  (2, 2, 'Rohan Mehta', 30, NULL, 3),
  (3, 1, 'Priya Nair', 29, NULL, 2),
  (3, 2, 'Rohan Mehta', 30, NULL, 3),
  (4, 1, 'Priya Nair', 29, NULL, 2),
  (4, 2, 'Rohan Mehta', 30, NULL, 3),
  (5, 1, 'Priya Nair', 29, '9C', 2),
  (5, 2, 'Rohan Mehta', 30, '9D', 3),
  (6, 1, 'Rohan Mehta', 30, 'C3-21', 3),
  (6, 2, 'Priya Nair', 29, 'C3-22', 2),
  (6, 3, 'Karthik Reddy', 31, 'C3-23', 5),
  (7, 1, 'Rohan Mehta', 30, NULL, 3),
  (7, 2, 'Priya Nair', 29, NULL, 2),
  (7, 3, 'Karthik Reddy', 31, NULL, 5),
  (8, 1, 'Rohan Mehta', 30, NULL, 3),
  (8, 2, 'Priya Nair', 29, NULL, 2),
  (8, 3, 'Karthik Reddy', 31, NULL, 5),
  (9, 1, 'Rohan Mehta', 30, '21C', 3),
  (9, 2, 'Priya Nair', 29, '21D', 2),
  (10, 1, 'Sneha Iyer', 28, NULL, 4),
  (10, 2, 'Ananya Das', 27, NULL, 6),
  (10, 3, 'Karthik Reddy', 31, NULL, 5),
  (11, 1, 'Sneha Iyer', 28, NULL, 4),
  (11, 2, 'Ananya Das', 27, NULL, 6),
  (11, 3, 'Karthik Reddy', 31, NULL, 5),
  (12, 1, 'Ananya Das', 27, NULL, 6),
  (12, 2, 'Sneha Iyer', 28, NULL, 4),
  (13, 1, 'Ananya Das', 27, 'L5', 6),
  (13, 2, 'Sneha Iyer', 28, 'L6', 4),
  (14, 1, 'Ananya Das', 27, 'U3', 6),
  (14, 2, 'Sneha Iyer', 28, 'U4', 4);
-- ============================ QUICK CHECK ============================
SELECT 'tables' AS what, COUNT(*) AS n FROM information_schema.tables WHERE table_schema='travel_itinerary_db' AND table_type='BASE TABLE'
UNION ALL SELECT 'foreign keys', COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema='travel_itinerary_db'
UNION ALL SELECT 'triggers', COUNT(*) FROM information_schema.triggers WHERE trigger_schema='travel_itinerary_db'
UNION ALL SELECT 'views', COUNT(*) FROM information_schema.views WHERE table_schema='travel_itinerary_db';
-- Expected: tables 30, foreign keys 40, triggers 24, views 2


-- =====================================================================
--  SMART LAYER (add-on 05): audit trail, budget alerts, dashboards
--  Run AFTER 01 and 03.  Safe to re-run.
--  Adds 2 tables, 1 foreign key, 7 AFTER triggers and 2 views.
--  Totals after this script: 32 tables, 41 foreign keys, 31 triggers, 4 views.
--
--  Why AFTER triggers?  The 12 + 12 triggers in 01 and 03 are BEFORE triggers: they
--  REJECT bad rows.  These 7 are AFTER triggers: the row is already saved, and they
--  REACT by writing a second record (an audit entry or an alert).
-- =====================================================================
USE travel_itinerary_db;

DROP VIEW  IF EXISTS v_trip_timeline;
DROP VIEW  IF EXISTS v_trip_cost_summary;
DROP TABLE IF EXISTS trip_alerts;
DROP TABLE IF EXISTS audit_log;

-- Generic change history: who changed what, from which value to which value
CREATE TABLE audit_log (
  audit_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
  table_name VARCHAR(40)  NOT NULL,
  record_id  VARCHAR(40)  NOT NULL,
  action     ENUM('UPDATE','DELETE') NOT NULL,
  field_name VARCHAR(40)  NULL,
  old_value  VARCHAR(255) NULL,
  new_value  VARCHAR(255) NULL,
  changed_by VARCHAR(80)  NOT NULL,
  changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_audit_table_record (table_name, record_id)
) ENGINE=InnoDB;

-- Budget alerts raised by the expense triggers; at most one alert of each type per trip
CREATE TABLE trip_alerts (
  alert_id   INT AUTO_INCREMENT PRIMARY KEY,
  trip_id    INT NOT NULL,
  alert_type ENUM('budget_80','budget_exceeded') NOT NULL,
  message    VARCHAR(200) NOT NULL,
  is_read    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uk_alert_trip_type UNIQUE (trip_id, alert_type),
  CONSTRAINT fk_alert_trip FOREIGN KEY (trip_id) REFERENCES trips(trip_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

DELIMITER $$

-- ---- audit triggers: keep a history of important changes ----
CREATE TRIGGER trg_trips_audit_au AFTER UPDATE ON trips FOR EACH ROW
BEGIN
  IF NOT (OLD.budget_total <=> NEW.budget_total) THEN
    INSERT INTO audit_log (table_name, record_id, action, field_name, old_value, new_value, changed_by)
    VALUES ('trips', NEW.trip_id, 'UPDATE', 'budget_total', CAST(OLD.budget_total AS CHAR), CAST(NEW.budget_total AS CHAR), USER());
  END IF;
  IF NOT (OLD.status <=> NEW.status) THEN
    INSERT INTO audit_log (table_name, record_id, action, field_name, old_value, new_value, changed_by)
    VALUES ('trips', NEW.trip_id, 'UPDATE', 'status', CAST(OLD.status AS CHAR), CAST(NEW.status AS CHAR), USER());
  END IF;
END$$

CREATE TRIGGER trg_res_audit_au AFTER UPDATE ON hotel_reservations FOR EACH ROW
BEGIN
  IF NOT (OLD.status <=> NEW.status) THEN
    INSERT INTO audit_log (table_name, record_id, action, field_name, old_value, new_value, changed_by)
    VALUES ('hotel_reservations', NEW.reservation_id, 'UPDATE', 'status', CAST(OLD.status AS CHAR), CAST(NEW.status AS CHAR), USER());
  END IF;
END$$

CREATE TRIGGER trg_transport_audit_au AFTER UPDATE ON transport_bookings FOR EACH ROW
BEGIN
  IF NOT (OLD.status <=> NEW.status) THEN
    INSERT INTO audit_log (table_name, record_id, action, field_name, old_value, new_value, changed_by)
    VALUES ('transport_bookings', NEW.transport_id, 'UPDATE', 'status', CAST(OLD.status AS CHAR), CAST(NEW.status AS CHAR), USER());
  END IF;
END$$

CREATE TRIGGER trg_exp_audit_au AFTER UPDATE ON expenses FOR EACH ROW
BEGIN
  IF NOT (OLD.amount <=> NEW.amount) THEN
    INSERT INTO audit_log (table_name, record_id, action, field_name, old_value, new_value, changed_by)
    VALUES ('expenses', NEW.expense_id, 'UPDATE', 'amount', CAST(OLD.amount AS CHAR), CAST(NEW.amount AS CHAR), USER());
  END IF;
END$$

CREATE TRIGGER trg_exp_audit_ad AFTER DELETE ON expenses FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, record_id, action, field_name, old_value, new_value, changed_by)
  VALUES ('expenses', OLD.expense_id, 'DELETE', 'amount', CAST(OLD.amount AS CHAR), NULL, USER());
END$$

-- ---- alert triggers: warn the group when spending nears or passes the budget ----
CREATE TRIGGER trg_exp_budget_alert_ai AFTER INSERT ON expenses FOR EACH ROW
BEGIN
  DECLARE v_budget DECIMAL(10,2);
  DECLARE v_spent  DECIMAL(12,2);
  SELECT budget_total INTO v_budget FROM trips WHERE trip_id = NEW.trip_id;
  SELECT COALESCE(SUM(amount), 0) INTO v_spent FROM expenses WHERE trip_id = NEW.trip_id;
  IF v_budget > 0 THEN
    IF v_spent > v_budget THEN
      INSERT IGNORE INTO trip_alerts (trip_id, alert_type, message)
      VALUES (NEW.trip_id, 'budget_exceeded',
              CONCAT('Spending ', v_spent, ' has exceeded the budget of ', v_budget));
    ELSEIF v_spent >= 0.8 * v_budget THEN
      INSERT IGNORE INTO trip_alerts (trip_id, alert_type, message)
      VALUES (NEW.trip_id, 'budget_80',
              CONCAT('Spending ', v_spent, ' has reached 80 percent of the budget of ', v_budget));
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_exp_budget_alert_au AFTER UPDATE ON expenses FOR EACH ROW
BEGIN
  DECLARE v_budget DECIMAL(10,2);
  DECLARE v_spent  DECIMAL(12,2);
  SELECT budget_total INTO v_budget FROM trips WHERE trip_id = NEW.trip_id;
  SELECT COALESCE(SUM(amount), 0) INTO v_spent FROM expenses WHERE trip_id = NEW.trip_id;
  IF v_budget > 0 THEN
    IF v_spent > v_budget THEN
      INSERT IGNORE INTO trip_alerts (trip_id, alert_type, message)
      VALUES (NEW.trip_id, 'budget_exceeded',
              CONCAT('Spending ', v_spent, ' has exceeded the budget of ', v_budget));
    ELSEIF v_spent >= 0.8 * v_budget THEN
      INSERT IGNORE INTO trip_alerts (trip_id, alert_type, message)
      VALUES (NEW.trip_id, 'budget_80',
              CONCAT('Spending ', v_spent, ' has reached 80 percent of the budget of ', v_budget));
    END IF;
  END IF;
END$$

DELIMITER ;

-- ============================== VIEWS ================================
-- One chronological list of everything that happens on a trip
CREATE VIEW v_trip_timeline AS
SELECT trip_id, depart_at AS happens_at, 'TRANSPORT' AS event_type,
       CONCAT(UPPER(transport_mode), ': ', carrier, ' - ', route) AS description,
       CAST(status AS CHAR) AS status
  FROM v_trip_transport WHERE status <> 'cancelled'
UNION ALL
SELECT hr.trip_id, TIMESTAMP(hr.check_in, h.check_in_time), 'HOTEL_CHECK_IN',
       CONCAT(p.name, ' - ', rt.name, ' ', r.room_number), CAST(hr.status AS CHAR)
  FROM hotel_reservations hr
  JOIN rooms r       ON r.room_id = hr.room_id
  JOIN room_types rt ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id
  JOIN hotels h      ON h.hotel_id = r.hotel_id
  JOIN places p      ON p.place_id = h.hotel_id
 WHERE hr.status <> 'cancelled'
UNION ALL
SELECT hr.trip_id, TIMESTAMP(hr.check_out, h.check_out_time), 'HOTEL_CHECK_OUT',
       CONCAT(p.name, ' - ', rt.name, ' ', r.room_number), CAST(hr.status AS CHAR)
  FROM hotel_reservations hr
  JOIN rooms r       ON r.room_id = hr.room_id
  JOIN room_types rt ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id
  JOIN hotels h      ON h.hotel_id = r.hotel_id
  JOIN places p      ON p.place_id = h.hotel_id
 WHERE hr.status <> 'cancelled'
UNION ALL
SELECT d.trip_id, TIMESTAMP(d.day_date, i.start_time), 'ACTIVITY', i.title, CAST(i.status AS CHAR)
  FROM itinerary_items i
  JOIN itinerary_days d       ON d.day_id = i.day_id
  JOIN activity_categories ac ON ac.category_id = i.category_id
 WHERE i.start_time IS NOT NULL AND ac.name NOT IN ('Accommodation','Transport');

-- Budget dashboard: what is booked (hotels + transport) versus what is actually spent
CREATE VIEW v_trip_cost_summary AS
SELECT t.trip_id, t.title, t.status, t.budget_total,
       COALESCE(h.hotel_booked, 0)     AS hotel_booked,
       COALESCE(tr.transport_booked,0) AS transport_booked,
       COALESCE(h.hotel_booked, 0) + COALESCE(tr.transport_booked, 0) AS total_booked,
       ROUND(100 * (COALESCE(h.hotel_booked, 0) + COALESCE(tr.transport_booked, 0)) / NULLIF(t.budget_total, 0), 1) AS booked_pct_of_budget,
       COALESCE(e.actual_spend, 0)     AS actual_spend,
       t.budget_total - COALESCE(e.actual_spend, 0) AS remaining_budget
  FROM trips t
  LEFT JOIN (SELECT trip_id, SUM(DATEDIFF(check_out, check_in) * rate_per_night) AS hotel_booked
               FROM hotel_reservations WHERE status <> 'cancelled' GROUP BY trip_id) h ON h.trip_id = t.trip_id
  LEFT JOIN (SELECT trip_id, SUM(fare) AS transport_booked
               FROM transport_bookings WHERE status <> 'cancelled' GROUP BY trip_id) tr ON tr.trip_id = t.trip_id
  LEFT JOIN (SELECT trip_id, SUM(amount) AS actual_spend
               FROM expenses GROUP BY trip_id) e ON e.trip_id = t.trip_id;

-- ============================ QUICK CHECK ============================
SELECT 'tables' AS what, COUNT(*) AS n FROM information_schema.tables WHERE table_schema='travel_itinerary_db' AND table_type='BASE TABLE'
UNION ALL SELECT 'foreign keys', COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema='travel_itinerary_db'
UNION ALL SELECT 'triggers', COUNT(*) FROM information_schema.triggers WHERE trigger_schema='travel_itinerary_db'
UNION ALL SELECT 'views', COUNT(*) FROM information_schema.views WHERE table_schema='travel_itinerary_db';
-- Expected: tables 32, foreign keys 41, triggers 31, views 4
