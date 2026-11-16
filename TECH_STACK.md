# Technology Stack — Travel Itinerary and Expense Organizer (TripNest)

Every choice below is either required by the brief or was made to keep the project free, reproducible and easy to explain in a viva. Versions are the ones actually pinned in `requirements.txt` and the `Dockerfile`.

---

## 1. Summary

| Layer | Technology | Version | Required? |
|---|---|---|---|
| Database engine | MySQL Community Server | 8.4 LTS | Required |
| Storage engine | InnoDB | bundled with MySQL | Required |
| Character set | `utf8mb4` / `utf8mb4_0900_ai_ci` | — | Required |
| Data language | SQL (MySQL dialect) | — | Required |
| Modelling / client | MySQL Workbench | 8.0.x | Required |
| Application language | Python | 3.12 | Required for the web layer |
| Web framework | FastAPI | 0.115.6 | Required for the web layer |
| ASGI server | Uvicorn | 0.34.0 | Required for the web layer |
| Database driver | mysql-connector-python | 9.1.0 | Required for the web layer |
| Config loading | python-dotenv | 1.0.1 | Required for the web layer |
| Password hashing | bcrypt | 5.0.0 (cost 12) | Required for auth |
| Front end | HTML5, CSS3, vanilla JavaScript | — | Required for the web layer |
| Tests | pytest | 8.3.4 | Development |
| Test HTTP client | httpx | 0.28.1 | Development |
| Version control | Git, GitHub | — | Required |
| Containers | Docker, Docker Compose | — | Optional (recommended) |
| Hosting | Railway | — | Optional (live demo) |

---

## 2. Why each choice

### MySQL 8.4 LTS

The brief is a relational-database project, so the engine is the centre of the work rather than an implementation detail.

* **8.4 LTS, not 8.0.** MySQL 8.0 reached end of life in April 2026. 8.4 is the current long-term-support release.
* **CHECK constraints are enforced** from 8.0.16 onward. The schema uses 26 of them, so an older server would silently accept invalid rows.
* **Triggers with `SIGNAL SQLSTATE '45000'`** let a rule reject a row with a custom message, which is how the 31 triggers report failures.
* **Window functions** (`SUM() OVER (...)`) are used by Q9 for the running-total query.
* **`SELECT ... FOR UPDATE`** gives row-level locking inside `sp_book_room`, which is what makes double-booking impossible under concurrency.

### InnoDB

InnoDB is the only MySQL engine that provides all four things this schema depends on: foreign keys, transactions, row-level locking, and triggers that can be rolled back. MyISAM supports none of them, so the engine is not a free choice here.

### utf8mb4

Stores the full Unicode range, including the 4-byte characters (emoji, some scripts) that plain `utf8` silently rejects. Place and destination names are user data, so this matters.

### SQL — the rules live in the database

The design decision that shapes everything else: business rules are enforced by the schema, not by application code.

* Rules in the database apply to **every** client — Workbench, the dashboard, TripNest, or anything written later. Rules in Python apply only to the one program that remembers to check.
* The 41 foreign keys, 26 CHECK constraints, 19 UNIQUE keys, 31 triggers and 2 procedures are all declared once, in SQL.
* The web layer therefore does not re-implement them. When a trigger rejects a booking, the API passes the trigger's own message to the user. The app and the schema cannot disagree.

### Python 3.12

* The single most common language for course projects, and the one the team already knows.
* FastAPI and mysql-connector-python both support it fully.
* The `Dockerfile` pins `python:3.12-slim`, so the runtime matches local development.

### FastAPI 0.115.6 + Uvicorn 0.34.0

FastAPI was chosen over Flask or Streamlit for three concrete reasons:

* **Automatic interactive docs.** `/docs` renders every endpoint with a form to call it. This is useful in a viva — the API can be demonstrated without writing a client.
* **Typed request validation.** Request bodies are validated against the project's own rules before they reach MySQL, so a malformed request gets a clean 422 instead of a raw driver error.
* **Async-capable ASGI server.** Uvicorn serves the app and the static files from one process, so the demo needs one port, not two.

Streamlit was the original plan for the "stretch" phase but was set aside: it re-renders a page per interaction, which makes a multi-step booking flow awkward, and it offers no clean way to expose the REST API the dashboard needs.

### mysql-connector-python 9.1.0

The official Oracle driver. Chosen over `PyMySQL` for its first-class support of stored procedures with multiple result sets (`sp_create_trip`, `sp_book_room`) and its handling of `DECIMAL` values, which matter for money.

A small connection pool (`DB_POOL_SIZE`, default 8) is kept in `app/db.py`. Opening a fresh TCP connection and TLS handshake per request would dominate response time against a remote MySQL.

### bcrypt 5.0.0, cost 12

The seed data stores legacy `SHA2(password, 256)` digests, which is fine for demo data but wrong for real ones: SHA-256 is fast and unsalted, so a leaked table falls to a rainbow table or a GPU brute force.

bcrypt is deliberately slow and salts each password individually, so the same password yields a different hash every time and each guess is expensive. Cost 12 is the current common default — roughly 250 ms per hash on modern hardware, slow enough to make bulk guessing impractical but fast enough that a sign-in still feels instant.

The migration path is transparent: on the first successful sign-in of a legacy account, the app verifies the old digest once and rewrites the row as bcrypt. Nothing is logged. Passwords over 72 bytes are rejected rather than silently truncated, because bcrypt only reads the first 72.

### Plain HTML, CSS and vanilla JavaScript

No React, Vue or build step, deliberately.

* The pages are served straight from `static/` by FastAPI. There is nothing to compile, so a clone runs immediately and the `Dockerfile` needs no Node stage.
* The `Dockerfile` copies only `app/` and `static/`. Adding a bundler would mean a second build stage and a `node_modules` directory for three pages.
* For a database course, the interesting part is the schema. A framework would add a lot of code that has nothing to do with the subject.

The two effect layers (`static/snow.js`, `static/fx.js`) are self-injecting: each adds its own `<style>` element and needs one `<script>` tag per page. Both are dependency-free and guard against `prefers-reduced-motion`.

### pytest 8.3.4 + httpx 0.28.1

86 tests run against a **live MySQL with the schema loaded** — not mocks. That is deliberate: the entire point of the project is that the database enforces its own rules, and a mocked database would prove nothing about that. The suite asserts the acceptance counts, the documented query results, that all 25 rule tests are rejected, that writes require CSRF and the right role, and that the demos leave no rows behind.

`httpx` provides the in-process HTTP client FastAPI's `TestClient` is built on.

### Docker and Docker Compose

Optional, but it removes the most common failure in this project: a team member whose MySQL is a different version, is not running, or has the schema half-loaded.

```bash
docker compose up -d --build
```

starts MySQL 8.4, loads `00_build_everything.sql` on first start, and runs the API against it. The schema is mounted read-only from the repository, so the container is disposable — delete the volume and the next start rebuilds from scratch.

### Railway

Hosts the live demo. It builds from the repository's `Dockerfile`, so the deployed artifact is the same image that runs locally. Free tier is sufficient for a course demo.

### Git and GitHub

Required by the brief. One branch per member, merged by pull request, with `main` kept deployable.

---

## 3. What was deliberately not used

| Rejected | Why |
|---|---|
| MyISAM | No foreign keys, transactions, row locking or rollback-able triggers — the schema depends on all four |
| MongoDB / any NoSQL store | The project is an ER-model exercise; the value is in keys, normalisation and referential integrity |
| SQLite | No stored procedures, no `SIGNAL`, limited trigger support — the schema would not load |
| Streamlit | Re-renders per interaction; awkward for multi-step flows; no REST API for the dashboard |
| React / Vue / a bundler | Adds a build step and a toolchain for three pages; the interesting work is in the schema |
| An ORM (SQLAlchemy, Django ORM) | The project's rules live in triggers and procedures, which an ORM would hide rather than exercise |
| Redis / a job queue | No background work; sessions are stateless signed cookies |
| JWT in `localStorage` | Readable by page scripts, so an XSS bug leaks the token. The session is an `HttpOnly` cookie instead |
| `SHA2` for new passwords | Fast and unsalted; kept only for legacy demo rows, upgraded to bcrypt on first sign-in |

---

## 4. Environment variables

All are read from `.env` (loaded by python-dotenv) or the process environment. See `.env.example`.

| Variable | Default | Purpose |
|---|---|---|
| `DB_HOST` | `127.0.0.1` | MySQL host |
| `DB_PORT` | `3306` | MySQL port |
| `DB_USER` | `root` | MySQL user |
| `DB_PASSWORD` | `rootpw` | MySQL password (placeholder — change for anything public) |
| `DB_NAME` | `travel_itinerary_db` | Schema name |
| `DB_POOL_SIZE` | `8` | Connections kept in the pool |
| `APP_PORT` | `12000` | Port Uvicorn listens on |
| `APP_SECRET_KEY` | — | **Required outside development.** HMAC key for session and CSRF tokens |
| `APP_ENV` | `development` | Any other value makes a default secret a fatal error |
| `SESSION_TTL_SECONDS` | `28800` | Idle session lifetime (8 hours) |
| `SESSION_REFRESH_AFTER_SECONDS` | — | How often the cookie is re-issued |
| `SESSION_ABSOLUTE_SECONDS` | — | Hard cap on session age regardless of activity |
| `COOKIE_SECURE` | `false` | Set `true` when served over HTTPS so the cookie is TLS-only |

`APP_SECRET_KEY` is the one that must never be guessed. A known key lets anyone forge a valid session cookie and sign in as any user, including an administrator. The app refuses to start with the built-in development key when `APP_ENV` is not `development`.

---

## 5. Runtime shape

```
Browser
   |  HTTPS
   v
Uvicorn (one process)
   |
   +-- FastAPI
   |     +-- /            -> static/index.html   (dashboard)
   |     +-- /app         -> static/app.html     (TripNest)
   |     +-- /login       -> static/login.html
   |     +-- /static/*    -> StaticFiles mount
   |     +-- /api/auth/*  -> app/auth.py
   |     +-- /api/travel/*-> app/travel.py -> app/catalog.py, app/recommender.py
   |     +-- /api/*       -> app/main.py (schema inspection)
   |
   +-- mysql-connector-python (pool of 8)
         |
         v
      MySQL 8.4 (InnoDB)
         32 tables, 41 FKs, 31 triggers, 4 views, 2 procedures
```

Every request that writes goes through the same path: FastAPI validates the shape, then MySQL validates the rule. There is no layer in between that could disagree with the database.
