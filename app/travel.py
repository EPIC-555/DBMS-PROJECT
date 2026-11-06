"""Consumer-facing travel API: browse, book, plan and track trips.

This is the layer a traveller uses, as opposed to the DBMS dashboard in
``main.py`` which inspects the schema. It never reimplements a business rule:
room capacity, date windows, double-booking, expense ownership and budget
alerts are all enforced by the triggers and procedures in the database. When one
of them rejects a write the SIGNAL message is surfaced to the caller as a 400.

Hotels are a subtype of place (``hotels.hotel_id`` is a ``places.place_id``), so
a hotel's name and address come from ``places`` and its destination from there
too. Every query joins accordingly.
"""

from __future__ import annotations

import datetime as _dt
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from . import auth, db

router = APIRouter(prefix="/api/travel", tags=["travel"])


# --------------------------------------------------------------- dependencies
def signed_in(user: dict = Depends(auth.current_user)) -> dict:
    return user


def write_access(
    user: dict = Depends(auth.current_user),
    _: None = Depends(auth.verify_csrf),
) -> dict:
    """A signed-in user making an unsafe request with a valid CSRF token."""
    return user


def _friendly_db_error(exc: Exception) -> HTTPException:
    """Turn a trigger SIGNAL into a message the traveller can act on."""
    text = str(exc)
    if "1644" in text or "45000" in text:
        # MySQL reports the SIGNAL text after the last colon on 8.x.
        if ":" in text:
            text = text.split(":", 1)[-1].strip()
    return HTTPException(status_code=400, detail=text)


# ------------------------------------------------------------------- payloads
class TripCreate(BaseModel):
    title: str = Field(min_length=2, max_length=100)
    start_date: _dt.date
    end_date: _dt.date
    budget_total: float = Field(default=0, ge=0, le=10_000_000)


class BookingCreate(BaseModel):
    trip_id: int
    room_id: int
    check_in: _dt.date
    check_out: _dt.date
    num_guests: int = Field(default=1, ge=1, le=10)
    special_requests: str | None = Field(default=None, max_length=255)


class ExpenseCreate(BaseModel):
    trip_id: int
    expense_category_id: int
    amount: float = Field(gt=0, le=10_000_000)
    expense_date: _dt.date
    description: str = Field(min_length=1, max_length=200)


class ReviewCreate(BaseModel):
    destination_id: int
    rating: int = Field(ge=1, le=5)
    comment: str = Field(min_length=1, max_length=2000)


# ---------------------------------------------------------------- exploration
@router.get("/destinations")
def list_destinations(
    q: str | None = Query(default=None, max_length=60),
    user: dict = Depends(signed_in),
) -> list[dict]:
    """Every destination with its hotel count, rating and the caller's wishlist flag."""
    where = ""
    params: tuple = ()
    if q:
        where = "WHERE d.name LIKE %s OR d.country LIKE %s"
        like = f"%{q}%"
        params = (like, like)
    return db.query(
        f"""
        SELECT d.destination_id, d.name, d.country, d.description, d.best_season,
               (SELECT COUNT(*) FROM places p
                 WHERE p.destination_id = d.destination_id AND p.place_type = 'Hotel') AS hotels,
               (SELECT COUNT(*) FROM places p
                 WHERE p.destination_id = d.destination_id) AS attractions,
               COALESCE((SELECT ROUND(AVG(r.rating), 1) FROM reviews r
                          WHERE r.destination_id = d.destination_id), 0) AS avg_rating,
               (SELECT COUNT(*) FROM reviews r
                 WHERE r.destination_id = d.destination_id) AS review_count,
               (SELECT MIN(rt.base_rate) FROM room_types rt
                  JOIN places hp ON rt.hotel_id = hp.place_id
                 WHERE hp.destination_id = d.destination_id) AS from_price,
               EXISTS(SELECT 1 FROM saved_destinations s
                       WHERE s.destination_id = d.destination_id AND s.user_id = %s) AS saved
          FROM destinations d
          {where}
         ORDER BY d.name
        """,
        (user["uid"], *params),
    )


@router.get("/destinations/{destination_id}")
def destination_detail(destination_id: int, user: dict = Depends(signed_in)) -> dict:
    rows = db.query(
        """
        SELECT d.destination_id, d.name, d.country, d.description, d.best_season,
               COALESCE((SELECT ROUND(AVG(r.rating), 1) FROM reviews r
                          WHERE r.destination_id = d.destination_id), 0) AS avg_rating,
               (SELECT COUNT(*) FROM reviews r
                 WHERE r.destination_id = d.destination_id) AS review_count,
               EXISTS(SELECT 1 FROM saved_destinations s
                       WHERE s.destination_id = d.destination_id AND s.user_id = %s) AS saved
          FROM destinations d WHERE d.destination_id = %s
        """,
        (user["uid"], destination_id),
    )
    if not rows:
        raise HTTPException(404, "Destination not found")
    dest = rows[0]

    dest["places"] = db.query(
        """
        SELECT place_id, name, address, place_type
          FROM places
         WHERE destination_id = %s AND place_type <> 'Hotel'
         ORDER BY place_type, name
        """,
        (destination_id,),
    )
    dest["hotels"] = _hotel_rows(destination_id)
    dest["reviews"] = db.query(
        """
        SELECT r.rating, r.comment, r.created_at, u.full_name
          FROM reviews r JOIN users u ON u.user_id = r.user_id
         WHERE r.destination_id = %s
         ORDER BY r.created_at DESC LIMIT 20
        """,
        (destination_id,),
    )
    return dest


def _hotel_rows(destination_id: int | None = None) -> list[dict]:
    where = "WHERE p.destination_id = %s" if destination_id else ""
    params: tuple = (destination_id,) if destination_id else ()
    return db.query(
        f"""
        SELECT h.hotel_id, p.name, p.address, p.destination_id, d.name AS destination,
               h.star_rating, h.phone, h.email, h.check_in_time, h.check_out_time,
               (SELECT MIN(rt.base_rate) FROM room_types rt
                 WHERE rt.hotel_id = h.hotel_id) AS from_price,
               (SELECT COUNT(*) FROM room_types rt WHERE rt.hotel_id = h.hotel_id) AS room_types,
               (SELECT COUNT(*) FROM rooms r
                 WHERE r.hotel_id = h.hotel_id AND r.status = 'available') AS rooms_available,
               COALESCE((SELECT ROUND(AVG(hr.rating), 1)
                           FROM hotel_reviews hr
                           JOIN hotel_reservations hres
                             ON hres.reservation_id = hr.reservation_id
                          WHERE hres.room_id IN (SELECT room_id FROM rooms
                                                  WHERE hotel_id = h.hotel_id)), 0) AS avg_rating
          FROM hotels h
          JOIN places p ON p.place_id = h.hotel_id
          JOIN destinations d ON d.destination_id = p.destination_id
          {where}
         ORDER BY h.star_rating DESC, p.name
        """,
        params,
    )


@router.get("/hotels")
def list_hotels(
    destination_id: int | None = Query(default=None),
    user: dict = Depends(signed_in),
) -> list[dict]:
    return _hotel_rows(destination_id)


@router.get("/hotels/{hotel_id}")
def hotel_detail(hotel_id: int, user: dict = Depends(signed_in)) -> dict:
    rows = db.query(
        """
        SELECT h.hotel_id, p.name, p.address, p.destination_id, d.name AS destination,
               h.star_rating, h.phone, h.email, h.check_in_time, h.check_out_time,
               d.best_season
          FROM hotels h
          JOIN places p ON p.place_id = h.hotel_id
          JOIN destinations d ON d.destination_id = p.destination_id
         WHERE h.hotel_id = %s
        """,
        (hotel_id,),
    )
    if not rows:
        raise HTTPException(404, "Hotel not found")
    hotel = rows[0]

    hotel["amenities"] = db.query(
        """
        SELECT a.amenity_id, a.name, ha.is_complimentary
          FROM hotel_amenities ha JOIN amenities a ON a.amenity_id = ha.amenity_id
         WHERE ha.hotel_id = %s
         ORDER BY a.name
        """,
        (hotel_id,),
    )
    hotel["room_types"] = db.query(
        """
        SELECT room_type_id, name, bed_type, max_occupancy, base_rate,
               (SELECT COUNT(*) FROM rooms r
                 WHERE r.room_type_id = room_types.room_type_id
                   AND r.hotel_id = room_types.hotel_id
                   AND r.status = 'available') AS rooms_available
          FROM room_types
         WHERE hotel_id = %s
         ORDER BY base_rate
        """,
        (hotel_id,),
    )
    hotel["reviews"] = db.query(
        """
        SELECT hr.rating, hr.title, hr.comment, hr.created_at, u.full_name
          FROM hotel_reviews hr
          JOIN hotel_reservations hres ON hres.reservation_id = hr.reservation_id
          JOIN rooms r ON r.room_id = hres.room_id
          JOIN users u ON u.user_id = hres.booked_by
         WHERE r.hotel_id = %s
         ORDER BY hr.created_at DESC LIMIT 20
        """,
        (hotel_id,),
    )
    return hotel


@router.get("/hotels/{hotel_id}/availability")
def hotel_availability(
    hotel_id: int,
    check_in: _dt.date = Query(...),
    check_out: _dt.date = Query(...),
    guests: int = Query(default=1, ge=1, le=10),
    user: dict = Depends(signed_in),
) -> list[dict]:
    """Rooms at this hotel free for the whole window and big enough for the party.

    Overlap uses the standard half-open test (new_in < existing_out AND
    new_out > existing_in), the same one the BEFORE INSERT trigger applies, so
    what this returns and what the trigger accepts cannot disagree.
    """
    if check_out <= check_in:
        raise HTTPException(400, "Check-out must be after check-in")
    return db.query(
        """
        SELECT r.room_id, r.room_number, r.floor_no,
               rt.room_type_id, rt.name AS room_type, rt.bed_type,
               rt.max_occupancy, rt.base_rate,
               DATEDIFF(%s, %s) AS nights,
               rt.base_rate * DATEDIFF(%s, %s) AS total_cost
          FROM rooms r
          JOIN room_types rt ON rt.room_type_id = r.room_type_id
                            AND rt.hotel_id = r.hotel_id
         WHERE r.hotel_id = %s
           AND r.status = 'available'
           AND rt.max_occupancy >= %s
           AND r.room_id NOT IN (
                 SELECT h.room_id FROM hotel_reservations h
                  WHERE h.status <> 'cancelled'
                    AND %s < h.check_out AND %s > h.check_in)
         ORDER BY rt.base_rate, r.room_number
        """,
        (check_out, check_in, check_out, check_in, hotel_id, guests, check_in, check_out),
    )


@router.get("/search")
def search(
    q: str = Query(min_length=1, max_length=60),
    user: dict = Depends(signed_in),
) -> dict:
    """One box covering destinations, hotels and things to see."""
    like = f"%{q}%"
    return {
        "destinations": db.query(
            "SELECT destination_id, name, country FROM destinations "
            "WHERE name LIKE %s OR country LIKE %s ORDER BY name LIMIT 10",
            (like, like),
        ),
        "hotels": db.query(
            "SELECT h.hotel_id, p.name, d.name AS destination, h.star_rating "
            "FROM hotels h JOIN places p ON p.place_id = h.hotel_id "
            "JOIN destinations d ON d.destination_id = p.destination_id "
            "WHERE p.name LIKE %s OR p.address LIKE %s ORDER BY p.name LIMIT 10",
            (like, like),
        ),
        "places": db.query(
            "SELECT p.place_id, p.name, p.place_type, d.name AS destination "
            "FROM places p JOIN destinations d ON d.destination_id = p.destination_id "
            "WHERE p.name LIKE %s AND p.place_type <> 'Hotel' ORDER BY p.name LIMIT 10",
            (like,),
        ),
    }


@router.get("/recommendations")
def recommendations(
    month: int | None = Query(default=None, ge=1, le=12),
    limit: int = Query(default=6, ge=1, le=20),
    user: dict = Depends(signed_in),
) -> dict:
    from . import recommender

    return recommender.recommend(user["uid"], month=month, limit=limit)


# --------------------------------------------------------------------- trips
@router.get("/trips")
def my_trips(user: dict = Depends(signed_in)) -> list[dict]:
    """Trips the caller belongs to, with booking and spend totals."""
    return db.query(
        """
        SELECT t.trip_id, t.title, t.start_date, t.end_date, t.budget_total,
               t.status, t.is_public, tm.role AS my_role,
               DATEDIFF(t.end_date, t.start_date) + 1 AS days,
               (SELECT COUNT(*) FROM trip_members m WHERE m.trip_id = t.trip_id) AS members,
               COALESCE((SELECT SUM(h.rate_per_night *
                          DATEDIFF(h.check_out, h.check_in))
                           FROM hotel_reservations h
                          WHERE h.trip_id = t.trip_id AND h.status <> 'cancelled'), 0)
                 AS hotel_booked,
               COALESCE((SELECT SUM(x.fare) FROM transport_bookings x
                          WHERE x.trip_id = t.trip_id AND x.status <> 'cancelled'), 0)
                 AS transport_booked,
               COALESCE((SELECT SUM(e.amount) FROM expenses e
                          WHERE e.trip_id = t.trip_id), 0) AS actual_spend
          FROM trips t
          JOIN trip_members tm ON tm.trip_id = t.trip_id
         WHERE tm.user_id = %s
         ORDER BY t.start_date DESC
        """,
        (user["uid"],),
    )


@router.post("/trips", status_code=201)
def create_trip(payload: TripCreate, user: dict = Depends(write_access)) -> dict:
    """Create a trip through sp_create_trip.

    The procedure inserts the trip, adds the owner as a trip member and
    generates one itinerary_days row per day, so the itinerary is never
    half-built.
    """
    if payload.end_date < payload.start_date:
        raise HTTPException(400, "End date must not be before the start date")
    if (payload.end_date - payload.start_date).days > 60:
        raise HTTPException(400, "Trips longer than 60 days are not supported")
    try:
        result = db.call_procedure(
            "sp_create_trip",
            (user["uid"], payload.title, payload.start_date,
             payload.end_date, payload.budget_total),
            ("p_trip_id",),
        )
    except Exception as exc:
        raise _friendly_db_error(exc) from exc
    trip_id = result.get("out", {}).get("p_trip_id")
    return {"trip_id": trip_id, "title": payload.title}


@router.get("/trips/{trip_id}")
def trip_detail(trip_id: int, user: dict = Depends(signed_in)) -> dict:
    """A trip the caller may see, with itinerary, stays, spend and timeline."""
    rows = db.query(
        """
        SELECT t.trip_id, t.title, t.start_date, t.end_date, t.budget_total,
               t.status, t.is_public, tm.role AS my_role, u.full_name AS owner
          FROM trips t
          JOIN trip_members tm ON tm.trip_id = t.trip_id AND tm.user_id = %s
          JOIN users u ON u.user_id = t.owner_id
         WHERE t.trip_id = %s
        """,
        (user["uid"], trip_id),
    )
    if not rows:
        raise HTTPException(404, "Trip not found, or you are not a member")
    trip = rows[0]

    trip["members"] = db.query(
        """
        SELECT u.full_name, u.email, m.role
          FROM trip_members m JOIN users u ON u.user_id = m.user_id
         WHERE m.trip_id = %s ORDER BY FIELD(m.role,'owner','editor','viewer'), u.full_name
        """,
        (trip_id,),
    )
    trip["days"] = db.query(
        """
        SELECT d.day_id, d.day_number, d.day_date, d.notes,
               (SELECT COUNT(*) FROM itinerary_items i WHERE i.day_id = d.day_id) AS items
          FROM itinerary_days d WHERE d.trip_id = %s ORDER BY d.day_number
        """,
        (trip_id,),
    )
    trip["items"] = db.query(
        """
        SELECT i.item_id, i.day_id, i.seq_no, i.title, i.start_time, i.end_time,
               i.estimated_cost, i.status, i.notes,
               c.name AS category, p.name AS place
          FROM itinerary_items i
          JOIN itinerary_days d ON d.day_id = i.day_id
          LEFT JOIN activity_categories c ON c.category_id = i.category_id
          LEFT JOIN places p ON p.place_id = i.place_id
         WHERE d.trip_id = %s
         ORDER BY d.day_number, i.seq_no
        """,
        (trip_id,),
    )
    trip["stays"] = db.query(
        """
        SELECT * FROM v_reservation_summary WHERE trip_id = %s ORDER BY check_in
        """,
        (trip_id,),
    )
    trip["transport"] = db.query(
        """
        SELECT * FROM v_trip_transport WHERE trip_id = %s ORDER BY depart_at
        """,
        (trip_id,),
    )
    trip["expenses"] = db.query(
        """
        SELECT e.expense_id, e.amount, e.expense_date, e.description,
               c.name AS category, u.full_name AS paid_by
          FROM expenses e
          JOIN expense_categories c ON c.expense_category_id = e.expense_category_id
          JOIN users u ON u.user_id = e.paid_by
         WHERE e.trip_id = %s
         ORDER BY e.expense_date DESC, e.expense_id DESC
        """,
        (trip_id,),
    )
    costs = db.query("SELECT * FROM v_trip_cost_summary WHERE trip_id = %s", (trip_id,))
    trip["costs"] = costs[0] if costs else {}
    return trip


# ------------------------------------------------------------------ bookings
@router.post("/bookings", status_code=201)
def book_room(payload: BookingCreate, user: dict = Depends(write_access)) -> dict:
    """Reserve a room through sp_book_room.

    sp_book_room locks the room row FOR UPDATE and inserts the reservation; the
    BEFORE INSERT trigger then checks capacity, the trip date window, that the
    booker is an owner or editor, and that the room is not already taken. Those
    rejections come back as 400 with the trigger's own wording.
    """
    if payload.check_out <= payload.check_in:
        raise HTTPException(400, "Check-out must be after check-in")
    try:
        result = db.call_procedure(
            "sp_book_room",
            (payload.trip_id, payload.room_id, user["uid"],
             payload.check_in, payload.check_out, payload.num_guests),
            ("p_reservation_id",),
        )
    except Exception as exc:
        raise _friendly_db_error(exc) from exc

    reservation_id = result.get("out", {}).get("p_reservation_id")
    if payload.special_requests and reservation_id:
        db.execute(
            "UPDATE hotel_reservations SET special_requests = %s WHERE reservation_id = %s",
            (payload.special_requests, reservation_id),
        )
    rows = db.query(
        "SELECT * FROM v_reservation_summary WHERE reservation_id = %s", (reservation_id,)
    )
    return {"reservation_id": reservation_id, "reservation": rows[0] if rows else None}


@router.get("/bookings")
def my_bookings(user: dict = Depends(signed_in)) -> list[dict]:
    return db.query(
        """
        SELECT v.*, t.start_date, t.end_date
          FROM v_reservation_summary v
          JOIN trips t ON t.trip_id = v.trip_id
          JOIN trip_members m ON m.trip_id = v.trip_id AND m.user_id = %s
         ORDER BY v.check_in DESC
        """,
        (user["uid"],),
    )


@router.post("/bookings/{reservation_id}/cancel")
def cancel_booking(reservation_id: int, user: dict = Depends(write_access)) -> dict:
    """Cancel a stay the caller booked. Only a pending or confirmed stay can go."""
    rows = db.query(
        """
        SELECT h.reservation_id, h.booked_by, h.status
          FROM hotel_reservations h
          JOIN trip_members m ON m.trip_id = h.trip_id AND m.user_id = %s
         WHERE h.reservation_id = %s
        """,
        (user["uid"], reservation_id),
    )
    if not rows:
        raise HTTPException(404, "Reservation not found")
    row = rows[0]
    if row["booked_by"] != user["uid"] and user["role"] != "admin":
        raise HTTPException(403, "Only the person who booked can cancel")
    if row["status"] in ("cancelled", "completed"):
        raise HTTPException(400, f"A {row['status']} reservation cannot be cancelled")
    try:
        db.execute(
            "UPDATE hotel_reservations SET status = 'cancelled' WHERE reservation_id = %s",
            (reservation_id,),
        )
    except Exception as exc:
        raise _friendly_db_error(exc) from exc
    return {"reservation_id": reservation_id, "status": "cancelled"}


# ------------------------------------------------------------------ expenses
@router.get("/expense-categories")
def expense_categories(user: dict = Depends(signed_in)) -> list[dict]:
    return db.query("SELECT * FROM expense_categories ORDER BY name")


@router.post("/expenses", status_code=201)
def add_expense(payload: ExpenseCreate, user: dict = Depends(write_access)) -> dict:
    """Record an expense on a trip the caller belongs to.

    The BEFORE INSERT trigger checks the trip exists and that the amount is
    positive; the AFTER INSERT trigger raises a trip_alert if the category or
    the trip budget is exceeded, so no budget logic lives here.
    """
    member = db.query(
        "SELECT role FROM trip_members WHERE trip_id = %s AND user_id = %s",
        (payload.trip_id, user["uid"]),
    )
    if not member:
        raise HTTPException(403, "You are not a member of this trip")
    try:
        expense_id = db.insert(
            """
            INSERT INTO expenses (trip_id, expense_category_id, paid_by, amount,
                                  expense_date, description)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (payload.trip_id, payload.expense_category_id, user["uid"],
             payload.amount, payload.expense_date, payload.description),
        )
    except Exception as exc:
        raise _friendly_db_error(exc) from exc

    alerts = db.query(
        "SELECT alert_type, message FROM trip_alerts WHERE trip_id = %s "
        "ORDER BY created_at DESC LIMIT 3",
        (payload.trip_id,),
    )
    costs = db.query("SELECT * FROM v_trip_cost_summary WHERE trip_id = %s", (payload.trip_id,))
    return {
        "expense_id": expense_id,
        "alerts": alerts,
        "costs": costs[0] if costs else {},
    }


# ------------------------------------------------------------------- reviews
@router.post("/reviews", status_code=201)
def add_review(payload: ReviewCreate, user: dict = Depends(write_access)) -> dict:
    """Rate a destination. One review per user per destination."""
    exists = db.query(
        "SELECT 1 FROM reviews WHERE user_id = %s AND destination_id = %s",
        (user["uid"], payload.destination_id),
    )
    if exists:
        raise HTTPException(409, "You have already reviewed this destination")
    try:
        db.insert(
            "INSERT INTO reviews (user_id, destination_id, rating, comment) "
            "VALUES (%s, %s, %s, %s)",
            (user["uid"], payload.destination_id, payload.rating, payload.comment),
        )
    except Exception as exc:
        raise _friendly_db_error(exc) from exc
    return {"ok": True}


# ------------------------------------------------------------------ wishlist
@router.get("/wishlist")
def wishlist(user: dict = Depends(signed_in)) -> list[dict]:
    return db.query(
        """
        SELECT d.destination_id, d.name, d.country, d.best_season, s.saved_at,
               (SELECT MIN(rt.base_rate) FROM room_types rt
                  JOIN places p ON p.place_id = rt.hotel_id
                 WHERE p.destination_id = d.destination_id) AS from_price
          FROM saved_destinations s
          JOIN destinations d ON d.destination_id = s.destination_id
         WHERE s.user_id = %s
         ORDER BY s.saved_at DESC
        """,
        (user["uid"],),
    )


@router.post("/wishlist/{destination_id}")
def toggle_wishlist(destination_id: int, user: dict = Depends(write_access)) -> dict:
    """Add or remove a destination from the caller's wishlist."""
    if not db.query("SELECT 1 FROM destinations WHERE destination_id = %s", (destination_id,)):
        raise HTTPException(404, "Destination not found")
    existing = db.query(
        "SELECT 1 FROM saved_destinations WHERE user_id = %s AND destination_id = %s",
        (user["uid"], destination_id),
    )
    if existing:
        db.execute(
            "DELETE FROM saved_destinations WHERE user_id = %s AND destination_id = %s",
            (user["uid"], destination_id),
        )
        return {"saved": False}
    try:
        db.insert(
            "INSERT INTO saved_destinations (user_id, destination_id) VALUES (%s, %s)",
            (user["uid"], destination_id),
        )
    except Exception as exc:
        raise _friendly_db_error(exc) from exc
    return {"saved": True}


# ------------------------------------------------------------- profile stats
@router.get("/profile")
def profile(user: dict = Depends(signed_in)) -> dict:
    """Headline numbers for the account page."""
    stats = db.query(
        """
        SELECT
          (SELECT COUNT(*) FROM trips t JOIN trip_members m ON m.trip_id = t.trip_id
            WHERE m.user_id = %s) AS trips,
          (SELECT COUNT(*) FROM saved_destinations WHERE user_id = %s) AS wishlist,
          (SELECT COUNT(*) FROM reviews WHERE user_id = %s) AS reviews,
          (SELECT COUNT(*) FROM hotel_reservations WHERE booked_by = %s
            AND status <> 'cancelled') AS stays,
          COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.paid_by = %s), 0) AS spend
        """,
        (user["uid"],) * 5,
    )
    return {"user": user, "stats": stats[0] if stats else {}}
