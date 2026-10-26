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
  (41, 20, 1, 4, NULL, 'Overnight Volvo Delhi to Manali', '07:00', '19:00', 2500, 'planned', NULL),
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
