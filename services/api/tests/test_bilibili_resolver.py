from datetime import datetime, timezone

from app.resolvers.bilibili import _expires_at, _select_audio_stream


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
