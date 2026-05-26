from __future__ import annotations

import re
from urllib.parse import urlencode

from .models import LyricLine, LyricsResponse
from .music_metadata import infer_track_and_artist


TIMESTAMP_RE = re.compile(r"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]")


def parse_lrc(raw: str) -> list[LyricLine]:
    lines: list[LyricLine] = []
    for raw_line in raw.splitlines():
        matches = list(TIMESTAMP_RE.finditer(raw_line))
        if not matches:
            continue

        text = TIMESTAMP_RE.sub("", raw_line).strip()
        if not text:
            continue

        for match in matches:
            minutes = int(match.group(1))
            seconds = int(match.group(2))
            fraction = match.group(3) or "0"
            millis = int(fraction.ljust(3, "0")[:3])
            lines.append(LyricLine(timeMs=minutes * 60_000 + seconds * 1000 + millis, text=text))

    return sorted(lines, key=lambda line: line.time_ms)


async def fetch_lrclib_lyrics(title: str, artist: str | None, duration: int | None) -> LyricsResponse:
    import httpx

    track_name, artist_name = infer_track_and_artist(title, artist)
    params: dict[str, str | int] = {"track_name": track_name}
    if artist_name:
        params["artist_name"] = artist_name
    if duration:
        params["duration"] = duration

    async with httpx.AsyncClient(timeout=8.0) as client:
        response = await _lrclib_get(client, params)
        if response.status_code == 404 and "duration" in params:
            relaxed = dict(params)
            relaxed.pop("duration", None)
            response = await _lrclib_get(client, relaxed)
        if response.status_code == 404:
            response = await _lrclib_search(client, track_name, artist_name)

    if response.status_code == 404:
        return demo_lyrics(track_name, artist_name, "未找到同步歌词")

    response.raise_for_status()
    payload = response.json()
    if isinstance(payload, list):
        payload = payload[0] if payload else {}

    synced = payload.get("syncedLyrics") or ""
    plain = payload.get("plainLyrics") or ""
    parsed = parse_lrc(synced)

    if not parsed and plain:
        parsed = [
            LyricLine(timeMs=index * 4000, text=line.strip())
            for index, line in enumerate(plain.splitlines())
            if line.strip()
        ]

    return LyricsResponse(
        title=payload.get("trackName") or track_name,
        artist=payload.get("artistName") or artist_name,
        confidence=0.86 if parsed and synced else 0.45,
        source="lrclib",
        lines=parsed or demo_lyrics(track_name, artist_name, "未找到同步歌词").lines,
    )


async def _lrclib_get(client, params: dict[str, str | int]):
    url = f"https://lrclib.net/api/get?{urlencode(params)}"
    return await client.get(url, headers={"User-Agent": "EchoMV/0.1 personal prototype"})


async def _lrclib_search(client, track_name: str, artist_name: str | None):
    headers = {"User-Agent": "EchoMV/0.1 personal prototype"}
    query = f"{artist_name or ''} {track_name}".strip()
    response = await client.get("https://lrclib.net/api/search", params={"q": query}, headers=headers)
    if response.status_code == 200 and response.json():
        return response
    return await client.get(
        "https://lrclib.net/api/search",
        params={"track_name": track_name, **({"artist_name": artist_name} if artist_name else {})},
        headers=headers,
    )


def demo_lyrics(title: str, artist: str | None, message: str | None = None) -> LyricsResponse:
    sample = [
        (0, "按下播放，EchoMV 会在这里同步歌词"),
        (5500, message or f"正在为《{title}》寻找匹配歌词"),
        (11000, "可以用偏移按钮微调每一行的时间"),
        (16500, "找到准确版本后，歌词会跟着音乐滚动"),
    ]
    return LyricsResponse(
        title=title,
        artist=artist,
        confidence=0.2,
        source="demo",
        lines=[LyricLine(timeMs=time_ms, text=text) for time_ms, text in sample],
    )
