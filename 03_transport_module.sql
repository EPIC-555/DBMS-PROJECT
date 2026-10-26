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
