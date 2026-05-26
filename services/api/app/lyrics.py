from __future__ import annotations

from collections.abc import Mapping
import re
from urllib.parse import urlencode

import httpx

from .config import settings
from .models import LyricLine, LyricsResponse
from .music_metadata import infer_track_and_artist
from .scoring import normalize_text


TIMESTAMP_RE = re.compile(r"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]")
USER_AGENT = "EchoMV/0.1 personal prototype"
NETEASE_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0 Safari/537.36"
    ),
    "Referer": "https://music.163.com/",
}


def lyrics_cache_key(title: str, artist: str | None, duration: int | None) -> str:
    track_name, artist_name = infer_track_and_artist(title, artist)
    return "|".join(
        [
            normalize_text(track_name),
            normalize_text(artist_name or ""),
            str(duration or ""),
        ]
    )


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


def _parse_translated_lrc(raw: str) -> dict[int, str]:
    return {line.time_ms: line.text for line in parse_lrc(raw)}


async def fetch_lyrics(title: str, artist: str | None, duration: int | None) -> LyricsResponse:
    track_name, artist_name = infer_track_and_artist(title, artist)

    async with httpx.AsyncClient(timeout=8.0) as client:
        try:
            lrclib = await _fetch_lrclib_lyrics(client, track_name, artist_name, duration)
        except Exception:
            lrclib = None
        if lrclib:
            return lrclib

        if settings.enable_netease_lyrics:
            try:
                netease = await _fetch_netease_lyrics(client, track_name, artist_name, duration)
            except Exception:
                netease = None
            if netease:
                return netease

    return demo_lyrics(track_name, artist_name, "未找到同步歌词")


async def fetch_lrclib_lyrics(title: str, artist: str | None, duration: int | None) -> LyricsResponse:
    track_name, artist_name = infer_track_and_artist(title, artist)
    async with httpx.AsyncClient(timeout=8.0) as client:
        lyrics = await _fetch_lrclib_lyrics(client, track_name, artist_name, duration)
    return lyrics or demo_lyrics(track_name, artist_name, "未找到同步歌词")


async def _fetch_lrclib_lyrics(
    client: httpx.AsyncClient,
    track_name: str,
    artist_name: str | None,
    duration: int | None,
) -> LyricsResponse | None:
    params: dict[str, str | int] = {"track_name": track_name}
    if artist_name:
        params["artist_name"] = artist_name
    if duration:
        params["duration"] = duration

    try:
        response = await _lrclib_get(client, params)
        if response.status_code == 404 and "duration" in params:
            relaxed = dict(params)
            relaxed.pop("duration", None)
            response = await _lrclib_get(client, relaxed)
        if response.status_code == 404:
            response = await _lrclib_search(client, track_name, artist_name)
        if response.status_code == 404:
            return None
        response.raise_for_status()
    except httpx.HTTPError:
        return None

    payload = response.json()
    if isinstance(payload, list):
        candidates = payload
    else:
        candidates = [payload]

    for candidate in candidates:
        lyrics = _lyrics_from_lrclib_payload(candidate, track_name, artist_name)
        if lyrics.lines:
            return lyrics
    return None


def _lyrics_from_lrclib_payload(
    payload: Mapping[str, object],
    track_name: str,
    artist_name: str | None,
) -> LyricsResponse:
    synced = str(payload.get("syncedLyrics") or "")
    plain = str(payload.get("plainLyrics") or "")
    parsed = parse_lrc(synced)

    if not parsed and plain:
        parsed = [
            LyricLine(timeMs=index * 4000, text=line.strip())
            for index, line in enumerate(plain.splitlines())
            if line.strip()
        ]

    return LyricsResponse(
        title=str(payload.get("trackName") or track_name),
        artist=str(payload.get("artistName") or artist_name) if payload.get("artistName") or artist_name else None,
        confidence=0.86 if parsed and synced else 0.45,
        source="lrclib",
        lines=parsed,
    )


async def _lrclib_get(client: httpx.AsyncClient, params: dict[str, str | int]) -> httpx.Response:
    url = f"https://lrclib.net/api/get?{urlencode(params)}"
    return await client.get(url, headers={"User-Agent": USER_AGENT})


async def _lrclib_search(
    client: httpx.AsyncClient,
    track_name: str,
    artist_name: str | None,
) -> httpx.Response:
    headers = {"User-Agent": USER_AGENT}
    query = f"{artist_name or ''} {track_name}".strip()
    response = await client.get("https://lrclib.net/api/search", params={"q": query}, headers=headers)
    if response.status_code == 200 and response.json():
        return response
    return await client.get(
        "https://lrclib.net/api/search",
        params={"track_name": track_name, **({"artist_name": artist_name} if artist_name else {})},
        headers=headers,
    )


async def _fetch_netease_lyrics(
    client: httpx.AsyncClient,
    track_name: str,
    artist_name: str | None,
    duration: int | None,
) -> LyricsResponse | None:
    try:
        song = await _search_netease_song(client, track_name, artist_name, duration)
        if not song:
            return None
        response = await client.get(
            "https://music.163.com/api/song/lyric",
            params={"id": song["id"], "lv": 1, "kv": 1, "tv": -1},
            headers=NETEASE_HEADERS,
        )
        response.raise_for_status()
    except httpx.HTTPError:
        return None

    payload = response.json()
    raw_lrc = ((payload.get("lrc") or {}).get("lyric") or "").strip()
    lines = parse_lrc(raw_lrc)
    if not lines:
        return None

    translations = _parse_translated_lrc(((payload.get("tlyric") or {}).get("lyric") or "").strip())
    if translations:
        lines = [
            LyricLine(
                timeMs=line.time_ms,
                text=line.text,
                translatedText=translations.get(line.time_ms),
            )
            for line in lines
        ]

    return LyricsResponse(
        title=str(song.get("name") or track_name),
        artist=str(song.get("artist") or artist_name) if song.get("artist") or artist_name else None,
        confidence=0.82,
        source="netease",
        lines=lines,
    )


async def _search_netease_song(
    client: httpx.AsyncClient,
    track_name: str,
    artist_name: str | None,
    duration: int | None,
) -> dict[str, object] | None:
    query = f"{artist_name or ''} {track_name}".strip()
    response = await client.get(
        "https://music.163.com/api/search/get/web",
        params={"csrf_token": "", "s": query, "type": 1, "offset": 0, "total": "true", "limit": 8},
        headers=NETEASE_HEADERS,
    )
    response.raise_for_status()
    songs = ((response.json().get("result") or {}).get("songs") or [])
    if not songs:
        return None

    scored: list[tuple[float, dict[str, object]]] = []
    normalized_track = normalize_text(track_name)
    normalized_artist = normalize_text(artist_name or "")
    for raw_song in songs:
        if not isinstance(raw_song, dict):
            continue
        song_name = str(raw_song.get("name") or "")
        artists = raw_song.get("artists") or []
        artist_text = " ".join(
            str(item.get("name") or "") for item in artists if isinstance(item, dict)
        )
        haystack = normalize_text(f"{artist_text} {song_name}")
        score = 0.0
        if normalized_track and normalized_track in normalize_text(song_name):
            score += 0.5
        if normalized_artist and normalized_artist in normalize_text(artist_text):
            score += 0.35
        if normalized_track and normalized_track in haystack:
            score += 0.2

        song_duration = raw_song.get("duration")
        if duration and isinstance(song_duration, int):
            diff = abs(song_duration / 1000 - duration)
            if diff <= 20:
                score += 0.15
            elif diff >= 90:
                score -= 0.1

        scored.append(
            (
                score,
                {
                    "id": raw_song.get("id"),
                    "name": song_name,
                    "artist": artist_text or None,
                },
            )
        )

    scored = [item for item in scored if item[1].get("id")]
    if not scored:
        return None
    scored.sort(key=lambda item: item[0], reverse=True)
    return scored[0][1]


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
