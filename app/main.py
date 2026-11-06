"""FastAPI service over the travel_itinerary_db MySQL schema.

The database enforces the business rules (31 triggers, 41 foreign keys, CHECK
constraints, 2 procedures). This API validates input, runs the project's demo
queries and rule tests, and shapes JSON for the dashboard.
"""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import auth, catalog, db, recommender, travel

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent
STATIC_DIR = BASE_DIR / "static"

app = FastAPI(
    title="Travel Itinerary and Expense Organizer API",
    description="A FastAPI layer over the travel_itinerary_db MySQL schema.",
    version="1.1.0",
)

if STATIC_DIR.is_dir():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# The traveller-facing routes live in their own module; the routes above are the
# DBMS dashboard that inspects the schema.
app.include_router(travel.router)


class Credentials(BaseModel):
    email: str = Field(min_length=3, max_length=100)
    password: str = Field(min_length=1, max_length=200)


class SignUp(BaseModel):
    full_name: str = Field(min_length=2, max_length=80)
    email: str = Field(min_length=3, max_length=100)
    password: str = Field(min_length=8, max_length=200)


def _set_session_cookie(response: Response, token: str) -> None:
    secure = os.getenv("COOKIE_SECURE", "false").lower() == "true"
    response.set_cookie(
        auth.SESSION_COOKIE, token, max_age=auth.SESSION_TTL_SECONDS,
        httponly=True, samesite="lax", secure=secure, path="/",
    )


def _set_csrf_cookie(response: Response) -> str:
    """Issue the double-submit CSRF token. Readable by page scripts on purpose."""
    token = auth.issue_csrf_token()
    secure = os.getenv("COOKIE_SECURE", "false").lower() == "true"
    response.set_cookie(
        auth.CSRF_COOKIE, token, max_age=auth.SESSION_TTL_SECONDS,
        httponly=False, samesite="lax", secure=secure, path="/",
    )
    return token


# Every data route below requires a signed-in user. Routes that change data
# additionally require the admin role, because the demo scripts would otherwise
# let any visitor write to the shared database. Unsafe methods must also carry
# the CSRF header, which only same-origin page scripts can read.
def signed_in(user: dict = Depends(auth.current_user)) -> dict:
    return user


def csrf_protect(_: None = Depends(auth.verify_csrf)) -> None:
    """Resolve the CSRF check as a dependency, so FastAPI reads cookie and header."""
    return None


def admin_only(
    user: dict = Depends(auth.current_user),
    _: None = Depends(csrf_protect),
) -> dict:
    return auth.admin_dependency(user)


def signed_in_csrf(
    user: dict = Depends(auth.current_user),
    _: None = Depends(csrf_protect),
) -> dict:
    return user


# ------------------------------------------------------------------ auth
@app.post("/api/auth/login")
def login(creds: Credentials, request: Request, response: Response) -> dict:
    """Verify credentials and set the signed session cookie plus a CSRF token."""
    user = auth.authenticate(creds.email, creds.password, request)
    _set_session_cookie(response, auth.make_session(user))
    csrf = _set_csrf_cookie(response)
    return {"user": user, "csrf_token": csrf}


@app.post("/api/auth/register")
def sign_up(payload: SignUp, response: Response) -> dict:
    """Create a normal user account and sign it in.

    The role is fixed to 'user'; admin accounts are never created over the API.
    """
    user = auth.register(payload.full_name, payload.email, payload.password)
    _set_session_cookie(response, auth.make_session(user))
    csrf = _set_csrf_cookie(response)
    return {"user": user, "csrf_token": csrf}


@app.post("/api/auth/logout")
def logout(response: Response, _: None = Depends(csrf_protect)) -> dict:
    response.delete_cookie(auth.SESSION_COOKIE, path="/")
    response.delete_cookie(auth.CSRF_COOKIE, path="/")
    return {"ok": True}


@app.get("/api/auth/me")
def me(user: dict = Depends(auth.current_user)) -> dict:
    return {"user": user}


@app.get("/api/auth/csrf")
def csrf_token(response: Response) -> dict:
    """Issue a CSRF token so a page can make unsafe calls after a reload.

    The token lives in a readable cookie, so the page only needs this on a fresh
    load; after that it reads the cookie directly.
    """
    return {"csrf_token": _set_csrf_cookie(response)}


# ------------------------------------------------------------------ meta
@app.get("/api/health")
def health(_: dict = Depends(signed_in)) -> dict:
    """Connection status and the acceptance counts (32/41/31/4)."""
    return db.health()


@app.get("/api/overview")
def overview(_: dict = Depends(signed_in)) -> dict:
    """Counts per object kind plus the live table inventory.

    information_schema.table_rows is only an InnoDB estimate, so exact counts are
    taken with COUNT(*) for every base table.
    """
    names = [r["table_name"] for r in db.query(
        "SELECT table_name AS table_name FROM information_schema.tables "
        "WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' ORDER BY table_name"
    )]
    tables = []
    for name in names:
        tables.append({"table_name": name, "rows": db.scalar(f"SELECT COUNT(*) FROM `{name}`")})
    return {
        "health": db.health(),
        "tables": tables,
        "views": [r["name"] for r in db.query(
            "SELECT table_name AS name FROM information_schema.views "
            "WHERE table_schema = DATABASE() ORDER BY table_name")],
        "procedures": [r["name"] for r in db.query(
            "SELECT routine_name AS name FROM information_schema.routines "
            "WHERE routine_schema = DATABASE() ORDER BY routine_name")],
    }


@app.get("/api/triggers")
def triggers(_: dict = Depends(signed_in)) -> list[dict]:
    """Every trigger with its table, timing and event (31 rows)."""
    return db.query(
        "SELECT trigger_name, event_object_table AS on_table, action_timing AS timing, "
        "event_manipulation AS event FROM information_schema.triggers "
        "WHERE trigger_schema = DATABASE() ORDER BY action_timing, event_object_table, trigger_name"
    )


@app.get("/api/triggers/{name}")
def trigger_source(name: str, _: dict = Depends(signed_in)) -> dict:
    """The CREATE TRIGGER source, for the viva explanation."""
    safe = name.replace("`", "")
    rows = db.query(f"SHOW CREATE TRIGGER `{safe}`")
    if not rows:
        raise HTTPException(404, f"No trigger named {name}")
    row = rows[0]
    body = next((v for k, v in row.items() if "original" in k.lower()), None)
    return {"name": name, "source": body}


@app.get("/api/fks")
def foreign_keys(_: dict = Depends(signed_in)) -> list[dict]:
    """Foreign keys with their ON DELETE / ON UPDATE rules (41 rows)."""
    return db.query(
        "SELECT constraint_name, table_name, referenced_table_name, delete_rule, update_rule "
        "FROM information_schema.referential_constraints "
        "WHERE constraint_schema = DATABASE() ORDER BY table_name, constraint_name"
    )


# ------------------------------------------------------------------ reference data
@app.get("/api/trips")
def trips(_: dict = Depends(signed_in)) -> list[dict]:
    return db.query(
        "SELECT t.trip_id, t.title, t.start_date, t.end_date, t.budget_total, t.status, "
        "u.full_name AS owner FROM trips t JOIN users u ON u.user_id = t.owner_id "
        "ORDER BY t.trip_id"
    )


@app.get("/api/users")
def users(_: dict = Depends(signed_in)) -> list[dict]:
    return db.query("SELECT user_id, full_name, email, role FROM users ORDER BY user_id")


@app.get("/api/rooms")
def rooms(_: dict = Depends(signed_in)) -> list[dict]:
    return db.query(
        "SELECT r.room_id, r.room_number, r.status, p.name AS hotel, rt.name AS room_type, "
        "rt.max_occupancy, rt.base_rate FROM rooms r "
        "JOIN places p ON p.place_id = r.hotel_id "
        "JOIN room_types rt ON rt.room_type_id = r.room_type_id AND rt.hotel_id = r.hotel_id "
        "ORDER BY r.room_id"
    )


# ------------------------------------------------------------------ demo queries
@app.get("/api/queries")
def list_queries(_: dict = Depends(signed_in)) -> list[dict]:
    """The catalog of demo queries without their SQL bodies."""
    return [
        {"id": q["id"], "section": q["section"], "title": q["title"],
         "note": q.get("note"), "params": q.get("params", []),
         "param_labels": q.get("param_labels"), "hide_params": q.get("hide_params", False)}
        for q in catalog.QUERIES
    ]


@app.get("/api/queries/{query_id}")
def run_query(query_id: str, _: dict = Depends(signed_in), params: str | None = Query(default=None,
              description="Comma-separated overrides for the query parameters")) -> dict:
    """Run one demo query, optionally overriding its parameters."""
    entry = next((q for q in catalog.QUERIES if q["id"].lower() == query_id.lower()), None)
    if entry is None:
        raise HTTPException(404, f"No query {query_id}")

    bound = list(entry.get("params", []))
    if params:
        overrides = [p.strip() for p in params.split(",")]
        for i, value in enumerate(overrides):
            if i < len(bound):
                bound[i] = value
    try:
        rows = db.query(entry["sql"], tuple(bound))
    except Exception as exc:  # surface the MySQL message to the dashboard
        raise HTTPException(400, str(exc)) from exc
    return {
        "id": entry["id"], "title": entry["title"], "note": entry.get("note"),
        "sql": entry["sql"].strip(), "params": bound, "columns": list(rows[0].keys()) if rows else [],
        "rows": rows, "row_count": len(rows),
    }


# ------------------------------------------------------------------ rule tests
@app.get("/api/rules")
def list_rules(_: dict = Depends(signed_in)) -> list[dict]:
    return [
        {"id": t["id"], "section": t["section"], "title": t["title"], "expect": t["expect"]}
        for t in catalog.RULE_TESTS
    ]


@app.post("/api/rules/run")
def run_rules(_: dict = Depends(admin_only), ids: list[str] | None = None) -> dict:
    """Run rule tests inside a transaction that is always rolled back.

    A test passes when the statement is rejected (or, for a few, when it runs
    cleanly), matching the expectation documented in the SQL file.
    """
    selected = [t for t in catalog.RULE_TESTS if ids is None or t["id"] in ids]
    statements = [{"sql": t["sql"], "params": t.get("params", ())} for t in selected]
    results = db.sandbox(statements)

    out: list[dict] = []
    for test, result in zip(selected, results):
        rejected = not result["ok"]
        out.append({
            "id": test["id"], "section": test["section"], "title": test["title"],
            "expect": test["expect"],
            "rejected": rejected,
            "passed": rejected,
            "actual": result.get("error"),
            "errno": result.get("errno"),
            "sql": test["sql"],
        })
    return {"total": len(out), "passed": sum(1 for r in out if r["passed"]), "results": out}


# ------------------------------------------------------------------ cascade demos
@app.get("/api/cascades")
def list_cascades(_: dict = Depends(signed_in)) -> list[dict]:
    return [
        {"id": d["id"], "section": d["section"], "title": d["title"],
         "description": d["description"]}
        for d in catalog.CASCADE_DEMOS
    ]


@app.post("/api/cascades/{demo_id}/run")
def run_cascade(demo_id: str, _: dict = Depends(admin_only)) -> dict:
    """Show CASCADE / SET NULL by counting before and after a rolled-back delete."""
    demo = next((d for d in catalog.CASCADE_DEMOS if d["id"].lower() == demo_id.lower()), None)
    if demo is None:
        raise HTTPException(404, f"No cascade demo {demo_id}")
    results = db.sandbox([
        {"sql": demo["before_sql"]},
        {"sql": demo["delete_sql"]},
        {"sql": demo["after_sql"]},
    ])
    before, delete, after = results
    if not delete["ok"]:
        raise HTTPException(400, delete.get("error", "delete failed"))
    return {
        "id": demo["id"], "title": demo["title"], "description": demo["description"],
        "before": before["rows"], "after": after["rows"],
        "delete_rowcount": delete["rowcount"],
    }


# ------------------------------------------------------------------ alert + audit demos
@app.post("/api/alerts/run")
def run_alerts(_: dict = Depends(admin_only)) -> dict:
    """Run the budget-alert demo steps in order, inside a rolled-back transaction."""
    steps = catalog.ALERT_DEMO["steps"]
    statements = [{"sql": s["sql"]} for s in steps]
    # Only rows above this id belong to the demo; the app writes alerts too.
    baseline = db.scalar("SELECT COALESCE(MAX(alert_id), 0) FROM trip_alerts")
    statements.append({"sql": catalog.ALERT_DEMO["read_sql"], "params": (baseline,)})
    results = db.sandbox(statements)
    alerts = results[-1]["rows"]
    return {
        "title": catalog.ALERT_DEMO["title"],
        "description": catalog.ALERT_DEMO["description"],
        "steps": [{"label": s["label"], "expect": s["expect"], "ok": r["ok"]}
                  for s, r in zip(steps, results[:-1])],
        "alerts": alerts,
        "alert_count": len(alerts),
    }


@app.post("/api/audit/run")
def run_audit(_: dict = Depends(admin_only)) -> dict:
    """Run the audit-trail demo steps in order, inside a rolled-back transaction."""
    steps = catalog.AUDIT_DEMO["steps"]
    statements = [{"sql": s["sql"]} for s in steps]
    # Only rows above this id belong to the demo; the app writes audit rows too.
    baseline = db.scalar("SELECT COALESCE(MAX(audit_id), 0) FROM audit_log")
    statements.append({"sql": catalog.AUDIT_DEMO["read_sql"], "params": (baseline,)})
    results = db.sandbox(statements)
    log = results[-1]["rows"]
    return {
        "title": catalog.AUDIT_DEMO["title"],
        "description": catalog.AUDIT_DEMO["description"],
        "steps": [{"label": s["label"], "ok": r["ok"]} for s, r in zip(steps, results[:-1])],
        "log": log,
        "log_count": len(log),
    }


# ------------------------------------------------------------------ procedures
@app.post("/api/procedures/create-trip")
def create_trip(_: dict = Depends(admin_only), owner_id: int = Query(...), title: str = Query(...),
                start_date: str = Query(...), end_date: str = Query(...),
                budget: float = Query(...), keep: bool = Query(False)) -> dict:
    """Call sp_create_trip: trip + owner membership + one row per day, all-or-nothing.

    By default the trip is rolled back so the demo leaves no rows behind; pass
    keep=true to commit it.
    """
    result = db.call_procedure(
        "sp_create_trip",
        (owner_id, title, start_date, end_date, budget),
        ("new_trip",),
    )
    trip_id = (result.get("out") or {}).get("new_trip")
    detail = {
        "members": db.query("SELECT * FROM trip_members WHERE trip_id = %s", (trip_id,)),
        "days": db.query("SELECT * FROM itinerary_days WHERE trip_id = %s ORDER BY day_number",
                         (trip_id,)),
    }
    if not keep:
        db.execute("DELETE FROM trips WHERE trip_id = %s", (trip_id,))
        detail["rolled_back"] = True
    return {"procedure": "sp_create_trip", "new_trip_id": trip_id, "out": result.get("out"),
            **detail}


@app.post("/api/procedures/book-room")
def book_room(_: dict = Depends(admin_only), trip_id: int = Query(...), room_id: int = Query(...),
              booked_by: int = Query(...), check_in: str = Query(...),
              check_out: str = Query(...), guests: int = Query(2),
              keep: bool = Query(True)) -> dict:
    """Call sp_book_room: lock the room with FOR UPDATE, insert, set the code.

    The reservation is kept by default so that calling the endpoint a second
    time on overlapping dates shows the validation trigger rejecting it. Use
    /api/procedures/cleanup to remove demo rows afterwards.
    """
    try:
        result = db.call_procedure(
            "sp_book_room",
            (trip_id, room_id, booked_by, check_in, check_out, guests),
            ("res_id",),
        )
    except Exception as exc:
        raise HTTPException(400, str(exc)) from exc
    res_id = (result.get("out") or {}).get("res_id")
    summary = db.query("SELECT * FROM v_reservation_summary WHERE reservation_id = %s", (res_id,))
    if not keep:
        db.execute("DELETE FROM hotel_reservations WHERE reservation_id = %s", (res_id,))
    return {"procedure": "sp_book_room", "reservation_id": res_id, "out": result.get("out"),
            "summary": summary, "rolled_back": not keep}


@app.post("/api/procedures/cleanup")
def cleanup_demo_rows(_: dict = Depends(admin_only)) -> dict:
    """Remove rows created by the procedure demos.

    Demo trips are titled 'Demo: ...'; deleting them cascades to members, days,
    reservations and payments.
    """
    trips = db.query("SELECT trip_id, title FROM trips WHERE title LIKE 'Demo:%'")
    for trip in trips:
        db.execute("DELETE FROM trips WHERE trip_id = %s", (trip["trip_id"],))
    return {"deleted_trips": trips, "count": len(trips)}


# ------------------------------------------------------------------ recommendations
@app.get("/api/recommendations")
def recommendations(_: dict = Depends(signed_in), user_id: int = Query(2), month: int = Query(3),
                    limit: int = Query(5)) -> dict:
    """Score unvisited destinations for a user in a given month."""
    return recommender.recommend(user_id, month, limit)


# ------------------------------------------------------------------ dashboard
@app.get("/")
def dashboard() -> FileResponse:
    index = STATIC_DIR / "index.html"
    if not index.is_file():
        raise HTTPException(500, "static/index.html is missing")
    return FileResponse(index)


@app.get("/login")
def login_page() -> FileResponse:
    page = STATIC_DIR / "login.html"
    if not page.is_file():
        raise HTTPException(500, "static/login.html is missing")
    return FileResponse(page)


@app.get("/app")
def traveller_app() -> FileResponse:
    """The consumer-facing trip planner, as opposed to the DBMS dashboard."""
    page = STATIC_DIR / "app.html"
    if not page.is_file():
        raise HTTPException(500, "static/app.html is missing")
    return FileResponse(page)


@app.get("/api/bundle")
def download_bundle(_: dict = Depends(signed_in)) -> Response:
    """Serve a zip of the application files so they can be added to GitHub."""
    import io
    import zipfile

    files = [
        "app/__init__.py", "app/db.py", "app/auth.py", "app/catalog.py",
        "app/recommender.py", "app/travel.py", "app/main.py", "app/README.md",
        "static/index.html", "static/login.html", "static/app.html",
        "tests/test_api.py",
        "requirements.txt", "Dockerfile", "docker-compose.yml",
        ".env.example", ".gitignore",
    ]
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel in files:
            path = BASE_DIR / rel
            if path.is_file():
                zf.write(path, rel)
    buffer.seek(0)
    return Response(
        content=buffer.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": 'attachment; filename="travel-itinerary-app.zip"'},
    )
