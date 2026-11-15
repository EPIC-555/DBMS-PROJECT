"""API tests. They run against a live MySQL with travel_itinerary_db loaded.

Set DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME (or a .env file) first.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

ADMIN = {"email": "aarav.sharma@example.com", "password": "Aarav@123"}
VIEWER = {"email": "priya.nair@example.com", "password": "Priya@123"}


@pytest.fixture(scope="session")
def admin_client():
    """A client signed in as the admin user, with the CSRF header preset."""
    c = TestClient(app)
    r = c.post("/api/auth/login", json=ADMIN)
    assert r.status_code == 200, r.text
    assert r.json()["user"]["role"] == "admin"
    # The real dashboard echoes the CSRF cookie in this header on every write.
    c.headers.update({"X-CSRF-Token": r.json()["csrf_token"]})
    return c


@pytest.fixture(scope="session")
def viewer_client():
    """A client signed in as a non-admin user, with the CSRF header preset."""
    c = TestClient(app)
    r = c.post("/api/auth/login", json=VIEWER)
    assert r.status_code == 200, r.text
    assert r.json()["user"]["role"] == "user"
    c.headers.update({"X-CSRF-Token": r.json()["csrf_token"]})
    return c


def test_health_reports_acceptance_counts(admin_client):
    r = admin_client.get("/api/health")
    assert r.status_code == 200
    body = r.json()
    assert body["connected"] is True
    counts = body["counts"]
    assert counts["tables"] == 32
    assert counts["foreign_keys"] == 41
    assert counts["triggers"] == 31
    assert counts["views"] == 4
    assert counts["procedures"] == 2


def test_overview_lists_objects(admin_client):
    body = admin_client.get("/api/overview").json()
    assert len(body["tables"]) == 32
    assert set(body["views"]) == {
        "v_reservation_summary", "v_trip_transport", "v_trip_timeline", "v_trip_cost_summary",
    }
    assert set(body["procedures"]) == {"sp_create_trip", "sp_book_room"}


def test_triggers_and_foreign_keys(admin_client):
    assert len(admin_client.get("/api/triggers").json()) == 31
    assert len(admin_client.get("/api/fks").json()) == 41


def test_trigger_source_is_readable(admin_client):
    body = admin_client.get("/api/triggers/trg_res_validate_bi").json()
    assert "CREATE" in body["source"].upper()
    assert body["source"].upper().count("TRIGGER") >= 1


def test_q2_budget_matches_documented_values(admin_client):
    rows = admin_client.get("/api/queries/Q2").json()["rows"]
    by_title = {r["title"]: r for r in rows}
    assert by_title["Goa Beach Escape"]["actual_spend"] == 30000.0
    assert by_title["Rajasthan Heritage Tour"]["actual_spend"] == 14600.0
    assert by_title["Munnar Monsoon Getaway"]["actual_spend"] == 30600.0
    assert by_title["Hampi and Coorg Road Trip"]["actual_spend"] == 22100.0
    assert by_title["Manali Winter Break"]["actual_spend"] == 5500.0


def test_q6_free_rooms_is_six(admin_client):
    body = admin_client.get("/api/queries/Q6").json()
    assert body["row_count"] == 6


def test_q12_integrity_returns_no_rows(admin_client):
    assert admin_client.get("/api/queries/Q12").json()["row_count"] == 0


def test_b2_budget_dashboard_matches_documented_values(admin_client):
    rows = admin_client.get("/api/queries/B2").json()["rows"]
    by_title = {r["title"]: r for r in rows}
    assert by_title["Goa Beach Escape"]["total_booked"] == 45240.0
    assert by_title["Goa Beach Escape"]["booked_pct_of_budget"] == 75.4
    assert by_title["Manali Winter Break"]["booked_pct_of_budget"] == 34.1


def test_t5_fare_per_passenger(admin_client):
    rows = admin_client.get("/api/queries/T5").json()["rows"]
    by_mode = {r["transport_mode"]: r for r in rows}
    assert by_mode["flight"]["fare_per_passenger"] == 4000.0
    assert by_mode["cab"]["fare_per_passenger"] == 1092.31
    assert by_mode["bus"]["fare_per_passenger"] == 840.0


def test_a1_amenity_counts(admin_client):
    rows = admin_client.get("/api/queries/A1").json()["rows"]
    by_name = {r["amenity"]: r for r in rows}
    assert by_name["Wi-Fi"]["hotels_offering"] == 8
    assert by_name["Wi-Fi"]["free_at"] == 7
    assert by_name["Spa"]["paid_at"] == 5
    assert by_name["Gym"]["hotels_offering"] == 0


def test_query_parameter_override(admin_client):
    body = admin_client.get("/api/queries/T1?params=2").json()
    assert body["row_count"] > 0
    assert body["params"] == ["2"]


def test_unknown_query_is_404(admin_client):
    assert admin_client.get("/api/queries/ZZZ").status_code == 404


def test_all_rule_tests_are_rejected(admin_client):
    body = admin_client.post("/api/rules/run").json()
    assert body["total"] == 25
    assert body["passed"] == 25
    for r in body["results"]:
        assert r["rejected"], f"{r['id']} was not rejected: {r['actual']}"


def test_rule_tests_do_not_change_data(admin_client):
    before = admin_client.get("/api/queries/Q2").json()["rows"]
    admin_client.post("/api/rules/run")
    after = admin_client.get("/api/queries/Q2").json()["rows"]
    assert before == after


def test_cascade_deletes_children(admin_client):
    body = admin_client.post("/api/cascades/C14/run").json()
    assert body["before"][0]["days"] == 5
    assert body["after"][0]["days"] == 0


def test_set_null_keeps_the_item(admin_client):
    body = admin_client.post("/api/cascades/SETNULL/run").json()
    assert body["before"][0]["place_id"] == 2
    assert body["after"][0]["place_id"] is None
    assert body["after"][0]["title"] == "Visit Fort Aguada"


def test_alert_demo_raises_two_alerts_without_duplicates(admin_client):
    body = admin_client.post("/api/alerts/run").json()
    types = [a["alert_type"] for a in body["alerts"]]
    assert types == ["budget_80", "budget_exceeded"]
    assert body["alert_count"] == 2


def test_audit_demo_writes_six_rows(admin_client):
    body = admin_client.post("/api/audit/run").json()
    assert body["log_count"] == 6
    assert any(r["action"] == "DELETE" for r in body["log"])


def test_create_trip_procedure_rolls_back_by_default(admin_client):
    body = admin_client.post(
        "/api/procedures/create-trip",
        params={"owner_id": 2, "title": "pytest trip", "start_date": "2027-03-01",
                "end_date": "2027-03-03", "budget": 10000},
    ).json()
    assert len(body["days"]) == 3
    assert len(body["members"]) == 1
    assert body["members"][0]["role"] == "owner"
    assert body.get("rolled_back") is True


def test_book_room_rejects_double_booking(admin_client):
    created = admin_client.post(
        "/api/procedures/create-trip",
        params={"owner_id": 2, "title": "Demo: pytest booking", "start_date": "2027-04-01",
                "end_date": "2027-04-04", "budget": 20000, "keep": True},
    ).json()
    trip_id = created["new_trip_id"]
    try:
        first = admin_client.post(
            "/api/procedures/book-room",
            params={"trip_id": trip_id, "room_id": 31, "booked_by": 2,
                    "check_in": "2027-04-01", "check_out": "2027-04-03", "guests": 2},
        )
        assert first.status_code == 200
        assert first.json()["summary"][0]["confirmation_code"].startswith("HB")

        second = admin_client.post(
            "/api/procedures/book-room",
            params={"trip_id": trip_id, "room_id": 31, "booked_by": 2,
                    "check_in": "2027-04-02", "check_out": "2027-04-04", "guests": 2},
        )
        assert second.status_code == 400
        assert "already reserved" in second.json()["detail"]
    finally:
        admin_client.post("/api/procedures/cleanup")


def test_recommendations_exclude_visited_destinations(admin_client):
    body = admin_client.get("/api/recommendations", params={"user_id": 2, "month": 3}).json()
    names = [d["name"] for d in body["results"]]
    assert "Goa" not in names
    assert body["results"], "expected at least one suggestion"
    scores = [d["score"] for d in body["results"]]
    assert scores == sorted(scores, reverse=True)


def test_recommendation_season_flag_flips_with_month(admin_client):
    jan = admin_client.get("/api/recommendations", params={"user_id": 1, "month": 1, "limit": 20}).json()
    jul = admin_client.get("/api/recommendations", params={"user_id": 1, "month": 7, "limit": 20}).json()
    jan_season = {d["name"]: d["in_season"] for d in jan["results"]}
    jul_season = {d["name"]: d["in_season"] for d in jul["results"]}
    assert jan_season.get("Manali") is True
    assert jul_season.get("Manali") is False


def test_dashboard_is_served(admin_client):
    r = admin_client.get("/")
    assert r.status_code == 200
    assert "Travel Itinerary" in r.text


def test_login_page_is_public():
    assert TestClient(app).get("/login").status_code == 200


# ---------------------------------------------------------------- authentication
def test_data_routes_require_sign_in():
    anon = TestClient(app)
    assert anon.get("/api/health").status_code == 401
    assert anon.get("/api/overview").status_code == 401
    assert anon.get("/api/queries").status_code == 401
    assert anon.get("/api/users").status_code == 401
    assert anon.get("/api/auth/me").status_code == 401


def test_wrong_password_is_rejected():
    c = TestClient(app)
    r = c.post("/api/auth/login", json={"email": ADMIN["email"], "password": "definitely-wrong"})
    assert r.status_code == 401


def test_unknown_account_is_rejected_with_the_same_message():
    c = TestClient(app)
    r = c.post("/api/auth/login", json={"email": "nobody@example.com", "password": "whatever"})
    assert r.status_code == 401
    # The message must not reveal whether the account exists.
    assert r.json()["detail"] == "Invalid e-mail or password"


def test_login_sets_an_httponly_cookie():
    c = TestClient(app)
    r = c.post("/api/auth/login", json=ADMIN)
    assert r.status_code == 200
    assert "password" not in r.text and "password_hash" not in r.text
    set_cookie = r.headers.get("set-cookie", "")
    assert "httponly" in set_cookie.lower()
    assert "samesite=lax" in set_cookie.lower()


def test_logout_clears_the_session():
    c = TestClient(app)
    token = c.post("/api/auth/login", json=ADMIN).json()["csrf_token"]
    assert c.get("/api/health").status_code == 200
    c.post("/api/auth/logout", headers={"X-CSRF-Token": token})
    assert c.get("/api/health").status_code == 401


def test_tampered_session_cookie_is_rejected():
    c = TestClient(app)
    c.post("/api/auth/login", json=ADMIN)
    token = c.cookies.get("travel_session")
    c.cookies.set("travel_session", token[:-4] + "aaaa")
    assert c.get("/api/health").status_code == 401


def test_viewer_can_read_but_cannot_change_data(viewer_client):
    assert viewer_client.get("/api/overview").status_code == 200
    assert viewer_client.post("/api/rules/run").status_code == 403
    assert viewer_client.post("/api/alerts/run").status_code == 403
    assert viewer_client.post("/api/audit/run").status_code == 403
    assert viewer_client.post("/api/procedures/cleanup").status_code == 403


def test_admin_can_change_data(admin_client):
    assert admin_client.post("/api/alerts/run").status_code == 200


def test_session_token_never_carries_the_password_hash():
    from app import auth

    token = auth.make_session({"user_id": 1, "email": "a@b.c", "full_name": "A B", "role": "admin"})
    body = auth.read_session(token)
    assert body["uid"] == 1
    assert "password" not in str(body).lower()


def test_bundle_download_contains_the_app_files(admin_client):
    import io
    import zipfile

    r = admin_client.get("/api/bundle")
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/zip"
    names = zipfile.ZipFile(io.BytesIO(r.content)).namelist()
    assert "app/main.py" in names
    assert "static/login.html" in names
    assert "tests/test_api.py" in names


# ---------------------------------------------------------------- CSRF
def test_login_issues_a_csrf_token():
    c = TestClient(app)
    r = c.post("/api/auth/login", json=ADMIN)
    assert r.status_code == 200
    token = r.json()["csrf_token"]
    assert token and len(token) > 20
    assert c.cookies.get("travel_csrf") == token


def test_write_without_csrf_header_is_rejected():
    c = TestClient(app)
    c.post("/api/auth/login", json=ADMIN)
    # The client is signed in but never sends the header.
    assert c.post("/api/alerts/run").status_code == 403


def test_write_with_a_wrong_csrf_header_is_rejected():
    c = TestClient(app)
    c.post("/api/auth/login", json=ADMIN)
    r = c.post("/api/alerts/run", headers={"X-CSRF-Token": "not-the-real-token"})
    assert r.status_code == 403


def test_write_with_the_correct_csrf_header_succeeds():
    c = TestClient(app)
    token = c.post("/api/auth/login", json=ADMIN).json()["csrf_token"]
    r = c.post("/api/alerts/run", headers={"X-CSRF-Token": token})
    assert r.status_code == 200


def test_csrf_endpoint_issues_a_token_for_an_existing_session():
    c = TestClient(app)
    c.post("/api/auth/login", json=ADMIN)
    c.cookies.delete("travel_csrf")
    token = c.get("/api/auth/csrf").json()["csrf_token"]
    assert c.post("/api/audit/run", headers={"X-CSRF-Token": token}).status_code == 200


def test_reads_do_not_need_a_csrf_token(admin_client):
    assert admin_client.get("/api/overview").status_code == 200


# ---------------------------------------------------------------- sign-up
def test_registration_creates_a_normal_user_and_signs_in():
    import uuid

    c = TestClient(app)
    email = f"test.{uuid.uuid4().hex[:10]}@example.com"
    r = c.post("/api/auth/register", json={
        "full_name": "Test Newcomer", "email": email, "password": "Str0ng-Passphrase",
    })
    assert r.status_code == 200, r.text
    user = r.json()["user"]
    assert user["role"] == "user"
    assert user["email"] == email
    assert "password" not in r.text
    # The new account is signed in and can read data, but not write it.
    assert c.get("/api/health").status_code == 200
    token = r.json()["csrf_token"]
    assert c.post("/api/alerts/run", headers={"X-CSRF-Token": token}).status_code == 403

    from app import db
    db.execute("DELETE FROM users WHERE email = %s", (email,))


def test_registration_never_grants_admin_even_if_asked():
    import uuid

    from app import db

    c = TestClient(app)
    email = f"test.{uuid.uuid4().hex[:10]}@example.com"
    r = c.post("/api/auth/register", json={
        "full_name": "Sneaky", "email": email, "password": "Str0ng-Passphrase",
        "role": "admin", "user_id": 1,
    })
    assert r.status_code == 200
    assert r.json()["user"]["role"] == "user"
    stored = db.query("SELECT role FROM users WHERE email = %s", (email,))
    assert stored[0]["role"] == "user"
    db.execute("DELETE FROM users WHERE email = %s", (email,))


def test_duplicate_email_is_rejected():
    c = TestClient(app)
    r = c.post("/api/auth/register", json={
        "full_name": "Copy Cat", "email": ADMIN["email"], "password": "Str0ng-Passphrase",
    })
    assert r.status_code == 409


def test_weak_registration_input_is_rejected():
    c = TestClient(app)
    bad = [
        {"full_name": "A", "email": "x@y.com", "password": "Str0ng-Passphrase"},
        {"full_name": "Valid Name", "email": "not-an-email", "password": "Str0ng-Passphrase"},
        {"full_name": "Valid Name", "email": "ok@example.com", "password": "short"},
        {"full_name": "Valid Name", "email": "alice@example.com", "password": "alicealice"},
    ]
    for payload in bad:
        assert c.post("/api/auth/register", json=payload).status_code in (400, 422), payload


def test_registered_user_can_sign_in_again():
    import uuid

    from app import db

    email = f"test.{uuid.uuid4().hex[:10]}@example.com"
    password = "Str0ng-Passphrase"
    TestClient(app).post("/api/auth/register", json={
        "full_name": "Returning User", "email": email, "password": password,
    })
    again = TestClient(app)
    r = again.post("/api/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200
    assert r.json()["user"]["email"] == email
    db.execute("DELETE FROM users WHERE email = %s", (email,))


# ------------------------------------------------------- traveller travel app
# These exercise /api/travel, the consumer-facing planner. Every test cleans up
# after itself so the documented counts in the DBMS tests stay true.


@pytest.fixture
def travel_trip(admin_client):
    """A throwaway trip owned by the admin, removed when the test ends."""
    from app import db

    r = admin_client.post("/api/travel/trips", json={
        "title": "pytest travel trip", "start_date": "2027-03-01",
        "end_date": "2027-03-05", "budget_total": 50000,
    })
    assert r.status_code == 201, r.text
    trip_id = r.json()["trip_id"]
    yield trip_id
    db.execute("DELETE FROM expenses WHERE trip_id = %s", (trip_id,))
    db.execute("DELETE FROM hotel_reservations WHERE trip_id = %s", (trip_id,))
    db.execute("DELETE FROM itinerary_days WHERE trip_id = %s", (trip_id,))
    db.execute("DELETE FROM trip_members WHERE trip_id = %s", (trip_id,))
    db.execute("DELETE FROM trips WHERE trip_id = %s", (trip_id,))
    # Booking and cancelling write audit rows; drop them so the audit demo test
    # and the documented counts stay accurate.
    db.execute("DELETE FROM audit_log WHERE changed_at >= NOW() - INTERVAL 10 MINUTE")


def test_travel_requires_sign_in():
    anon = TestClient(app)
    assert anon.get("/api/travel/destinations").status_code == 401
    assert anon.get("/api/travel/trips").status_code == 401


def test_travel_write_requires_csrf(admin_client):
    no_header = TestClient(app)
    r = no_header.post("/api/auth/login", json=ADMIN)
    assert r.status_code == 200
    r = no_header.post("/api/travel/trips", json={
        "title": "no csrf", "start_date": "2027-03-01",
        "end_date": "2027-03-02", "budget_total": 100,
    })
    assert r.status_code == 403


def test_destinations_list_carries_prices_and_ratings(admin_client):
    body = admin_client.get("/api/travel/destinations").json()
    assert len(body) == 7
    goa = next(d for d in body if d["name"] == "Goa")
    assert goa["hotels"] == 2
    assert goa["from_price"] == 3200.0
    assert goa["avg_rating"] > 0


def test_hotel_detail_joins_places_for_name_and_amenities(admin_client):
    body = admin_client.get("/api/travel/hotels/3").json()
    assert body["name"] == "Seaside Palms Resort"
    assert body["destination"] == "Goa"
    assert body["star_rating"] == 4
    names = {a["name"] for a in body["amenities"]}
    assert {"Wi-Fi", "Swimming Pool", "Spa"} <= names
    assert len(body["room_types"]) == 2


def test_availability_excludes_overlapping_stays(admin_client):
    # Reservation 3 already occupies room 5 on the Goa trip dates.
    free = admin_client.get("/api/travel/hotels/3/availability", params={
        "check_in": "2026-12-26", "check_out": "2026-12-30", "guests": 2,
    }).json()
    taken = admin_client.get("/api/travel/hotels/3/availability", params={
        "check_in": "2026-12-26", "check_out": "2026-12-30", "guests": 1,
    }).json()
    assert all(r["max_occupancy"] >= 2 for r in free)
    # Room 2 is under maintenance, so it must never appear.
    assert 2 not in {r["room_id"] for r in taken}


def test_availability_rejects_reversed_dates(admin_client):
    r = admin_client.get("/api/travel/hotels/3/availability", params={
        "check_in": "2026-12-30", "check_out": "2026-12-26",
    })
    assert r.status_code == 400


def test_trip_can_be_created_and_read_back(admin_client, travel_trip):
    body = admin_client.get(f"/api/travel/trips/{travel_trip}").json()
    assert body["title"] == "pytest travel trip"
    assert body["my_role"] == "owner"
    # sp_create_trip must have generated one day per date in the range.
    assert len(body["days"]) == 5
    assert [d["day_number"] for d in body["days"]] == [1, 2, 3, 4, 5]


def test_trip_rejects_end_before_start(admin_client):
    r = admin_client.post("/api/travel/trips", json={
        "title": "backwards", "start_date": "2027-03-05",
        "end_date": "2027-03-01", "budget_total": 100,
    })
    assert r.status_code == 400


def test_booking_succeeds_inside_the_trip_window(admin_client, travel_trip):
    body = admin_client.post("/api/travel/bookings", json={
        "trip_id": travel_trip, "room_id": 1, "check_in": "2027-03-02",
        "check_out": "2027-03-04", "num_guests": 2,
    }).json()
    assert body["reservation_id"]
    res = body["reservation"]
    assert res["confirmation_code"].startswith("HB")
    assert res["nights"] == 2
    assert res["total_cost"] == 9000.0


def test_booking_is_refused_when_room_is_already_taken(admin_client, travel_trip):
    first = admin_client.post("/api/travel/bookings", json={
        "trip_id": travel_trip, "room_id": 1, "check_in": "2027-03-02",
        "check_out": "2027-03-04", "num_guests": 2,
    })
    assert first.status_code == 201
    clash = admin_client.post("/api/travel/bookings", json={
        "trip_id": travel_trip, "room_id": 1, "check_in": "2027-03-03",
        "check_out": "2027-03-05", "num_guests": 2,
    })
    assert clash.status_code == 400
    assert "already reserved" in clash.json()["detail"]


def test_booking_is_refused_over_room_capacity(admin_client, travel_trip):
    r = admin_client.post("/api/travel/bookings", json={
        "trip_id": travel_trip, "room_id": 1, "check_in": "2027-03-02",
        "check_out": "2027-03-03", "num_guests": 9,
    })
    assert r.status_code == 400
    assert "capacity" in r.json()["detail"]


def test_booking_is_refused_outside_the_trip_dates(admin_client, travel_trip):
    r = admin_client.post("/api/travel/bookings", json={
        "trip_id": travel_trip, "room_id": 1, "check_in": "2027-06-01",
        "check_out": "2027-06-03", "num_guests": 2,
    })
    assert r.status_code == 400
    assert "inside the trip dates" in r.json()["detail"]


def test_booking_is_refused_for_a_trip_you_do_not_belong_to(admin_client):
    # Trip 1 belongs to user 2; the admin is not a member, so the trigger stops it.
    r = admin_client.post("/api/travel/bookings", json={
        "trip_id": 1, "room_id": 1, "check_in": "2026-12-27",
        "check_out": "2026-12-28", "num_guests": 1,
    })
    assert r.status_code == 400
    assert "owner or editor" in r.json()["detail"]


def test_cancelling_a_booking_keeps_the_room_free(admin_client, travel_trip):
    created = admin_client.post("/api/travel/bookings", json={
        "trip_id": travel_trip, "room_id": 1, "check_in": "2027-03-02",
        "check_out": "2027-03-04", "num_guests": 2,
    }).json()
    rid = created["reservation_id"]
    assert admin_client.post(f"/api/travel/bookings/{rid}/cancel").status_code == 200
    # A cancelled stay must not block the same room on the same nights.
    again = admin_client.post("/api/travel/bookings", json={
        "trip_id": travel_trip, "room_id": 1, "check_in": "2027-03-02",
        "check_out": "2027-03-04", "num_guests": 2,
    })
    assert again.status_code == 201
    assert admin_client.post(f"/api/travel/bookings/{rid}/cancel").status_code == 400


def test_expense_over_budget_raises_a_trip_alert(admin_client, travel_trip):
    body = admin_client.post("/api/travel/expenses", json={
        "trip_id": travel_trip, "expense_category_id": 1, "amount": 45000,
        "expense_date": "2027-03-02", "description": "pytest big spend",
    }).json()
    assert body["expense_id"]
    types = {a["alert_type"] for a in body["alerts"]}
    assert "budget_80" in types
    assert body["costs"]["actual_spend"] == 45000.0


def test_expense_requires_trip_membership(admin_client):
    r = admin_client.post("/api/travel/expenses", json={
        "trip_id": 1, "expense_category_id": 1, "amount": 100,
        "expense_date": "2026-12-27", "description": "not my trip",
    })
    assert r.status_code == 403


def test_expense_rejects_a_negative_amount(admin_client, travel_trip):
    r = admin_client.post("/api/travel/expenses", json={
        "trip_id": travel_trip, "expense_category_id": 1, "amount": -50,
        "expense_date": "2027-03-02", "description": "negative",
    })
    assert r.status_code == 422


def test_wishlist_toggles_on_and_off(admin_client):
    from app import db

    dest = 3  # Munnar; the seeded user 1 does not have it saved
    db.execute("DELETE FROM saved_destinations WHERE user_id = 1 AND destination_id = %s", (dest,))
    try:
        assert admin_client.post(f"/api/travel/wishlist/{dest}").json()["saved"] is True
        names = {d["name"] for d in admin_client.get("/api/travel/wishlist").json()}
        assert "Munnar" in names
        assert admin_client.post(f"/api/travel/wishlist/{dest}").json()["saved"] is False
        names = {d["name"] for d in admin_client.get("/api/travel/wishlist").json()}
        assert "Munnar" not in names
    finally:
        db.execute("DELETE FROM saved_destinations WHERE user_id = 1 AND destination_id = %s", (dest,))


def test_wishlist_unknown_destination_is_404(admin_client):
    assert admin_client.post("/api/travel/wishlist/99999").status_code == 404


def test_search_finds_destinations_and_hotels(admin_client):
    body = admin_client.get("/api/travel/search", params={"q": "goa"}).json()
    assert [d["name"] for d in body["destinations"]] == ["Goa"]
    assert {h["name"] for h in body["hotels"]} == {
        "Seaside Palms Resort", "Casa Azul Boutique Stay"}


def test_recommendations_skip_visited_destinations(admin_client):
    body = admin_client.get("/api/travel/recommendations", params={"limit": 3}).json()
    assert body["results"]
    visited = set(body["visited_destination_ids"])
    assert all(r["destination_id"] not in visited for r in body["results"])
    assert all(r["reasons"] for r in body["results"])


def test_profile_reports_the_signed_in_user(admin_client):
    body = admin_client.get("/api/travel/profile").json()
    assert body["user"]["email"] == ADMIN["email"]
    assert set(body["stats"]) >= {"trips", "wishlist", "reviews", "stays", "spend"}


def test_app_page_is_served():
    assert TestClient(app).get("/app").status_code == 200


def test_bundle_includes_the_travel_app(admin_client):
    import io
    import zipfile

    r = admin_client.get("/api/bundle")
    assert r.status_code == 200
    names = zipfile.ZipFile(io.BytesIO(r.content)).namelist()
    assert "app/travel.py" in names
    assert "static/app.html" in names



# --------------------------------------------------------------- hashing
def test_passwords_are_bcrypt_after_login():
    """A legacy SHA-256 row is rewritten as bcrypt the first time it is used."""
    import hashlib

    from app import auth, db

    email = "rohan.mehta@example.com"
    password = "Rohan@123"
    # Start from a known legacy state so this test is repeatable.
    db.execute("UPDATE users SET password_hash = %s WHERE email = %s",
               (hashlib.sha256(password.encode()).hexdigest(), email))
    before = db.query("SELECT password_hash FROM users WHERE email = %s", (email,))[0]
    assert auth._LEGACY_HASH_RE.match(before["password_hash"]), "expected a legacy digest"

    c = TestClient(app)
    assert c.post("/api/auth/login", json={"email": email, "password": password}).status_code == 200

    after = db.query("SELECT password_hash FROM users WHERE email = %s", (email,))[0]
    assert after["password_hash"].startswith("$2b$"), "should be upgraded to bcrypt"
    assert after["password_hash"] != before["password_hash"]
    # The plaintext must never be recoverable from the stored value.
    assert password not in after["password_hash"]
    # And the upgraded row must still accept the same password next time.
    assert TestClient(app).post(
        "/api/auth/login", json={"email": email, "password": password}).status_code == 200


def test_bcrypt_hashes_are_salted_and_verifiable():
    from app import auth

    a = auth.hash_password("CorrectHorse1")
    b = auth.hash_password("CorrectHorse1")
    assert a != b, "the same password must not produce the same hash"
    assert auth.verify_password("CorrectHorse1", a)
    assert auth.verify_password("CorrectHorse1", b)
    assert not auth.verify_password("wrong-password", a)


def test_legacy_sha256_hash_still_verifies():
    """The upgrade path must not lock out an account that has not signed in yet."""
    import hashlib

    from app import auth

    digest = hashlib.sha256(b"Legacy@123").hexdigest()
    assert auth.verify_password("Legacy@123", digest)
    assert not auth.verify_password("nope", digest)
    assert auth.needs_rehash(digest)
    assert not auth.needs_rehash(auth.hash_password("Modern@123"))


# --------------------------------------------------------------- sessions
def test_session_reports_a_thirty_minute_window():
    c = TestClient(app)
    assert c.post("/api/auth/login", json=ADMIN).status_code == 200
    body = c.get("/api/auth/session").json()
    assert body["active"] is True
    assert body["ttl_seconds"] == 1800
    assert 0 < body["expires_in"] <= 1800
    assert body["absolute_expires_in"] >= body["expires_in"]


def test_session_endpoint_is_anonymous_friendly():
    body = TestClient(app).get("/api/auth/session").json()
    assert body == {"active": False}


def test_logout_revokes_only_the_presented_session():
    """Signing out on one client must not sign the account out everywhere."""
    a = TestClient(app)
    b = TestClient(app)
    ta = a.post("/api/auth/login", json=ADMIN).json()["csrf_token"]
    b.post("/api/auth/login", json=ADMIN)

    assert a.post("/api/auth/logout", headers={"X-CSRF-Token": ta}).status_code == 200
    assert a.get("/api/health").status_code == 401, "the logged-out client is done"
    assert b.get("/api/health").status_code == 200, "the other session survives"


def test_expired_session_is_rejected(monkeypatch):
    from app import auth

    monkeypatch.setattr(auth, "SESSION_TTL_SECONDS", -1)
    token = auth.make_session({"user_id": 1, "email": "x@y.z", "full_name": "X", "role": "user"})
    assert auth.read_session(token) is None
    assert auth.session_state(token) == {"active": False}


# --------------------------------------------------------------- permissions
def test_permissions_list_both_allowed_and_denied(viewer_client):
    body = viewer_client.get("/api/me/permissions").json()
    assert body["user"]["role"] == "user"
    assert "run_rule_tests" in body["global_cannot"]
    assert "browse_destinations" in body["global_can"]
    # Every denial carries a sentence a person can act on.
    assert all(a["reason"] for a in body["global"] if not a["allowed"])
    assert all(a["reason"] for a in body["global"] if a["allowed"])


def test_admin_permissions_are_a_superset(admin_client, viewer_client):
    admin = admin_client.get("/api/me/permissions").json()
    assert admin["global_cannot"] == []
    assert set(viewer_client.get("/api/me/permissions").json()["global_can"]) < set(admin["global_can"])


def test_trip_matrix_matches_the_role(viewer_client):
    trips = {t["trip_id"]: t for t in viewer_client.get("/api/me/trips").json()}
    # Priya owns trip 1, edits trip 2 and only views trip 5.
    assert trips[1]["my_role"] == "owner"
    assert trips[1]["capabilities"]["delete_trip"]["allowed"] is True
    assert trips[2]["my_role"] == "editor"
    assert trips[2]["capabilities"]["book_room"]["allowed"] is True
    assert trips[2]["capabilities"]["delete_trip"]["allowed"] is False
    assert trips[5]["my_role"] == "viewer"
    assert trips[5]["capabilities"]["book_room"]["allowed"] is False
    assert "view" in trips[5]["can"] and "book_room" in trips[5]["cannot"]


def test_booking_options_separate_bookable_from_blocked(viewer_client):
    body = viewer_client.get("/api/me/booking-options").json()
    assert body["can_book_any"] is True
    bookable = {t["trip_id"] for t in body["bookable"]}
    blocked = {t["trip_id"] for t in body["blocked"]}
    assert bookable == {1, 2}
    assert blocked == {5}
    assert all(t["why"] for t in body["blocked"])


def test_booking_a_viewer_trip_explains_instead_of_failing(viewer_client):
    """The dead end from the demo: a clear reason plus the trips that do work."""
    r = viewer_client.post("/api/travel/bookings", json={
        "trip_id": 5, "room_id": 19,
        "check_in": "2027-01-08", "check_out": "2027-01-10", "num_guests": 2,
    })
    assert r.status_code == 403
    detail = r.json()["detail"]
    assert "viewer" in detail["message"]
    assert {t["trip_id"] for t in detail["bookable"]} == {1, 2}


def test_travel_access_endpoint_returns_the_matrix(viewer_client):
    body = viewer_client.get("/api/travel/access").json()
    assert body["booking"]["can_book_any"] is True
    assert {t["trip_id"] for t in body["trips"]} == {1, 2, 5}
    assert body["actions"], "the action catalog should be included for the UI"


def test_trip_list_carries_capabilities(viewer_client):
    for trip in viewer_client.get("/api/travel/trips").json():
        assert "capabilities" in trip and "can" in trip and "cannot" in trip
        assert trip["capabilities"]["view"]["allowed"] is True


# --------------------------------------------------------------- hardening
def test_security_headers_are_present():
    r = TestClient(app).get("/login")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"
    assert r.headers["referrer-policy"] == "same-origin"
    assert "frame-ancestors 'none'" in r.headers["content-security-policy"]
    assert "default-src 'self'" in r.headers["content-security-policy"]


def test_registration_rejects_a_common_password():
    r = TestClient(app).post("/api/auth/register", json={
        "full_name": "Test Person", "email": "common.pw@example.com", "password": "password123",
    })
    assert r.status_code == 400
    assert "common" in r.json()["detail"].lower()


def test_registration_never_grants_admin():
    import uuid

    address = f"probe-{uuid.uuid4().hex[:8]}@example.com"
    c = TestClient(app)
    r = c.post("/api/auth/register", json={
        "full_name": "Probe User", "email": address, "password": "Str0ngPass!x",
    })
    assert r.status_code == 200
    assert r.json()["user"]["role"] == "user"
    assert c.get("/api/me/permissions").json()["global_cannot"], "a new user is not an admin"

    from app import db

    db.execute("DELETE FROM users WHERE email = %s", (address,))
