from app.models import ResolveRequest
from app.resolvers.preview import _candidate_terms, _clean_music_term, _select_preview


def test_clean_music_term_removes_video_noise():
    assert _clean_music_term("【4K修复】周杰伦 - 晴天MV 2160P修复版") == "周杰伦 晴天"


def test_candidate_terms_ignores_bilibili_uploader_names():
    request = ResolveRequest(
        source="bilibili",
        videoId="BV1",
        title="【4K修复】周杰伦 - 晴天MV 2160P修复版",
        artist="zyl2012_音乐无限",
        pageUrl="https://www.bilibili.com/video/BV1",
    )

    assert _candidate_terms(request) == ["周杰伦 晴天"]


def test_select_preview_prefers_matching_track_with_preview():
    selected = _select_preview(
        [
            {"artistName": "Someone", "trackName": "Sunny Day Piano", "previewUrl": "a"},
            {"artistName": "周杰伦", "trackName": "晴天", "previewUrl": "b", "trackTimeMillis": 250000},
        ],
        "周杰伦 晴天",
        250,
    )

    assert selected["previewUrl"] == "b"
