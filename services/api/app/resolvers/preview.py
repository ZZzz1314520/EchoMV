from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re

import httpx

from .base import MediaResolver
from ..models import ResolveRequest, ResolvedMedia
from ..music_metadata import clean_music_term, looks_like_video_uploader
from ..scoring import normalize_text


class NoPreviewFound(RuntimeError):
    pass


class PreviewResolver(MediaResolver):
    async def resolve(self, request: ResolveRequest) -> ResolvedMedia:
        terms = _candidate_terms(request)
        async with httpx.AsyncClient(timeout=8.0) as client:
            for country in ("CN", "US"):
                for term in terms:
                    preview = await _search_itunes_preview(client, term, country, request.duration)
                    if preview:
                        return preview

        raise NoPreviewFound(
            "No legal preview audio was found for this result. Open the source video page instead."
        )


async def _search_itunes_preview(
    client: httpx.AsyncClient,
    term: str,
    country: str,
    requested_duration: int | None,
) -> ResolvedMedia | None:
    response = await client.get(
        "https://itunes.apple.com/search",
        params={
            "term": term,
            "media": "music",
            "entity": "song",
            "limit": 12,
            "country": country,
        },
    )
    response.raise_for_status()
    payload = response.json()
    selected = _select_preview(payload.get("results") or [], term, requested_duration)
    if not selected:
        return None

    return ResolvedMedia(
        streamUrl=selected["previewUrl"],
        mimeType="audio/mp4",
        expiresAt=datetime.now(timezone.utc) + timedelta(days=7),
        source="itunes-preview",
        isExperimental=False,
        externalPageUrl=selected.get("trackViewUrl"),
        requestHeaders={},
        waveformPeaks=_synthetic_peaks(selected.get("trackName") or term),
    )


def _candidate_terms(request: ResolveRequest) -> list[str]:
    cleaned = clean_music_term(request.title)
    candidates = [cleaned]

    if request.artist and not looks_like_video_uploader(request.artist):
        candidates.insert(0, clean_music_term(f"{request.artist} {cleaned}"))

    return [term for index, term in enumerate(candidates) if term and term not in candidates[:index]]


_clean_music_term = clean_music_term


def _select_preview(
    results: list[dict],
    term: str,
    requested_duration: int | None,
) -> dict | None:
    scored: list[tuple[float, dict]] = []
    normalized_term = normalize_text(term)
    term_parts = {part for part in re.split(r"\s+", normalized_term) if len(part) > 1}

    for item in results:
        preview_url = item.get("previewUrl")
        if not preview_url:
            continue

        track = normalize_text(str(item.get("trackName") or ""))
        artist = normalize_text(str(item.get("artistName") or ""))
        haystack = f"{artist} {track}"
        score = 0.2

        if track and track in normalized_term:
            score += 0.35
        if normalized_term and normalized_term in haystack:
            score += 0.35
        score += min(0.3, sum(0.08 for part in term_parts if part in haystack))

        duration_ms = item.get("trackTimeMillis")
        if requested_duration and isinstance(duration_ms, int):
            diff = abs(duration_ms / 1000 - requested_duration)
            if diff <= 20:
                score += 0.12
            elif diff >= 90:
                score -= 0.08

        scored.append((score, item))

    if not scored:
        return None

    scored.sort(key=lambda value: value[0], reverse=True)
    return scored[0][1]


def _synthetic_peaks(seed: str) -> list[float]:
    base = sum(ord(char) for char in seed) or 1
    return [round(0.18 + ((base * (index + 7)) % 73) / 100, 2) for index in range(16)]
