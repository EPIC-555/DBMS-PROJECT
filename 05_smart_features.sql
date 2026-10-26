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

-- Drop the triggers first: they survive a table drop only if the table is dropped,
-- and re-running this script must not fail with "Trigger already exists" (error 1359).
DROP TRIGGER IF EXISTS trg_trips_audit_au;
DROP TRIGGER IF EXISTS trg_res_audit_au;
DROP TRIGGER IF EXISTS trg_transport_audit_au;
DROP TRIGGER IF EXISTS trg_exp_audit_au;
DROP TRIGGER IF EXISTS trg_exp_audit_ad;
DROP TRIGGER IF EXISTS trg_exp_budget_alert_ai;
DROP TRIGGER IF EXISTS trg_exp_budget_alert_au;
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
