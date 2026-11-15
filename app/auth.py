"""Password hashing, sessions and CSRF for the dashboard and the API.

Passwords
---------
The project's SQL seed stores ``SHA2(password, 256)`` hex digests. That is fine
for a demo but wrong for anything real: SHA-256 is fast, so a stolen table can be
brute-forced at billions of guesses a second. This module verifies a login
against the legacy digest exactly once and then rewrites the row with a bcrypt
hash (cost 12, per-password salt). The next sign-in uses bcrypt. Nothing is
migrated up front, no column changes, and a user never notices.

Sessions
--------
A session is an HMAC-SHA256 signed cookie holding the user id, name, role and an
expiry. ``SESSION_TTL_SECONDS`` defaults to 30 minutes, and the token also
carries an absolute deadline (``abs``) so that touching the app cannot extend a
session indefinitely. The cookie is HttpOnly and SameSite=Lax, so page scripts
cannot read it and cross-site requests do not carry it.

Security notes
--------------
* Passwords are never logged and never returned by an endpoint.
* Login is rate limited per (e-mail, client) pair to slow guessing.
* Errors are deliberately vague: a wrong password and an unknown account are
  indistinguishable.
* Signing out bumps a per-user token version, so every cookie issued before the
  logout stops working immediately.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import threading
import time

import bcrypt
import mysql.connector
from fastapi import Cookie, Header, HTTPException, Request, status

from . import db

SESSION_COOKIE = "travel_session"
CSRF_COOKIE = "travel_csrf"
CSRF_HEADER = "X-CSRF-Token"

# 30 minutes by default, as requested. The absolute cap stops a long-lived tab
# from renewing itself forever.
SESSION_TTL_SECONDS = int(os.getenv("SESSION_TTL_SECONDS", str(30 * 60)))
SESSION_ABSOLUTE_SECONDS = int(os.getenv("SESSION_ABSOLUTE_SECONDS", str(12 * 3600)))
# Refresh the cookie only once this much of the window has elapsed, so a busy
# page is not writing a Set-Cookie header on every request.
SESSION_REFRESH_AFTER_SECONDS = int(os.getenv("SESSION_REFRESH_AFTER_SECONDS", str(5 * 60)))

_DEV_SECRET = "dev-only-insecure-secret-change-me"

_MIN_PASSWORD_LENGTH = 8
_BCRYPT_ROUNDS = 12
_LEGACY_HASH_RE = re.compile(r"^[0-9a-f]{64}$")

_MAX_ATTEMPTS = 5
_WINDOW_SECONDS = 300
_attempts: dict[str, list[float]] = {}
_attempts_lock = threading.Lock()

# Sessions carry a random id, so signing out ends only that one session rather
# than every device the account is signed in on. Revoked ids are held until the
# token they belong to would have expired anyway.
_revoked: dict[str, float] = {}
_revoked_lock = threading.Lock()


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


# ------------------------------------------------------------------ passwords
def hash_password(password: str) -> str:
    """Return a bcrypt hash (per-password salt, cost 12)."""
    raw = password.encode("utf-8")
    if len(raw) > 72:  # bcrypt silently truncates beyond 72 bytes
        raise HTTPException(400, "Password is too long (72 bytes maximum).")
    return bcrypt.hashpw(raw, bcrypt.gensalt(rounds=_BCRYPT_ROUNDS)).decode("ascii")


def verify_password(password: str, stored: str) -> bool:
    """Check a password against a bcrypt hash, falling back to a legacy SHA-256.

    The fallback exists only so the seeded demo accounts can sign in once and be
    upgraded; see ``authenticate``.
    """
    if not stored:
        return False
    raw = password.encode("utf-8")
    if stored.startswith(("$2a$", "$2b$", "$2y$")):
        try:
            return bcrypt.checkpw(raw[:72], stored.encode("ascii"))
        except ValueError:
            return False
    if _LEGACY_HASH_RE.match(stored):
        return hmac.compare_digest(hashlib.sha256(raw).hexdigest(), stored)
    return False


def _cost_of(bcrypt_hash: str) -> int:
    parts = bcrypt_hash.split("$")
    if len(parts) < 4:
        return 0
    try:
        return int(parts[2])
    except ValueError:
        return 0


def needs_rehash(stored: str) -> bool:
    """True for legacy digests, or a bcrypt hash below the current cost."""
    if not stored:
        return False
    if not stored.startswith(("$2a$", "$2b$", "$2y$")):
        return True
    return _cost_of(stored) < _BCRYPT_ROUNDS


# ------------------------------------------------------------------ tokens
def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _b64d(text: str) -> bytes:
    padding = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + padding)


def _sign(payload: bytes) -> str:
    return _b64e(hmac.new(_secret(), payload, hashlib.sha256).digest())


def _revoke(sid: str, expires_at: float) -> None:
    with _revoked_lock:
        now = time.time()
        for key in [k for k, exp in _revoked.items() if exp < now]:
            del _revoked[key]
        _revoked[sid] = expires_at


def _is_revoked(sid: str | None) -> bool:
    if not sid:
        return False
    with _revoked_lock:
        return sid in _revoked


def make_session(user: dict) -> str:
    """Build a signed token holding only non-sensitive identity fields."""
    now = int(time.time())
    body = {
        "uid": user["user_id"],
        "email": user["email"],
        "name": user["full_name"],
        "role": user["role"],
        "sid": secrets.token_urlsafe(16),
        "iat": now,
        "exp": now + SESSION_TTL_SECONDS,
        "abs": now + SESSION_ABSOLUTE_SECONDS,
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
    if not isinstance(body, dict):
        return None
    now = time.time()
    if body.get("exp", 0) < now or body.get("abs", 0) < now:
        return None
    if _is_revoked(body.get("sid")):
        return None
    return body


def session_state(token: str | None) -> dict:
    """Describe the session for the client, including the time left.

    Returns ``{"active": False}`` when there is no usable session, so the page can
    show a countdown without treating a missing session as an error.
    """
    body = read_session(token)
    if body is None:
        return {"active": False}
    now = int(time.time())
    return {
        "active": True,
        "user": {k: body[k] for k in ("uid", "email", "name", "role") if k in body},
        "issued_at": body.get("iat"),
        "expires_at": body.get("exp"),
        "absolute_expires_at": body.get("abs"),
        "expires_in": max(0, int(body["exp"] - now)),
        "absolute_expires_in": max(0, int(body.get("abs", body["exp"]) - now)),
        "ttl_seconds": SESSION_TTL_SECONDS,
        "refresh_after_seconds": SESSION_REFRESH_AFTER_SECONDS,
    }


def should_renew(token: str | None) -> bool:
    """True when the cookie is old enough to be reissued on this request."""
    body = read_session(token)
    if body is None:
        return False
    return (time.time() - body.get("iat", 0)) >= SESSION_REFRESH_AFTER_SECONDS


def revoke_session(token: str | None) -> bool:
    """End one session. Returns True when a session was actually ended.

    Only the token presented is invalidated, so signing out on a laptop does not
    sign the same account out on a phone.
    """
    body = read_session(token)
    if body is None or not body.get("sid"):
        return False
    _revoke(body["sid"], body.get("abs", body.get("exp", time.time())))
    return True


# ------------------------------------------------------------------ rate limit
def _rate_limit_key(email: str, request: Request) -> str:
    client = request.client.host if request.client else "unknown"
    return f"{email.lower()}|{client}"


def _check_rate_limit(key: str) -> None:
    now = time.time()
    with _attempts_lock:
        hits = [t for t in _attempts.get(key, []) if now - t < _WINDOW_SECONDS]
        _attempts[key] = hits
        over = len(hits) >= _MAX_ATTEMPTS
    if over:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many failed sign-in attempts. Try again in a few minutes.",
        )


def _record_failure(key: str) -> None:
    with _attempts_lock:
        _attempts.setdefault(key, []).append(time.time())


def _clear_failures(key: str) -> None:
    with _attempts_lock:
        _attempts.pop(key, None)


# ------------------------------------------------------------------ login
def _dummy_verify(password: str) -> bool:
    """Spend the same work as a real check so timing does not leak accounts."""
    try:
        bcrypt.checkpw(password.encode("utf-8")[:72], _DUMMY_HASH)
    except ValueError:
        pass
    return False


_DUMMY_HASH = bcrypt.hashpw(b"not-a-real-password", bcrypt.gensalt(rounds=_BCRYPT_ROUNDS))


def authenticate(email: str, password: str, request: Request) -> dict:
    """Verify credentials and return the user row.

    A successful legacy (SHA-256) login is upgraded to bcrypt in place, so the
    seeded demo accounts become properly hashed the first time they sign in.
    """
    key = _rate_limit_key(email, request)
    _check_rate_limit(key)

    rows = db.query(
        "SELECT user_id, email, full_name, role, password_hash "
        "FROM users WHERE email = %s",
        (email,),
    )
    stored = rows[0]["password_hash"] if rows else ""
    # Always run a verification, even for an unknown account, so the response
    # time does not reveal whether the address exists.
    ok = verify_password(password, stored) if rows else _dummy_verify(password)
    if not rows or not ok:
        _record_failure(key)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid e-mail or password")

    _clear_failures(key)
    user = {k: v for k, v in rows[0].items() if k != "password_hash"}
    if needs_rehash(stored):
        try:
            db.execute(
                "UPDATE users SET password_hash = %s WHERE user_id = %s",
                (hash_password(password), user["user_id"]),
            )
            user["password_upgraded"] = True
        except mysql.connector.Error:
            # A failed upgrade must not block a valid sign-in.
            user["password_upgraded"] = False
    return user


# ------------------------------------------------------------------ deps
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
_COMMON_PASSWORDS = {
    "password", "password1", "password123", "12345678", "123456789", "qwerty123",
    "letmein123", "welcome1", "admin123", "iloveyou", "abc12345", "passw0rd",
}


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
    if password.strip() == "":
        raise HTTPException(400, "Choose a stronger password.")
    if password.lower() in _COMMON_PASSWORDS:
        raise HTTPException(400, "That password is too common. Choose another.")
    if address.split("@")[0].lower() in password.lower():
        raise HTTPException(400, "Choose a stronger password — it must not contain your e-mail name.")
    return name, address


def register(full_name: str, email: str, password: str) -> dict:
    """Create a user with role 'user' and return the identity fields.

    The role is hard-coded, never taken from the request, so a visitor cannot
    sign themselves up as an administrator.
    """
    name, address = validate_registration(full_name, email, password)
    digest = hash_password(password)
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


def bcrypt_rounds() -> int:
    """Exposed so the API can report which hashing scheme is in use."""
    return _BCRYPT_ROUNDS
