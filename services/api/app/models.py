from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Literal

from pydantic import BaseModel, Field, HttpUrl


VideoSource = Literal["bilibili", "youtube", "demo"]


class SearchResult(BaseModel):
    id: str
    source: VideoSource
    video_id: str = Field(alias="videoId")
    title: str
    artist: str | None = None
    duration: int | None = None
    thumbnail_url: str | None = Field(default=None, alias="thumbnailUrl")
    page_url: str = Field(alias="pageUrl")
    confidence: float = 0.0
    tags: list[str] = Field(default_factory=list)

    model_config = {"populate_by_name": True}


class ResolveRequest(BaseModel):
    source: VideoSource
    video_id: str = Field(alias="videoId")
    title: str
    artist: str | None = None
    duration: int | None = None
    page_url: str = Field(alias="pageUrl")

    model_config = {"populate_by_name": True}


class ResolvedMedia(BaseModel):
    stream_url: str = Field(alias="streamUrl")
    mime_type: str = Field(alias="mimeType")
    expires_at: datetime = Field(alias="expiresAt")
    source: str
    is_experimental: bool = Field(alias="isExperimental")
    waveform_peaks: list[float] | None = Field(default=None, alias="waveformPeaks")
    external_page_url: str | None = Field(default=None, alias="externalPageUrl")
    request_headers: dict[str, str] = Field(default_factory=dict, alias="requestHeaders")

    model_config = {"populate_by_name": True}

    @staticmethod
    def demo(stream_url: str, page_url: str) -> "ResolvedMedia":
        return ResolvedMedia(
            streamUrl=stream_url,
            mimeType="audio/mpeg",
            expiresAt=datetime.now(timezone.utc) + timedelta(hours=6),
            source="demo",
            isExperimental=False,
            externalPageUrl=page_url,
            requestHeaders={},
            waveformPeaks=[
                0.16,
                0.38,
                0.72,
                0.44,
                0.62,
                0.91,
                0.57,
                0.33,
                0.75,
                0.49,
                0.84,
                0.27,
            ],
        )


class LyricLine(BaseModel):
    time_ms: int = Field(alias="timeMs")
    text: str
    translated_text: str | None = Field(default=None, alias="translatedText")

    model_config = {"populate_by_name": True}


class LyricsResponse(BaseModel):
    title: str
    artist: str | None = None
    confidence: float
    source: str
    lines: list[LyricLine]


class HistoryCreate(BaseModel):
    item: SearchResult
    played_at: datetime | None = Field(default=None, alias="playedAt")

    model_config = {"populate_by_name": True}


class FavoriteCreate(BaseModel):
    item: SearchResult
