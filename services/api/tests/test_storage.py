from datetime import datetime, timedelta, timezone

from app.models import SearchResult
from app.storage import Store


def test_search_cache_respects_max_age(tmp_path):
    store = Store(tmp_path / "test.sqlite3")
    item = SearchResult(
        id="bilibili:BV1",
        source="bilibili",
        videoId="BV1",
        title="晴天 官方MV",
        pageUrl="https://www.bilibili.com/video/BV1",
        tags=["官方", "mv"],
    )
    store.write_search_cache("晴天|bilibili", [item])

    with store._connect() as db:
        db.execute(
            "update search_cache set created_at = ?",
            ((datetime.now(timezone.utc) - timedelta(hours=2)).isoformat(),),
        )

    assert store.read_search_cache("晴天|bilibili", max_age_seconds=60) is None
    assert store.read_search_cache("晴天|bilibili", max_age_seconds=7201) is not None
