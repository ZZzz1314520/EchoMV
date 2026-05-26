from __future__ import annotations

from datetime import datetime, timezone
import json
import sqlite3
from pathlib import Path

from .models import SearchResult


class Store:
    def __init__(self, database_path: Path):
        self.database_path = database_path
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._init()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path)
        connection.row_factory = sqlite3.Row
        return connection

    def _init(self) -> None:
        with self._connect() as db:
            db.executescript(
                """
                create table if not exists favorites (
                    id text primary key,
                    payload text not null,
                    created_at text not null
                );
                create table if not exists history (
                    id integer primary key autoincrement,
                    result_id text not null,
                    payload text not null,
                    played_at text not null
                );
                create table if not exists search_cache (
                    cache_key text primary key,
                    payload text not null,
                    created_at text not null
                );
                """
            )

    def save_favorite(self, item: SearchResult) -> None:
        with self._connect() as db:
            db.execute(
                "insert or replace into favorites (id, payload, created_at) values (?, ?, ?)",
                (
                    item.id,
                    item.model_dump_json(by_alias=True),
                    datetime.now(timezone.utc).isoformat(),
                ),
            )

    def remove_favorite(self, item_id: str) -> None:
        with self._connect() as db:
            db.execute("delete from favorites where id = ?", (item_id,))

    def list_favorites(self) -> list[SearchResult]:
        with self._connect() as db:
            rows = db.execute("select payload from favorites order by created_at desc").fetchall()
        return [SearchResult.model_validate_json(row["payload"]) for row in rows]

    def save_history(self, item: SearchResult, played_at: datetime | None = None) -> None:
        timestamp = (played_at or datetime.now(timezone.utc)).isoformat()
        with self._connect() as db:
            db.execute(
                "insert into history (result_id, payload, played_at) values (?, ?, ?)",
                (item.id, item.model_dump_json(by_alias=True), timestamp),
            )

    def list_history(self, limit: int = 50) -> list[SearchResult]:
        with self._connect() as db:
            rows = db.execute(
                "select payload from history order by played_at desc limit ?",
                (limit,),
            ).fetchall()
        return [SearchResult.model_validate_json(row["payload"]) for row in rows]

    def read_search_cache(self, cache_key: str, max_age_seconds: int | None = None) -> list[SearchResult] | None:
        with self._connect() as db:
            row = db.execute(
                "select payload, created_at from search_cache where cache_key = ?",
                (cache_key,),
            ).fetchone()
        if not row:
            return None
        if max_age_seconds is not None:
            created_at = datetime.fromisoformat(row["created_at"])
            if created_at.tzinfo is None:
                created_at = created_at.replace(tzinfo=timezone.utc)
            age_seconds = (datetime.now(timezone.utc) - created_at).total_seconds()
            if age_seconds > max_age_seconds:
                return None
        return [SearchResult.model_validate(item) for item in json.loads(row["payload"])]

    def write_search_cache(self, cache_key: str, results: list[SearchResult]) -> None:
        payload = json.dumps([item.model_dump(by_alias=True) for item in results], ensure_ascii=False)
        with self._connect() as db:
            db.execute(
                "insert or replace into search_cache (cache_key, payload, created_at) values (?, ?, ?)",
                (cache_key, payload, datetime.now(timezone.utc).isoformat()),
            )

    def clear_search_cache(self) -> None:
        with self._connect() as db:
            db.execute("delete from search_cache")
