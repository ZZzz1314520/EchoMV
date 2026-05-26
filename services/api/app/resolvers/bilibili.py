from __future__ import annotations

from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlparse

import httpx

from .base import MediaResolver
from .preview import NoPreviewFound
from ..models import ResolveRequest, ResolvedMedia


BROWSER_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0 Safari/537.36"
)


class BilibiliAudioResolver(MediaResolver):
    async def resolve(self, request: ResolveRequest) -> ResolvedMedia:
        if request.source != "bilibili" or not request.video_id.startswith("BV"):
            raise NoPreviewFound("Only public Bilibili BV videos are supported by this resolver.")

        page_url = request.page_url or f"https://www.bilibili.com/video/{request.video_id}"
        headers = {
            "User-Agent": BROWSER_USER_AGENT,
            "Referer": page_url,
            "Accept": "application/json, text/plain, */*",
        }
        async with httpx.AsyncClient(timeout=12.0, headers=headers) as client:
            view_response = await client.get(
                "https://api.bilibili.com/x/web-interface/view",
                params={"bvid": request.video_id},
            )
            view_response.raise_for_status()
            view_payload = view_response.json()
            if view_payload.get("code") != 0:
                raise NoPreviewFound(f"Bilibili video metadata failed: {view_payload.get('message')}")

            cid = (view_payload.get("data") or {}).get("cid")
            if not cid:
                raise NoPreviewFound("Bilibili video did not expose a playable cid.")

            play_response = await client.get(
                "https://api.bilibili.com/x/player/playurl",
                params={
                    "bvid": request.video_id,
                    "cid": cid,
                    "qn": 64,
                    "fnval": 16,
                    "fourk": 1,
                },
            )
            play_response.raise_for_status()

        play_payload = play_response.json()
        if play_payload.get("code") != 0:
            raise NoPreviewFound(f"Bilibili playurl failed: {play_payload.get('message')}")

        audio = _select_audio_stream((play_payload.get("data") or {}).get("dash") or {})
        if not audio:
            raise NoPreviewFound("Bilibili did not return a public DASH audio stream.")

        stream_url = audio.get("baseUrl") or audio.get("base_url")
        if not stream_url:
            raise NoPreviewFound("Bilibili audio stream URL was empty.")

        return ResolvedMedia(
            streamUrl=stream_url,
            mimeType=audio.get("mimeType") or audio.get("mime_type") or "audio/mp4",
            expiresAt=_expires_at(stream_url),
            source="bilibili-audio",
            isExperimental=True,
            externalPageUrl=page_url,
            requestHeaders={
                "User-Agent": BROWSER_USER_AGENT,
                "Referer": page_url,
            },
            waveformPeaks=_synthetic_peaks(request.video_id),
        )


def _select_audio_stream(dash: dict) -> dict | None:
    streams = [item for item in dash.get("audio") or [] if item.get("baseUrl") or item.get("base_url")]
    if not streams:
        return None
    return sorted(streams, key=lambda item: item.get("bandwidth") or 0, reverse=True)[0]


def _expires_at(stream_url: str) -> datetime:
    query = parse_qs(urlparse(stream_url).query)
    deadline = (query.get("deadline") or [None])[0]
    if deadline and deadline.isdigit():
        return datetime.fromtimestamp(int(deadline), timezone.utc)
    return datetime.now(timezone.utc) + timedelta(hours=6)


def _synthetic_peaks(seed: str) -> list[float]:
    base = sum(ord(char) for char in seed) or 1
    return [round(0.2 + ((base * (index + 11)) % 68) / 100, 2) for index in range(16)]
