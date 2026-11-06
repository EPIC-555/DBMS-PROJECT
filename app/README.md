# Application layer (`app/`) — deployment notes

The database scripts in the repository root are the project. This directory adds
a small FastAPI service and a web dashboard so the database can be shown without
MySQL Workbench.

## What the app exposes

| Route | What it shows |
|---|---|
| `/` | The dashboard (single page) |
| `/api/health` | Connection status and the acceptance counts (32/41/31/4) |
| `/api/overview` | Every table with an exact row count, plus views and procedures |
| `/api/triggers`, `/api/triggers/{name}` | The 31 triggers and their `CREATE TRIGGER` source |
| `/api/fks` | The 41 foreign keys with their ON DELETE / ON UPDATE rules |
| `/api/queries`, `/api/queries/{id}` | The 25 named demo queries (Q1-Q12, T1-T7, A1-A3, B1-B2) |
| `/api/rules`, `/api/rules/run` | The 25 rule tests, run in a rolled-back transaction |
| `/api/cascades/{id}/run` | CASCADE and SET NULL demos |
| `/api/alerts/run`, `/api/audit/run` | Budget alerts and the audit trail |
| `/api/procedures/create-trip`, `/api/procedures/book-room` | The two stored procedures |
| `/api/procedures/cleanup` | Remove demo rows left by the procedure demos |
| `/api/recommendations` | Destination scores for a user and month |

Interactive API docs are at `/docs`.

## The traveller app (`/app`)

The dashboard above inspects the schema. `/app` is the opposite side: a
consumer-style trip planner a normal traveller would use, built on the same
tables. It is served at `/app` and linked from the dashboard header.

| Route | What it does |
|---|---|
| `GET /api/travel/destinations`, `/destinations/{id}` | Browse places, with hotels, things to see and reviews |
| `GET /api/travel/hotels`, `/hotels/{id}` | Hotels with amenities and room types |
| `GET /api/travel/hotels/{id}/availability` | Rooms free for a date range and party size |
| `GET /api/travel/search?q=` | One box over destinations, hotels and places |
| `GET /api/travel/recommendations` | Personalised destination scores |
| `GET/POST /api/travel/trips` | List and create trips (`sp_create_trip`) |
| `GET /api/travel/trips/{id}` | Full itinerary: days, items, stays, expenses, costs |
| `POST /api/travel/bookings` | Reserve a room (`sp_book_room`) |
| `GET /api/travel/bookings`, `POST /bookings/{id}/cancel` | List and cancel stays |
| `POST /api/travel/expenses` | Log an expense, returning any budget alert |
| `POST /api/travel/reviews` | Rate a destination |
| `GET /api/travel/wishlist`, `POST /wishlist/{id}` | Saved destinations; the POST toggles |
| `GET /api/travel/profile` | The signed-in user's headline numbers |

Every write goes through the database's own rules rather than reimplementing
them, so the app and the schema cannot disagree:

* Room capacity, the trip date window, the "only an owner or editor may book"
  rule and double-booking are all enforced by `trg_res_validate_bi`. When one
  rejects a booking the trigger's message is returned as a 400 and shown to the
  user as-is.
* `sp_book_room` locks the room row `FOR UPDATE` and generates the confirmation
  code; `sp_create_trip` creates the trip, adds the owner as a member and writes
  one `itinerary_days` row per date.
* Logging an expense fires the budget triggers, which write `trip_alerts`; the
  API returns those alerts so the page can surface them immediately.

### Authentication

`/app` uses the same session and CSRF scheme as the dashboard. Reads need a
signed-in user; writes need a signed-in user plus the `X-CSRF-Token` header.
Sign-up is on the login page.

## Authentication

Every data route requires a signed-in user, and routes that write to the database
additionally require the `admin` role. Accounts come from the project's own
`users` table, so no schema change was needed.

| Route | Who can call it |
|---|---|
| `POST /api/auth/login`, `POST /api/auth/register` | anyone |
| `GET /api/auth/me`, `GET /api/auth/csrf` | signed-in |
| `POST /api/auth/logout` | signed-in, with CSRF |
| All `GET /api/...` data routes | any signed-in user |
| `POST /api/rules/run`, `/api/alerts/run`, `/api/audit/run`, `/api/cascades/{id}/run` | admin |
| `POST /api/procedures/*` (create-trip, book-room, cleanup) | admin |

How it works:

* The password is hashed with SHA2-256 and compared to `users.password_hash`
  using `hmac.compare_digest`, so the comparison is constant time.
* A successful login sets a `travel_session` cookie that is HMAC-signed and
  carries only the user id, name, e-mail, role and expiry. It is `HttpOnly` and
  `SameSite=Lax`, so page scripts cannot read it and other sites cannot send it.
* Failed logins are rate limited (5 attempts per e-mail and client per 5 minutes).
* Unknown accounts and wrong passwords return the same message, so the API does
  not reveal which e-mails exist.
* `APP_SECRET_KEY` must be set outside development; the app refuses to start with
  the built-in development key when `APP_ENV` is anything else.

### CSRF

Every unsafe method (`POST`) requires a double-submit token: the server sets a
readable `travel_csrf` cookie and the page echoes it in the `X-CSRF-Token` header.
A cross-site page can cause a request but cannot read the cookie, so it cannot
forge the header. A missing or wrong header returns 403. `GET /api/auth/csrf`
issues a token for a session that outlived its cookie.

### Sign-up

`POST /api/auth/register` creates an account and signs it in. The role is
hard-coded to `user` and is never read from the request, so nobody can register
themselves as an administrator. Duplicate e-mails are caught by the `uk_users_email`
UNIQUE index and returned as 409. E-mail shape and a minimum password length of 8
are validated before the insert.

The sample users and their demo passwords are in the project's seed data. The
dashboard offers one-click fill for the admin (`aarav.sharma@example.com`) and a
normal user (`priya.nair@example.com`), and the login page can also create a new
account.

**Not included:** password reset and MFA, and the seeded hashes are unsalted SHA2
demo values. A production system would store bcrypt or argon2 hashes.

## Run it

### Option A: Docker Compose (recommended)

Needs Docker Desktop (or Docker Engine) running. Nothing else.

```bash
cp .env.example .env
# put a real key in .env - compose refuses to start without one:
python -c "import secrets; print(secrets.token_urlsafe(48))"
# paste that value as APP_SECRET_KEY in .env, then:
docker compose up -d --build
# open http://localhost:8000 and sign in
```

Compose starts MySQL 8.4, loads `00_build_everything.sql` on first start, and
runs the API against it. The first start takes a few minutes while the image
builds and the schema loads.

If port 3306 or 8000 is already taken, set `DB_PORT` and `APP_PORT` in `.env` to
free ones (for example 3307 and 8001) and open the new `APP_PORT`.

### Option B: an existing MySQL server

Use this when you already have MySQL and do not want Docker.

```bash
mysql -h127.0.0.1 -uroot -p < 00_build_everything.sql   # build the schema once
cp .env.example .env                                    # then edit if needed
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The app reads `.env` automatically. If your MySQL already has the schema loaded,
skip the first line; loading it twice is safe but slow.

## Tests

`tests/test_api.py` runs against a live MySQL with the schema loaded:

```bash
pip install -r requirements.txt
pytest -q
```

Set `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD` and `DB_NAME` (or use a `.env`
file) first. The tests assert the counts, the documented query results, that all
25 rule tests are rejected, and that the demos leave no rows behind.

## Notes

* **Business rules stay in MySQL.** The API validates input and shapes JSON; the
  31 triggers, 41 foreign keys, CHECK constraints and both procedures do the
  enforcing.
* **Demos roll back.** The rule lab, the cascade demos, the alert and audit demos,
  and `sp_create_trip` all run inside a transaction that is rolled back, so
  running them never changes the data. `sp_book_room` keeps its reservation so a
  second call can show the trigger rejecting a double booking; use
  `/api/procedures/cleanup` afterwards.
* **The alert and audit demos read only their own rows.** Booking, cancelling or
  logging an expense through `/app` fires the same triggers that write
  `trip_alerts` and `audit_log`. Both demos therefore capture the highest id
  before they run and read only rows above it, so normal use of the app cannot
  change the numbers they report.
* **Script 07 is not in the repository.** `AGENTS.md` describes a recommendation
  layer, but `07_recommendation_engine.sql` was never committed, so the scoring
  model is implemented in `app/recommender.py` against the existing tables. The
  weights match the documentation; the exact scores will differ because the
  documented SQL does not exist here.
* **A public URL has no login.** The demo MySQL password is a placeholder. Add
  authentication before exposing this anywhere other than a course demo.
