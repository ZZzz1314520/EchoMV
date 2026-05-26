from __future__ import annotations

from html import unescape
import re

from .scoring import normalize_text


NOISE_RE = re.compile(
    r"(?i)("
    r"official|music\s*video|lyric\s*video|mv|live|session|cover|remix|"
    r"4k|8k|hi-res|2160p|1080p|720p|"
    r"官方|高清|修复版|修复|完整版|版本|版|无损音质|无损|视听|循环歌曲|字幕|伴奏|现场|翻唱"
    r")"
)


def clean_music_term(title: str) -> str:
    value = unescape(unescape(title))
    value = re.sub(r"<[^>]+>", " ", value)
    value = re.sub(r"【[^】]*】|\[[^\]]*\]|\([^)]*\)|（[^）]*）", " ", value)
    value = NOISE_RE.sub(" ", value)
    value = re.sub(r"[-_:：｜|，,。·]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def looks_like_video_uploader(value: str) -> bool:
    normalized = normalize_text(value)
    return any(token in normalized for token in ("echo", "music", "mv", "official", "频道")) or "_" in value


def infer_track_and_artist(title: str, artist: str | None = None) -> tuple[str, str | None]:
    cleaned_artist = artist if artist and not looks_like_video_uploader(artist) else None
    raw = unescape(unescape(title))
    raw = re.sub(r"<[^>]+>", " ", raw)
    raw = re.sub(r"【[^】]*】|\[[^\]]*\]|\([^)]*\)|（[^）]*）", " ", raw)
    raw = NOISE_RE.sub(" ", raw)
    raw = re.sub(r"\s+", " ", raw).strip()

    separators = (" - ", " – ", " — ", "-", "｜", "|", "：", ":")
    for separator in separators:
        if separator in raw:
            left, right = [part.strip() for part in raw.split(separator, 1)]
            left = clean_music_term(left)
            right = clean_music_term(right)
            if left and right:
                return right, cleaned_artist or left

    cleaned = clean_music_term(raw)
    if cleaned_artist and cleaned.startswith(cleaned_artist):
        cleaned = cleaned[len(cleaned_artist) :].strip()
    return cleaned or title.strip(), cleaned_artist
