from __future__ import annotations

import re
from unicodedata import normalize


POSITIVE_KEYWORDS = {
    "official": 0.18,
    "mv": 0.16,
    "music video": 0.16,
    "官方": 0.2,
    "官方mv": 0.22,
    "高清": 0.06,
    "完整版": 0.06,
}

NEGATIVE_KEYWORDS = {
    "cover": -0.18,
    "翻唱": -0.22,
    "伴奏": -0.25,
    "karaoke": -0.22,
    "reaction": -0.24,
    "remix": -0.1,
    "现场": -0.08,
    "live": -0.08,
}


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", normalize("NFKC", value).casefold()).strip()


def score_result(query: str, title: str, duration: int | None = None) -> tuple[float, list[str]]:
    normalized_query = normalize_text(query)
    normalized_title = normalize_text(title)
    score = 0.35
    tags: list[str] = []

    if normalized_query and normalized_query in normalized_title:
        score += 0.24
        tags.append("query-match")
    else:
        query_terms = {part for part in re.split(r"[\s\-_/]+", normalized_query) if part}
        if query_terms:
            matched = sum(1 for part in query_terms if part in normalized_title)
            score += min(0.18, matched * 0.06)
            if matched:
                tags.append("partial-match")

    for keyword, weight in POSITIVE_KEYWORDS.items():
        if keyword in normalized_title:
            score += weight
            tags.append(keyword)

    for keyword, weight in NEGATIVE_KEYWORDS.items():
        if keyword in normalized_title:
            score += weight
            tags.append(keyword)

    if duration is not None:
        if 120 <= duration <= 420:
            score += 0.08
            tags.append("song-length")
        elif duration < 75 or duration > 900:
            score -= 0.12
            tags.append("duration-risk")

    return max(0.0, min(1.0, round(score, 3))), tags
