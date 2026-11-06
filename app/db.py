"""Pooled MySQL access for the Travel Itinerary app.

Business rules live in MySQL (triggers, constraints, procedures); this module
only runs statements and converts MySQL types into JSON-friendly Python.
"""

from __future__ import annotations

import datetime as _dt
import decimal
import os
from typing import Any

import mysql.connector
from mysql.connector import pooling

_POOL: pooling.MySQLConnectionPool | None = None


def _config() -> dict[str, Any]:
    return {
        "host": os.getenv("DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("DB_PORT", "3306")),
        "user": os.getenv("DB_USER", "root"),
        "password": os.getenv("DB_PASSWORD", "rootpw"),
        "database": os.getenv("DB_NAME", "travel_itinerary_db"),
        "charset": "utf8mb4",
        "autocommit": True,
    }


def _pool() -> pooling.MySQLConnectionPool:
    global _POOL
    if _POOL is None:
        _POOL = pooling.MySQLConnectionPool(
            pool_name="travel_pool",
            pool_size=int(os.getenv("DB_POOL_SIZE", "8")),
            **_config(),
        )
    return _POOL


def jsonify(value: Any) -> Any:
    """Convert MySQL values to types FastAPI can serialise."""
    if isinstance(value, decimal.Decimal):
        return float(value)
    if isinstance(value, _dt.datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, _dt.date):
        return value.isoformat()
    if isinstance(value, _dt.timedelta):
        return int(value.total_seconds())
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return value


def _clean_rows(rows: list[dict]) -> list[dict]:
    # information_schema returns column names in upper case on some MySQL builds,
    # so keys are normalised to lower case for a consistent API.
    return [{k.lower(): jsonify(v) for k, v in row.items()} for row in rows]


def query(sql: str, params: tuple = ()) -> list[dict]:
    """Run a SELECT and return all rows as dicts."""
    conn = _pool().get_connection()
    try:
        cur = conn.cursor(dictionary=True)
        try:
            cur.execute(sql, params)
            rows = cur.fetchall() if cur.with_rows else []
        finally:
            cur.close()
        return _clean_rows(rows or [])
    finally:
        conn.close()


def execute(sql: str, params: tuple = ()) -> int:
    """Run a DML statement, return affected row count."""
    conn = _pool().get_connection()
    try:
        cur = conn.cursor()
        try:
            cur.execute(sql, params)
            return cur.rowcount
        finally:
            cur.close()
    finally:
        conn.close()


def insert(sql: str, params: tuple = ()) -> int:
    """Run an INSERT and return the new AUTO_INCREMENT id.

    The commit is explicit rather than relying on the pool's autocommit setting,
    so a caller that later wraps several statements in a transaction still works.
    """
    conn = _pool().get_connection()
    try:
        cur = conn.cursor()
        try:
            cur.execute(sql, params)
            conn.commit()
            return cur.lastrowid
        finally:
            cur.close()
    finally:
        conn.close()


def call_procedure(name: str, in_args: tuple, out_vars: tuple[str, ...]) -> dict:
    """Call a stored procedure that mixes IN and OUT parameters.

    mysql-connector returns one result set per SELECT inside the procedure and
    leaves them queued; anything left unread corrupts the pooled connection, so
    every set is drained here. Returns the last non-empty set plus OUT values.
    """
    placeholders = ", ".join(["%s"] * len(in_args))
    outs = "".join(f", @{v}" for v in out_vars)
    conn = _pool().get_connection()
    try:
        cur = conn.cursor(dictionary=True)
        try:
            cur.execute(f"CALL {name}({placeholders}{outs})", in_args)
            last_rows: list[dict] = []
            while True:
                if cur.with_rows:
                    rows = cur.fetchall() or []
                    if rows:
                        last_rows = rows
                if not cur.nextset():
                    break
            result: dict[str, Any] = {"rows": _clean_rows(last_rows)}
            if out_vars:
                select_list = ", ".join(f"@{v} AS {v}" for v in out_vars)
                cur.execute(f"SELECT {select_list}")
                fetched = cur.fetchall() or [{}]
                result["out"] = _clean_rows(fetched)[0]
            return result
        finally:
            cur.close()
    finally:
        conn.close()


def sandbox(statements: list[dict]) -> list[dict]:
    """Run statements inside one transaction and always roll back.

    Used by the rule tests and the cascade/alert/audit demos so a demonstration
    never changes the data. Each statement is a dict with keys sql, params and an
    optional capture flag; the return value has one entry per statement, either
    {"ok": True, "rows": [...], "rowcount": n} or {"ok": False, "error": ...}.
    """
    conn = _pool().get_connection()
    results: list[dict] = []
    try:
        conn.start_transaction()
        cur = conn.cursor(dictionary=True)
        try:
            for st in statements:
                try:
                    cur.execute(st["sql"], st.get("params", ()))
                    rows = _clean_rows(cur.fetchall() or []) if cur.with_rows else []
                    results.append({"ok": True, "rows": rows, "rowcount": cur.rowcount})
                except mysql.connector.Error as exc:
                    results.append({
                        "ok": False,
                        "error": str(exc),
                        "errno": exc.errno,
                        "sqlstate": getattr(exc, "sqlstate", None),
                    })
                    while cur.nextset():
                        pass
        finally:
            cur.close()
        conn.rollback()
    finally:
        conn.close()
    return results


def scalar(sql: str, params: tuple = ()) -> Any:
    rows = query(sql, params)
    if not rows:
        return None
    return next(iter(rows[0].values()))


def health() -> dict:
    """Connection + acceptance-count probe used by the dashboard header."""
    try:
        counts = query(
            """
            SELECT
              (SELECT COUNT(*) FROM information_schema.tables
                WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE') AS tables,
              (SELECT COUNT(*) FROM information_schema.referential_constraints
                WHERE constraint_schema = DATABASE()) AS foreign_keys,
              (SELECT COUNT(*) FROM information_schema.triggers
                WHERE trigger_schema = DATABASE()) AS triggers,
              (SELECT COUNT(*) FROM information_schema.views
                WHERE table_schema = DATABASE()) AS views,
              (SELECT COUNT(*) FROM information_schema.routines
                WHERE routine_schema = DATABASE()) AS procedures
            """
        )
        return {
            "connected": True,
            "version": scalar("SELECT VERSION()"),
            "database": scalar("SELECT DATABASE()"),
            "counts": counts[0] if counts else {},
        }
    except mysql.connector.Error as exc:
        return {"connected": False, "error": str(exc)}
