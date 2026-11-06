"""Destination recommendations.

The repository's AGENTS.md documents a recommendation layer (07) that is not in
the repo, so the model is implemented here against the existing views and
tables. It scores every destination a user has NOT visited, out of 100:

    quality   30  average rating, scaled
    crowd     15  number of reviews
    wishlist  15  number of saves
    taste     20  the user saved or rated it 4+
    season    20  the destination is in season for the chosen month

Weights are literal constants; keep them in step with the documentation if the
ranking is meant to change.
"""

from __future__ import annotations

import calendar
import re
from typing import Any

from . import db

W_QUALITY, W_CROWD, W_WISHLIST, W_TASTE, W_SEASON = 30, 15, 15, 20, 20

_MONTHS = {name.lower(): n for n, name in enumerate(calendar.month_name) if name}
_MONTHS.update({name.lower(): n for n, name in enumerate(calendar.month_abbr) if name})


def _months_in_season(text: str | None) -> set[int]:
    """Turn free text like 'November to February' into month numbers."""
    if not text:
        return set()
    found: list[int] = []
    for token in re.findall(r"[A-Za-z]+", text):
        month = _MONTHS.get(token.lower())
        if month:
            found.append(month)
    if not found:
        return set()
    if len(found) == 1:
        return {found[0]}
    start, end = found[0], found[-1]
    if start <= end:
        return set(range(start, end + 1))
    # wraps the new year, e.g. November to February
    return set(range(start, 13)) | set(range(1, end + 1))


def _visited(user_id: int) -> set[int]:
    """Destinations already on the user's trips, so they are not recommended again.

    This matches the documented behaviour that a user who owns the Goa trip never
    gets Goa back as a suggestion.
    """
    rows = db.query(
        """
        SELECT DISTINCT d.destination_id
          FROM trip_members tm
          JOIN trips t           ON t.trip_id = tm.trip_id
          JOIN itinerary_days iy ON iy.trip_id = t.trip_id
          JOIN itinerary_items it ON it.day_id = iy.day_id
          JOIN places p          ON p.place_id = it.place_id
          JOIN destinations d    ON d.destination_id = p.destination_id
         WHERE tm.user_id = %s
        UNION
        SELECT DISTINCT p.destination_id
          FROM hotel_reservations hr
          JOIN rooms r   ON r.room_id = hr.room_id
          JOIN hotels h  ON h.hotel_id = r.hotel_id
          JOIN places p  ON p.place_id = h.hotel_id
          JOIN trip_members tm ON tm.trip_id = hr.trip_id
         WHERE tm.user_id = %s AND hr.status <> 'cancelled'
        """,
        (user_id, user_id),
    )
    return {r["destination_id"] for r in rows}


def _stats() -> dict[int, dict[str, Any]]:
    rows = db.query(
        """
        SELECT d.destination_id, d.name, d.country, d.best_season,
               COALESCE((SELECT AVG(r.rating) FROM reviews r
                          WHERE r.destination_id = d.destination_id), 0) AS avg_rating,
               (SELECT COUNT(*) FROM reviews r
                 WHERE r.destination_id = d.destination_id) AS review_count,
               (SELECT COUNT(*) FROM saved_destinations s
                 WHERE s.destination_id = d.destination_id) AS save_count
          FROM destinations d
        """
    )
    return {r["destination_id"]: r for r in rows}


def _user_taste(user_id: int) -> tuple[set[int], set[int]]:
    saved = {r["destination_id"] for r in db.query(
        "SELECT destination_id FROM saved_destinations WHERE user_id = %s", (user_id,))}
    liked = {r["destination_id"] for r in db.query(
        "SELECT destination_id FROM reviews WHERE user_id = %s AND rating >= 4", (user_id,))}
    return saved, liked


def recommend(user_id: int, month: int | None = None, limit: int = 5) -> dict:
    """Score unvisited destinations for a user, best first."""
    if month is None:
        month = 1
    stats = _stats()
    visited = _visited(user_id)
    saved, liked = _user_taste(user_id)

    max_reviews = max((s["review_count"] for s in stats.values()), default=0) or 1
    max_saves = max((s["save_count"] for s in stats.values()), default=0) or 1

    scored: list[dict] = []
    for dest_id, s in stats.items():
        if dest_id in visited:
            continue
        months = _months_in_season(s["best_season"])
        in_season = month in months

        quality = W_QUALITY * (float(s["avg_rating"]) / 5.0)
        crowd = W_CROWD * (s["review_count"] / max_reviews)
        wishlist = W_WISHLIST * (s["save_count"] / max_saves)
        taste = W_TASTE if (dest_id in saved or dest_id in liked) else 0
        season = W_SEASON if in_season else 0

        reasons: list[str] = []
        if dest_id in saved:
            reasons.append("already on your wishlist")
        if dest_id in liked:
            reasons.append("you rated it 4 or higher")
        if in_season:
            reasons.append(f"in season in {calendar.month_name[month]}")
        if float(s["avg_rating"]) >= 4.5:
            reasons.append("highly rated")

        scored.append({
            "destination_id": dest_id,
            "name": s["name"],
            "country": s["country"],
            "best_season": s["best_season"],
            "avg_rating": round(float(s["avg_rating"]), 2),
            "review_count": s["review_count"],
            "save_count": s["save_count"],
            "in_season": in_season,
            "score": round(quality + crowd + wishlist + taste + season, 1),
            "breakdown": {
                "quality": round(quality, 1),
                "crowd": round(crowd, 1),
                "wishlist": round(wishlist, 1),
                "taste": round(taste, 1),
                "season": round(season, 1),
            },
            "reasons": reasons,
        })

    scored.sort(key=lambda r: r["score"], reverse=True)
    return {
        "user_id": user_id,
        "month": month,
        "month_name": calendar.month_name[month],
        "visited_destination_ids": sorted(visited),
        "weights": {"quality": W_QUALITY, "crowd": W_CROWD, "wishlist": W_WISHLIST,
                    "taste": W_TASTE, "season": W_SEASON},
        "results": scored[:limit],
        "all": scored,
    }
