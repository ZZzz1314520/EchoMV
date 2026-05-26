from __future__ import annotations

from hashlib import sha1
from urllib.parse import quote_plus, urlencode

from .base import VideoSourceProvider
from ..config import settings
from ..models import SearchResult
from ..scoring import score_result


class YouTubeProvider(VideoSourceProvider):
    source = "youtube"

    async def search(self, query: str, limit: int = 8) -> list[SearchResult]:
        if not settings.youtube_api_key:
            return self._demo_results(query, limit)

        import httpx

        params = {
            "part": "snippet",
            "type": "video",
            "maxResults": min(limit, 10),
            "q": f"{query} official mv",
            "key": settings.youtube_api_key,
        }
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get("https://www.googleapis.com/youtube/v3/search", params=params)
        response.raise_for_status()
        payload = response.json()

        results: list[SearchResult] = []
        for raw in payload.get("items", []):
            snippet = raw.get("snippet") or {}
            video_id = (raw.get("id") or {}).get("videoId")
            if not video_id:
                continue
            title = snippet.get("title") or query
            confidence, tags = score_result(query, title)
            thumb = ((snippet.get("thumbnails") or {}).get("high") or {}).get("url")
            results.append(
                SearchResult(
                    id=f"youtube:{video_id}",
                    source="youtube",
                    videoId=video_id,
                    title=title,
                    artist=snippet.get("channelTitle"),
                    duration=None,
                    thumbnailUrl=thumb,
                    pageUrl=f"https://www.youtube.com/watch?{urlencode({'v': video_id})}",
                    confidence=confidence,
                    tags=tags,
                )
            )
        return results

    def _demo_results(self, query: str, limit: int) -> list[SearchResult]:
        templates = [
            ("official-mv", f"{query} - Official Music Video", "Official Artist Channel", 238),
            ("lyric-video", f"{query} - Lyric Video", "EchoMV Demo", 226),
            ("live", f"{query} - Live Session", "EchoMV Demo Stage", 312),
        ]
        results: list[SearchResult] = []
        for slug, title, artist, duration in templates[:limit]:
            confidence, tags = score_result(query, title, duration)
            suffix = sha1(query.encode("utf-8")).hexdigest()[:10]
            video_id = f"demo-{slug}-{suffix}"
            results.append(
                SearchResult(
                    id=f"youtube:{video_id}",
                    source="youtube",
                    videoId=video_id,
                    title=title,
                    artist=artist,
                    duration=duration,
                    thumbnailUrl=f"https://picsum.photos/seed/echomv-{slug}/640/360",
                    pageUrl=f"https://www.youtube.com/results?search_query={quote_plus(query)}",
                    confidence=confidence,
                    tags=tags + ["demo"],
                )
            )
        return results
