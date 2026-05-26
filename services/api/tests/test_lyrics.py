import asyncio

import httpx

from app.lyrics import _fetch_netease_lyrics, fetch_lyrics, lyrics_cache_key, parse_lrc
from app.models import LyricLine, LyricsResponse


def test_parse_lrc_supports_multiple_timestamps_and_millis():
    lines = parse_lrc("[00:01.20][00:02.345]Hello\n[01:00]World\n")

    assert [line.time_ms for line in lines] == [1200, 2345, 60000]
    assert [line.text for line in lines] == ["Hello", "Hello", "World"]


def test_parse_lrc_skips_empty_text():
    assert parse_lrc("[00:01.00]\n[ar:EchoMV]") == []


def test_lyrics_cache_key_normalizes_noisy_titles():
    assert lyrics_cache_key("【4K修复】周杰伦 - 晴天MV 2160P修复版", "zyl2012_音乐无限", 240) == (
        "晴天|周杰伦|240"
    )


def test_fetch_lyrics_uses_netease_after_lrclib_miss(monkeypatch):
    async def fake_lrclib(*_args):
        return None

    async def fake_netease(_client, track_name, artist_name, _duration):
        return LyricsResponse(
            title=track_name,
            artist=artist_name,
            confidence=0.82,
            source="netease",
            lines=[LyricLine(timeMs=0, text="第一句")],
        )

    monkeypatch.setattr("app.lyrics._fetch_lrclib_lyrics", fake_lrclib)
    monkeypatch.setattr("app.lyrics._fetch_netease_lyrics", fake_netease)

    lyrics = asyncio.run(fetch_lyrics("周杰伦 - 晴天 官方MV", None, 240))

    assert lyrics.source == "netease"
    assert lyrics.lines[0].text == "第一句"


def test_fetch_lyrics_falls_back_to_demo_when_sources_fail(monkeypatch):
    async def fake_lrclib(*_args):
        return None

    async def fake_netease(*_args):
        return None

    monkeypatch.setattr("app.lyrics._fetch_lrclib_lyrics", fake_lrclib)
    monkeypatch.setattr("app.lyrics._fetch_netease_lyrics", fake_netease)

    lyrics = asyncio.run(fetch_lyrics("不存在的歌 官方MV", None, None))

    assert lyrics.source == "demo"
    assert lyrics.lines


def test_fetch_netease_lyrics_parses_synced_and_translated_lrc():
    client = _FakeNeteaseClient(
        [
            {
                "result": {
                    "songs": [
                        {
                            "id": 186016,
                            "name": "晴天",
                            "artists": [{"name": "周杰伦"}],
                            "duration": 269000,
                        }
                    ]
                }
            },
            {
                "lrc": {"lyric": "[00:01.00]故事的小黄花\n[00:02.00]从出生那年就飘着"},
                "tlyric": {"lyric": "[00:01.00]Translated line"},
            },
        ]
    )

    lyrics = asyncio.run(_fetch_netease_lyrics(client, "晴天", "周杰伦", 269))

    assert lyrics is not None
    assert lyrics.source == "netease"
    assert lyrics.lines[0].text == "故事的小黄花"
    assert lyrics.lines[0].translated_text == "Translated line"


def test_fetch_netease_lyrics_returns_none_for_empty_lrc():
    client = _FakeNeteaseClient(
        [
            {
                "result": {
                    "songs": [
                        {"id": 1, "name": "晴天", "artists": [{"name": "周杰伦"}], "duration": 269000}
                    ]
                }
            },
            {"lrc": {"lyric": ""}},
        ]
    )

    assert asyncio.run(_fetch_netease_lyrics(client, "晴天", "周杰伦", 269)) is None


class _FakeNeteaseClient:
    def __init__(self, payloads):
        self._payloads = list(payloads)

    async def get(self, *_args, **_kwargs):
        payload = self._payloads.pop(0)
        return httpx.Response(200, json=payload, request=httpx.Request("GET", "https://example.test"))
