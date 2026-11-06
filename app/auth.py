"""Session authentication for the dashboard and API.

The users table stores SHA2-256 password hashes (demo values only). Login
verifies a submitted password against that hash in constant time, then issues a
signed session cookie. No new tables or columns are added, so the database
schema from the project's own SQL files is untouched.

Security notes:
* Passwords are never logged and never returned by any endpoint.
* The session cookie is HMAC-signed, HttpOnly and SameSite=Lax, so it cannot be
  read by page scripts or sent on cross-site requests.
* Failed logins are rate limited per e-mail and per client to slow guessing.
* Errors are deliberately vague: the caller cannot tell a wrong password from an
  unknown account.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import time
from typing import Any

import mysql.connector
from fastapi import Cookie, Header, HTTPException, Request, status

from . import db

SESSION_COOKIE = "travel_session"
CSRF_COOKIE = "travel_csrf"
CSRF_HEADER = "X-CSRF-Token"
SESSION_TTL_SECONDS = int(os.getenv("SESSION_TTL_SECONDS", str(8 * 3600)))
_DEV_SECRET = "dev-only-insecure-secret-change-me"

_MIN_PASSWORD_LENGTH = 8

_MAX_ATTEMPTS = 5
_WINDOW_SECONDS = 300
_attempts: dict[str, list[float]] = {}


def _secret() -> bytes:
    """Signing key. Set APP_SECRET_KEY in any real deployment."""
    value = os.getenv("APP_SECRET_KEY", "").strip()
    if not value or value == _DEV_SECRET:
        # Fail closed: a known key would let anyone forge a session cookie.
        if os.getenv("APP_ENV", "development").lower() != "development":
            raise RuntimeError(
                "APP_SECRET_KEY must be set to a long random value when "
                "APP_ENV is not 'development'. Generate one with: "
                'python -c "import secrets; print(secrets.token_urlsafe(48))"'
            )
        return _DEV_SECRET.encode("utf-8")
    return value.encode("utf-8")


def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _b64d(text: str) -> bytes:
    padding = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + padding)


def _sign(payload: bytes) -> str:
    return _b64e(hmac.new(_secret(), payload, hashlib.sha256).digest())


def make_session(user: dict) -> str:
    """Build a signed token holding only non-sensitive identity fields."""
    body = {
        "uid": user["user_id"],
        "email": user["email"],
        "name": user["full_name"],
        "role": user["role"],
        "exp": int(time.time()) + SESSION_TTL_SECONDS,
    }
    payload = _b64e(json.dumps(body, separators=(",", ":")).encode("utf-8"))
    return f"{payload}.{_sign(payload.encode('ascii'))}"


def read_session(token: str | None) -> dict | None:
    """Return the session body if the token is authentic and unexpired."""
    if not token or "." not in token:
        return None
    payload, signature = token.rsplit(".", 1)
    if not hmac.compare_digest(_sign(payload.encode("ascii")), signature):
        return None
    try:
        body = json.loads(_b64d(payload))
    except (ValueError, json.JSONDecodeError):
        return None
    if not isinstance(body, dict) or body.get("exp", 0) < time.time():
        return None
    return body


def _rate_limit_key(email: str, request: Request) -> str:
    client = request.client.host if request.client else "unknown"
    return f"{email.lower()}|{client}"


def _check_rate_limit(key: str) -> None:
    now = time.time()
    hits = [t for t in _attempts.get(key, []) if now - t < _WINDOW_SECONDS]
    _attempts[key] = hits
    if len(hits) >= _MAX_ATTEMPTS:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many failed sign-in attempts. Try again in a few minutes.",
        )


def _record_failure(key: str) -> None:
    _attempts.setdefault(key, []).append(time.time())


def authenticate(email: str, password: str, request: Request) -> dict:
    """Verify credentials against the users table and return the user row."""
    key = _rate_limit_key(email, request)
    _check_rate_limit(key)

    rows = db.query(
        "SELECT user_id, email, full_name, role, password_hash "
        "FROM users WHERE email = %s",
        (email,),
    )
    supplied = hashlib.sha256(password.encode("utf-8")).hexdigest()
    stored = rows[0]["password_hash"] if rows else ""
    # Always compare, even for an unknown account, so timing does not leak.
    if not hmac.compare_digest(supplied, stored or "0" * 64):
        _record_failure(key)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid e-mail or password")

    _attempts.pop(key, None)
    return {k: v for k, v in rows[0].items() if k != "password_hash"}


def current_user(token: str | None = Cookie(default=None, alias=SESSION_COOKIE)) -> dict:
    """FastAPI dependency: require any signed-in user."""
    session = read_session(token)
    if session is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sign in to continue")
    return session


def issue_csrf_token() -> str:
    """A random double-submit token, stored in a readable cookie.

    The same value is echoed by the page in the X-CSRF-Token header. A cross-site
    attacker can send the cookie (SameSite=Lax mostly prevents that) but cannot
    read it, so it cannot set the header.
    """
    return secrets.token_urlsafe(32)


def verify_csrf(
    csrf_cookie: str | None = Cookie(default=None, alias=CSRF_COOKIE),
    csrf_header: str | None = Header(default=None, alias=CSRF_HEADER),
) -> None:
    """FastAPI dependency for unsafe methods: the header must match the cookie."""
    if not csrf_cookie or not csrf_header or not hmac.compare_digest(csrf_cookie, csrf_header):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Missing or invalid CSRF token. Reload the page and try again.",
        )


_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$")


def validate_registration(full_name: str, email: str, password: str) -> tuple[str, str]:
    """Check a sign-up request and return the cleaned (full_name, email).

    Only shape and strength are checked here; the UNIQUE index on users.email is
    the real guard against duplicates, and it is enforced inside register().
    """
    name = " ".join(full_name.split())
    if len(name) < 2 or len(name) > 80:
        raise HTTPException(400, "Enter a name between 2 and 80 characters.")
    address = email.strip().lower()
    if not _EMAIL_RE.match(address) or len(address) > 100:
        raise HTTPException(400, "Enter a valid e-mail address.")
    if len(password) < _MIN_PASSWORD_LENGTH or len(password) > 200:
        raise HTTPException(400, f"Choose a password of at least {_MIN_PASSWORD_LENGTH} characters.")
    if password.strip() == "" or address.split("@")[0].lower() in password.lower():
        raise HTTPException(400, "Choose a stronger password.")
    return name, address


def register(full_name: str, email: str, password: str) -> dict:
    """Create a user with role 'user' and return the identity fields.

    The role is hard-coded, never taken from the request, so a visitor cannot
    sign themselves up as an administrator.
    """
    name, address = validate_registration(full_name, email, password)
    digest = hashlib.sha256(password.encode("utf-8")).hexdigest()
    try:
        user_id = db.insert(
            "INSERT INTO users (email, password_hash, full_name, role) VALUES (%s, %s, %s, 'user')",
            (address, digest, name),
        )
    except mysql.connector.IntegrityError:
        raise HTTPException(status.HTTP_409_CONFLICT, "That e-mail is already registered.")
    return {"user_id": user_id, "email": address, "full_name": name, "role": "user"}


def admin_dependency(user: dict) -> dict:
    """Raise 403 unless the session role is admin."""
    if user.get("role") != "admin":
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "This action changes data and requires an administrator account.",
        )
    return user
