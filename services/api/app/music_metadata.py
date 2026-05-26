from __future__ import annotations

from html import unescape
import re

from .scoring import normalize_text


BRACKET_RE = re.compile(r"【[^】]*】|\[[^\]]*\]|\([^)]*\)|（[^）]*）")
NOISE_RE = re.compile(
    r"(?i)("
    r"official|music\s*video|lyric\s*video|lyrics?|mv|live|session|cover|remix|"
    r"karaoke|伴奏|instrumental|"
    r"4k|8k|hi-res|2160p|1080p|720p|"
    r"官方|高清|修复版?|完整版?|版本|无损音质|无损|视听|循环歌曲|"
    r"字幕|伴奏|现场|翻唱|动态歌词|歌词版|纯享|合集"
    r")"
)
SEPARATOR_RE = re.compile(r"\s*[-_:：|｜·•]+\s*")


def clean_music_term(title: str) -> str:
    value = unescape(unescape(title))
    value = re.sub(r"<[^>]+>", " ", value)
    value = BRACKET_RE.sub(" ", value)
    value = NOISE_RE.sub(" ", value)
    value = SEPARATOR_RE.sub(" ", value)
    return re.sub(r"\s+", " ", value).strip()


def looks_like_video_uploader(value: str) -> bool:
    normalized = normalize_text(value)
    uploader_tokens = (
        "echo",
        "music",
        "mv",
        "official",
        "channel",
        "频道",
        "音乐",
        "视频",
        "搬运",
        "字幕",
    )
    return any(token in normalized for token in uploader_tokens) or "_" in value


def infer_track_and_artist(title: str, artist: str | None = None) -> tuple[str, str | None]:
    cleaned_artist = artist.strip() if artist and not looks_like_video_uploader(artist) else None
    raw = unescape(unescape(title))
    raw = re.sub(r"<[^>]+>", " ", raw)
    raw = BRACKET_RE.sub(" ", raw)
    raw = NOISE_RE.sub(" ", raw)
    raw = re.sub(r"\s+", " ", raw).strip()

    for separator in (" - ", " — ", " – ", "-", "｜", "|", "：", ":"):
        if separator in raw:
            left, right = [part.strip() for part in raw.split(separator, 1)]
            left = clean_music_term(left)
            right = clean_music_term(right)
            if left and right:
                return right, cleaned_artist or left

    cleaned = clean_music_term(raw)
    if cleaned_artist and normalize_text(cleaned).startswith(normalize_text(cleaned_artist)):
        cleaned = cleaned[len(cleaned_artist) :].strip()
    return cleaned or title.strip(), cleaned_artist
