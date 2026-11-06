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
