from __future__ import annotations

from html import unescape
import re
from urllib.parse import quote_plus

from .base import VideoSourceProvider
from ..models import SearchResult
from ..scoring import score_result


class BilibiliProvider(VideoSourceProvider):
    source = "bilibili"

    async def search(self, query: str, limit: int = 8) -> list[SearchResult]:
        import httpx

        url = (
            "https://api.bilibili.com/x/web-interface/search/type"
            f"?search_type=video&keyword={quote_plus(query)}&page=1"
        )
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0 Safari/537.36"
            ),
            "Referer": "https://search.bilibili.com/",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        }
        async with httpx.AsyncClient(timeout=8.0, headers=headers) as client:
            try:
                response = await client.get(url)
                response.raise_for_status()
            except httpx.HTTPStatusError:
                return await _search_html(client, query, limit)

        payload = response.json()
        if payload.get("code") != 0:
            return await _search_html(client, query, limit)

        data = payload.get("data", {})
        raw_results = data.get("result") or []
        results: list[SearchResult] = []
        for raw in raw_results:
            if len(results) >= limit:
                break
            bvid = raw.get("bvid")
            if not isinstance(bvid, str) or not bvid.startswith("BV"):
                continue
            title = _strip_html(raw.get("title") or "")
            duration = _parse_duration(raw.get("duration"))
            confidence, tags = score_result(query, title, duration)
            pic = raw.get("pic") or ""
            thumbnail = f"https:{pic}" if pic.startswith("//") else pic or None
            results.append(
                SearchResult(
                    id=f"bilibili:{bvid}",
                    source="bilibili",
                    videoId=bvid,
                    title=title,
                    artist=raw.get("author"),
                    duration=duration,
                    thumbnailUrl=thumbnail,
                    pageUrl=raw.get("arcurl") or f"https://www.bilibili.com/video/{bvid}",
                    confidence=confidence,
                    tags=tags,
                )
            )
        if not results:
            return await _search_html(client, query, limit)
        return results


def _strip_html(value: str) -> str:
    decoded = unescape(unescape(value))
    return re.sub(r"<[^>]+>", "", decoded).strip()


async def _search_html(client, query: str, limit: int) -> list[SearchResult]:
    response = await client.get(f"https://search.bilibili.com/all?keyword={quote_plus(query)}")
    response.raise_for_status()
    cards = response.text.split("bili-video-card__wrap")
    results: list[SearchResult] = []
    seen: set[str] = set()

    for card in cards:
        if len(results) >= limit:
            break

        video_match = re.search(r"www\.bilibili\.com/video/(BV[0-9A-Za-z]+)", card)
        if not video_match:
            continue
        bvid = video_match.group(1)
        if bvid in seen:
            continue
        seen.add(bvid)

        title_match = re.search(r'bili-video-card__info--tit"[^>]*title="([^"]+)"', card)
        if not title_match:
            title_match = re.search(r'<img[^>]+alt="([^"]+)"', card)
        title = _strip_html(title_match.group(1) if title_match else f"{query} - Bilibili")

        author_match = re.search(r'bili-video-card__info--author"[^>]*>([^<]+)', card)
        duration_match = re.search(r'bili-video-card__stats__duration"[^>]*>([^<]+)', card)
        image_match = re.search(r'<img[^>]+src="([^"]+)"', card)
        image = unescape(image_match.group(1)) if image_match else None
        thumbnail = f"https:{image}" if image and image.startswith("//") else image
        duration = _parse_duration(duration_match.group(1).strip() if duration_match else None)
        confidence, tags = score_result(query, title, duration)

        results.append(
            SearchResult(
                id=f"bilibili:{bvid}",
                source="bilibili",
                videoId=bvid,
                title=title,
                artist=_strip_html(author_match.group(1)) if author_match else None,
                duration=duration,
                thumbnailUrl=thumbnail,
                pageUrl=f"https://www.bilibili.com/video/{bvid}",
                confidence=confidence,
                tags=tags + ["html-fallback"],
            )
        )

    return results


def _parse_duration(value: object) -> int | None:
    if not value:
        return None
    if isinstance(value, int):
        return value
    parts = str(value).split(":")
    try:
        total = 0
        for part in parts:
            total = total * 60 + int(part)
        return total
    except ValueError:
        return None
