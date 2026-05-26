from datetime import datetime, timedelta, timezone

from app.models import LyricLine, LyricsResponse, SearchResult
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


def test_lyrics_cache_round_trips_response(tmp_path):
    store = Store(tmp_path / "test.sqlite3")
    lyrics = LyricsResponse(
        title="晴天",
        artist="周杰伦",
        confidence=0.82,
        source="netease",
        lines=[LyricLine(timeMs=1000, text="故事的小黄花")],
    )

    store.write_lyrics_cache("晴天|周杰伦|269", lyrics)

    cached = store.read_lyrics_cache("晴天|周杰伦|269")
    assert cached is not None
    assert cached.source == "netease"
    assert cached.lines[0].text == "故事的小黄花"
