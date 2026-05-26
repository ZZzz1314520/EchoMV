from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    app_name: str = "EchoMV API"
    database_path: Path = Path(os.getenv("ECHOMV_DB_PATH", "data/echomv.sqlite3"))
    youtube_api_key: str | None = os.getenv("YOUTUBE_API_KEY") or None
    demo_stream_url: str = os.getenv(
        "ECHOMV_DEMO_STREAM_URL",
        "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
    )
    allow_experimental_resolve: bool = (
        os.getenv("ECHOMV_ALLOW_EXPERIMENTAL_RESOLVE", "").lower()
        in {"1", "true", "yes", "on"}
    )
    search_cache_ttl_seconds: int = int(os.getenv("ECHOMV_SEARCH_CACHE_TTL_SECONDS", "900"))
    enable_netease_lyrics: bool = (
        os.getenv("ECHOMV_ENABLE_NETEASE_LYRICS", "true").lower()
        in {"1", "true", "yes", "on"}
    )


settings = Settings()
