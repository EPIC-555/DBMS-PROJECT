"""What a given user may and may not do, worked out from the database.

The dashboard and the travel app both need to answer "what is available to me?".
Rather than let each page guess and then show a raw database error, this module
builds one matrix that mirrors what the triggers actually enforce:

* A trip member's ``role`` decides what they can do with that trip. Only
  ``owner`` and ``editor`` may book a room or a transport leg — that is the exact
  rule in ``trg_res_validate_bi`` and ``trg_transport_validate_bi``.
* The account ``role`` decides the schema-wide demo actions. Anything that writes
  is administrator-only.

Every entry carries ``allowed`` plus a ``reason`` phrased for the person reading
it, so the UI can show a tick or a greyed-out row with an explanation instead of
a failure message after the fact.
"""

from __future__ import annotations

from . import db

# ---------------------------------------------------------------- trip actions
# Ordered so the UI can render them as a consistent table.
TRIP_ACTIONS: list[dict] = [
    {"key": "view", "label": "View trip, itinerary and costs",
     "roles": {"owner", "editor", "viewer"}},
    {"key": "edit_itinerary", "label": "Add and edit itinerary items",
     "roles": {"owner", "editor"}},
    {"key": "book_room", "label": "Book a hotel room",
     "roles": {"owner", "editor"}},
    {"key": "book_transport", "label": "Book flights, trains or cabs",
     "roles": {"owner", "editor"}},
    {"key": "cancel_booking", "label": "Cancel a booking you made",
     "roles": {"owner", "editor"}},
    {"key": "add_expense", "label": "Log an expense",
     "roles": {"owner", "editor", "viewer"}},
    {"key": "manage_members", "label": "Add or remove trip members",
     "roles": {"owner"}},
    {"key": "delete_trip", "label": "Delete the trip",
     "roles": {"owner"}},
]

_ROLE_RANK = {"viewer": 0, "editor": 1, "owner": 2}

ROLE_BLURB = {
    "owner": "full control of this trip",
    "editor": "can plan and book, but cannot change the member list",
    "viewer": "read-only: can follow the trip and log expenses, but not book",
}


def _article(word: str) -> str:
    """'a viewer', 'an editor', 'an owner' — reads properly in the UI."""
    return "an " + word if word[:1].lower() in "aeiou" else "a " + word


# ------------------------------------------------------------- global actions
GLOBAL_ACTIONS: list[dict] = [
    {"key": "browse_destinations", "label": "Browse destinations, hotels and rooms",
     "admin_only": False, "writes": False},
    {"key": "search", "label": "Search destinations, hotels and places",
     "admin_only": False, "writes": False},
    {"key": "create_trip", "label": "Create your own trips",
     "admin_only": False, "writes": True},
    {"key": "view_schema", "label": "Read the schema: tables, triggers, foreign keys",
     "admin_only": False, "writes": False},
    {"key": "run_demo_queries", "label": "Run the read-only demo queries",
     "admin_only": False, "writes": False},
    {"key": "run_rule_tests", "label": "Run the rule tests (rolled back)",
     "admin_only": True, "writes": True},
    {"key": "run_cascade_demos", "label": "Run the CASCADE / SET NULL demos",
     "admin_only": True, "writes": True},
    {"key": "run_alert_demo", "label": "Run the budget-alert demo",
     "admin_only": True, "writes": True},
    {"key": "run_audit_demo", "label": "Run the audit-trail demo",
     "admin_only": True, "writes": True},
    {"key": "call_procedures", "label": "Call sp_create_trip and sp_book_room",
     "admin_only": True, "writes": True},
    {"key": "cleanup_demo_rows", "label": "Delete rows left by the procedure demos",
     "admin_only": True, "writes": True},
    {"key": "download_bundle", "label": "Download the application bundle",
     "admin_only": False, "writes": False},
]


def _trip_capabilities(my_role: str | None, account_role: str) -> dict[str, dict]:
    """Per-action verdict for one trip."""
    out: dict[str, dict] = {}
    is_admin = account_role == "admin"
    for action in TRIP_ACTIONS:
        allowed = is_admin or (my_role in action["roles"])
        if allowed:
            reason = (
                "You are an administrator." if is_admin and my_role not in action["roles"]
                else f"You are the {my_role} of this trip."
                if my_role
                else "You are an administrator."
            )
        elif my_role is None:
            reason = "You are not a member of this trip."
        else:
            needed = " or ".join(
                sorted(action["roles"], key=lambda r: _ROLE_RANK.get(r, 0), reverse=True)
            )
            reason = f"Requires the {needed} role; you are {_article(my_role)}."
        out[action["key"]] = {"allowed": allowed, "reason": reason, "label": action["label"]}
    return out


def trip_matrix(user: dict) -> list[dict]:
    """Every trip the user can see, with a capability table for each."""
    uid = user["uid"]
    account_role = user.get("role", "user")
    trips = db.query(
        """
        SELECT t.trip_id, t.title, t.start_date, t.end_date, t.status,
               t.is_public, tm.role AS my_role, u.full_name AS owner
          FROM trips t
          JOIN trip_members tm ON tm.trip_id = t.trip_id AND tm.user_id = %s
          JOIN users u ON u.user_id = t.owner_id
         ORDER BY t.start_date DESC
        """,
        (uid,),
    )
    out: list[dict] = []
    for trip in trips:
        caps = _trip_capabilities(trip["my_role"], account_role)
        out.append({
            **trip,
            "role_blurb": ROLE_BLURB.get(trip["my_role"], ""),
            "capabilities": caps,
            "can": sorted(k for k, v in caps.items() if v["allowed"]),
            "cannot": sorted(k for k, v in caps.items() if not v["allowed"]),
        })
    return out


def booking_options(user: dict) -> dict:
    """Which trips can take a new booking, and why the others cannot.

    This is what the booking dialog reads, so a viewer is never offered a trip
    the trigger would reject.
    """
    uid = user["uid"]
    account_role = user.get("role", "user")
    rows = db.query(
        """
        SELECT t.trip_id, t.title, t.start_date, t.end_date, t.status, tm.role AS my_role
          FROM trips t
          JOIN trip_members tm ON tm.trip_id = t.trip_id AND tm.user_id = %s
         ORDER BY t.start_date DESC
        """,
        (uid,),
    )
    bookable: list[dict] = []
    blocked: list[dict] = []
    for row in rows:
        role = row["my_role"]
        if account_role == "admin" or role in ("owner", "editor"):
            bookable.append({**row, "why": f"You are the {role} of this trip."})
        else:
            blocked.append({
                **row,
                "why": f"You are only a {role} of this trip, so booking is not available.",
                "needs": "Ask the owner to make you an editor.",
            })
    return {
        "bookable": bookable,
        "blocked": blocked,
        "can_book_any": bool(bookable),
    }


def global_matrix(user: dict) -> list[dict]:
    """Schema-wide actions with an allow/deny verdict for this account."""
    is_admin = user.get("role") == "admin"
    out: list[dict] = []
    for action in GLOBAL_ACTIONS:
        allowed = is_admin or not action["admin_only"]
        if allowed:
            reason = "Available to every signed-in account."
        else:
            reason = "Administrator only — this action can change shared data."
        out.append({**action, "allowed": allowed, "reason": reason})
    return out


def summary(user: dict) -> dict:
    """One call that returns the whole picture, for the dashboard header."""
    trips = trip_matrix(user)
    glob = global_matrix(user)
    return {
        "user": {
            "user_id": user["uid"],
            "full_name": user.get("name"),
            "email": user.get("email"),
            "role": user.get("role", "user"),
        },
        "global": glob,
        "global_can": [a["key"] for a in glob if a["allowed"]],
        "global_cannot": [a["key"] for a in glob if not a["allowed"]],
        "trips": trips,
        "counts": {
            "trips": len(trips),
            "owner": sum(1 for t in trips if t["my_role"] == "owner"),
            "editor": sum(1 for t in trips if t["my_role"] == "editor"),
            "viewer": sum(1 for t in trips if t["my_role"] == "viewer"),
            "can_book": sum(1 for t in trips if t["capabilities"]["book_room"]["allowed"]),
            "cannot_book": sum(1 for t in trips if not t["capabilities"]["book_room"]["allowed"]),
        },
        "role_blurb": ROLE_BLURB,
    }


def explain_denial(user: dict, trip_id: int, action: str) -> str | None:
    """Return a plain-language reason why an action would fail, or None if it is allowed.

    Used to pre-empt the database's own error message with something more useful.
    """
    if user.get("role") == "admin":
        return None
    row = db.query(
        "SELECT role FROM trip_members WHERE trip_id = %s AND user_id = %s",
        (trip_id, user["uid"]),
    )
    my_role = row[0]["role"] if row else None
    spec = next((a for a in TRIP_ACTIONS if a["key"] == action), None)
    if spec is None:
        return None
    if my_role in spec["roles"]:
        return None
    if my_role is None:
        return "You are not a member of this trip, so you cannot do that."
    needed = " or ".join(sorted(spec["roles"], key=lambda r: _ROLE_RANK.get(r, 0), reverse=True))
    return f"{spec['label']} needs the {needed} role, but you are {_article(my_role)} on this trip."
