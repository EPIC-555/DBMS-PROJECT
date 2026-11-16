# Deployment — Travel Itinerary and Expense Organizer (TripNest)

How the live site is built, and the one mistake that has repeatedly broken it.

**Live:** <https://dbms-project-production-0729.up.railway.app>

---

## 1. The rule that matters most

The `Dockerfile` copies **`app/` and `static/` only**:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
COPY static ./static
ENV APP_PORT=8000
EXPOSE 8000
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${APP_PORT}"]
```

Everything else in the repository — the SQL scripts, the PDFs, `docker-compose.yml`, and **anything committed at the repository root** — is not part of the image.

**The front end must live in `static/`.** Files named `index.html`, `app.html`, `login.html` or `fx.js` sitting at the repository root are never served. They are inert.

### How to check

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://<your-host>/static/fx.js
```

`200` means the file is deployed. `404` means it is not in `static/` — no matter what the commit history says.

### What this looks like when it goes wrong

| Symptom | Cause |
|---|---|
| Site loads but a new effect or style is missing | File was committed to the repo root instead of `static/` |
| `/static/<file>` returns 404 | File is not in `static/` |
| A commit "landed" but nothing changed | Commit only touched root-level files the image ignores |
| Live content is older than `main` | Latest `static/` change has not been deployed yet |

---

## 2. Deploying

Railway builds from the repository's `Dockerfile` on every push to `main`. There is no separate build step and no `railway.json` or `nixpacks.toml` in this repository — the `Dockerfile` is the whole configuration.

### Steps

1. **Put front-end files in `static/`.** Use GitHub's web UI or `git add static/<file>`.
2. **Commit and push to `main`.**
3. **Wait for the build.** The first build takes a few minutes; later ones are faster.
4. **Verify by URL, not by commit SHA.** See §3.

### Required environment variables on the host

Set these in the Railway dashboard (or the equivalent for another host). See `.env.example`.

| Variable | Notes |
|---|---|
| `APP_SECRET_KEY` | **Required.** Generate with `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `APP_ENV` | Set to anything other than `development` in production |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | Point at the MySQL instance |
| `COOKIE_SECURE` | `true` when served over HTTPS |
| `APP_PORT` | Railway usually injects its own port; the app reads this if set |

The app **refuses to start** with the built-in development secret when `APP_ENV` is not `development`. That is intentional: a known key would let anyone forge a session cookie and sign in as any user.

---

## 3. Verifying a deploy

Do not trust the commit SHA alone. A commit can be on `main` and still change nothing that the container uses. Check the actual served bytes.

### Does the file exist?

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://<host>/static/fx.js
```

### Is the live file the same as the one in the repo?

```bash
# checksum of what the server sends
curl -s https://<host>/static/index.html | sha256sum

# checksum of what is committed
git show origin/main:static/index.html | sha256sum
```

If the two hashes match, the deploy is current for that file. If they differ, the deploy is stale **or** the change was committed somewhere the image does not copy.

### Are the pages actually using the file?

```bash
curl -s https://<host>/ | grep -o "fx.js[^\"]*"
```

An empty result means the page does not reference the script, so the effect will never run even if the file is present.

### Full check

```bash
HOST=https://<host>
for f in index.html app.html login.html snow.js fx.js; do
  printf "%-12s %s\n" "$f" "$(curl -s -o /dev/null -w '%{http_code}' "$HOST/static/$f")"
done
```

Every line should read `200`.

---

## 4. Local run

### Docker Compose (closest to production)

```bash
cp .env.example .env
python -c "import secrets; print(secrets.token_urlsafe(48))"   # paste as APP_SECRET_KEY
docker compose up -d --build
# http://localhost:8000
```

Compose starts MySQL 8.4, loads `00_build_everything.sql` on first start, and runs the API against it. The schema is mounted read-only from the repository, so the database container is disposable.

### Against an existing MySQL

```bash
mysql -h127.0.0.1 -uroot -p < 00_build_everything.sql
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Build the image alone

```bash
docker build -t tripnest .
docker run --rm -p 8000:8000 --env-file .env tripnest
```

To confirm the image contains what you expect:

```bash
docker run --rm tripnest ls -la /app/static
```

Anything missing from that listing will 404 in production.

---

## 5. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `/static/<file>` 404 | File is not in `static/` | Move it into `static/` and push |
| New effect missing, file exists | Page does not reference it | Add the `<script>` tag to the page in `static/` |
| Commit pushed, site unchanged | Commit only touched root-level files | Commit the same change under `static/` |
| App fails to start | `APP_SECRET_KEY` missing or left at the default | Set a real key and set `APP_ENV` |
| "Sign in to continue" on `/api/health` | Endpoint requires a session | Expected; sign in first, or check `/` |
| Build succeeds, schema missing | MySQL not reachable or not seeded | Check the DB variables; load `00_build_everything.sql` |
| Stale content after a correct push | Build still running or cache | Wait for the build, then re-check the checksum in §3 |
| Old asset still served | Browser or CDN cache | The scripts are versioned (`fx.js?v=1`, `snow.js?v=5`) — bump the query string |

---

## 6. Notes

* **`static/` is publicly served.** Anything placed there — including `.zip` and `.patch` files — can be downloaded by anyone. Keep build artifacts out of `static/`.
* **One process serves everything.** Uvicorn serves the API and the static files, so there is no separate web server and no CORS configuration.
* **The demo MySQL password is a placeholder.** Do not expose the database publicly with the default credentials.
* **Session cookies are `HttpOnly` and `SameSite=Lax`.** Set `COOKIE_SECURE=true` in production so they are TLS-only.
