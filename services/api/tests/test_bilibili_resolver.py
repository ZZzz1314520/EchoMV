import asyncio
from datetime import datetime, timezone

from app.models import ResolveRequest
from app.resolvers import bilibili
from app.resolvers.bilibili import (
    BROWSER_USER_AGENT,
    BilibiliAudioResolver,
    _expires_at,
    _select_audio_stream,
)


def test_select_audio_stream_prefers_highest_bandwidth():
    selected = _select_audio_stream(
        {
            "audio": [
                {"baseUrl": "low", "bandwidth": 100},
                {"baseUrl": "high", "bandwidth": 300},
            ]
        }
    )

    assert selected["baseUrl"] == "high"


def test_expires_at_uses_bilibili_deadline_query_param():
    expires = _expires_at("https://example.test/audio.m4s?deadline=2000000000")

    assert expires == datetime.fromtimestamp(2000000000, timezone.utc)


def test_resolve_passes_bilibili_headers_to_waveform_analyzer(monkeypatch):
    captured = {}

    async def fake_analyze(stream_url, request_headers, fallback):
        captured["stream_url"] = stream_url
        captured["request_headers"] = request_headers
        captured["fallback"] = fallback
        return [0.9]

    monkeypatch.setattr(bilibili, "analyze_waveform_peaks", fake_analyze)
    monkeypatch.setattr(bilibili.httpx, "AsyncClient", _FakeBilibiliClient)

    request = ResolveRequest(
        source="bilibili",
        videoId="BV123",
        title="Song",
        pageUrl="https://www.bilibili.com/video/BV123",
    )

    media = asyncio.run(BilibiliAudioResolver().resolve(request))

    assert media.waveform_peaks == [0.9]
    assert (
        captured["stream_url"]
        == "https://example.test/audio.m4s?deadline=2000000000"
    )
    assert captured["request_headers"] == {
        "User-Agent": BROWSER_USER_AGENT,
        "Referer": "https://www.bilibili.com/video/BV123",
    }


class _FakeBilibiliClient:
    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def get(self, url, params):
        if "web-interface/view" in url:
            return _FakeResponse({"code": 0, "data": {"cid": 123}})
        return _FakeResponse(
            {
                "code": 0,
                "data": {
                    "dash": {
                        "audio": [
                            {
                                "baseUrl": (
                                    "https://example.test/audio.m4s"
                                    "?deadline=2000000000"
                                ),
                                "bandwidth": 128000,
                            }
                        ]
                    }
                },
            }
        )


class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload
