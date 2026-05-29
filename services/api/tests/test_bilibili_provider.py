import asyncio

from app.providers import bilibili
from app.providers.bilibili import BilibiliProvider


def test_search_html_fallback_uses_open_client(monkeypatch):
    monkeypatch.setattr(bilibili.httpx, "AsyncClient", _FallbackClient)

    results = asyncio.run(BilibiliProvider().search("清明雨上", limit=3))

    assert len(results) == 1
    assert results[0].video_id == "BV1abcDEF23"
    assert results[0].title == "清明雨上 官方MV"
    assert "html-fallback" in results[0].tags


class _FallbackClient:
    def __init__(self, *args, **kwargs):
        self.closed = False

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        self.closed = True
        return False

    async def get(self, url):
        if self.closed:
            raise RuntimeError("client is closed")
        if "web-interface/search/type" in url:
            return _ApiResponse({"code": -1})
        return _HtmlResponse(
            """
            bili-video-card__wrap
            <a href="https://www.bilibili.com/video/BV1noise123"></a>
            <div class="bili-video-card__info--tit" title="许嵩跨年晚会"></div>
            <span class="bili-video-card__stats__duration">4:05</span>
            bili-video-card__wrap
            <a href="https://www.bilibili.com/video/BV1abcDEF23"></a>
            <div class="bili-video-card__info--tit" title="清明雨上 官方MV"></div>
            <span class="bili-video-card__info--author">许嵩</span>
            <span class="bili-video-card__stats__duration">4:12</span>
            <img src="//example.test/cover.jpg" />
            """
        )


class _ApiResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


class _HtmlResponse:
    def __init__(self, text):
        self.text = text

    def raise_for_status(self):
        pass
