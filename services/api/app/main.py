from __future__ import annotations

import asyncio
from typing import Annotated

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .lyrics import demo_lyrics, fetch_lrclib_lyrics
from .models import (
    FavoriteCreate,
    HistoryCreate,
    LyricsResponse,
    ResolveRequest,
    ResolvedMedia,
    SearchResult,
)
from .providers import BilibiliProvider, VideoSourceProvider, YouTubeProvider
from .resolvers import BilibiliAudioResolver, NoPreviewFound, PreviewResolver
from .storage import Store

app = FastAPI(title=settings.app_name)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

store = Store(settings.database_path)
providers: dict[str, VideoSourceProvider] = {
    "bilibili": BilibiliProvider(),
    "youtube": YouTubeProvider(),
}
bilibili_resolver = BilibiliAudioResolver()
preview_resolver = PreviewResolver()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "app": settings.app_name}


@app.get("/api/search", response_model=list[SearchResult])
async def search(
    q: Annotated[str, Query(min_length=1)],
    sources: str = "bilibili,youtube",
) -> list[SearchResult]:
    requested = [source.strip() for source in sources.split(",") if source.strip()]
    cache_key = f"{q}|{','.join(sorted(requested))}"
    cached = store.read_search_cache(cache_key, settings.search_cache_ttl_seconds)
    if cached and _has_real_results(cached):
        return cached

    tasks = [providers[source].search(q) for source in requested if source in providers]
    if not tasks:
        raise HTTPException(status_code=400, detail="No supported video sources requested")

    settled = await asyncio.gather(*tasks, return_exceptions=True)
    results: list[SearchResult] = []
    for value in settled:
        if isinstance(value, Exception):
            continue
        results.extend(value)

    results.sort(key=lambda item: ("demo" in item.tags, -item.confidence))
    if _has_real_results(results):
        store.write_search_cache(cache_key, results)
    return results


def _has_real_results(results: list[SearchResult]) -> bool:
    return any("demo" not in item.tags for item in results)


@app.post("/api/resolve", response_model=ResolvedMedia)
async def resolve(request: ResolveRequest) -> ResolvedMedia:
    try:
        if request.source == "bilibili":
            return await bilibili_resolver.resolve(request)
        return await preview_resolver.resolve(request)
    except NoPreviewFound as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.get("/api/lyrics", response_model=LyricsResponse)
async def lyrics(title: str, artist: str | None = None, duration: int | None = None) -> LyricsResponse:
    try:
        return await fetch_lrclib_lyrics(title, artist, duration)
    except Exception:
        return demo_lyrics(title, artist)


@app.post("/api/history")
def create_history(payload: HistoryCreate) -> dict[str, bool]:
    store.save_history(payload.item, payload.played_at)
    return {"ok": True}


@app.get("/api/history", response_model=list[SearchResult])
def get_history() -> list[SearchResult]:
    return store.list_history()


@app.post("/api/favorites")
def create_favorite(payload: FavoriteCreate) -> dict[str, bool]:
    store.save_favorite(payload.item)
    return {"ok": True}


@app.get("/api/favorites", response_model=list[SearchResult])
def get_favorites() -> list[SearchResult]:
    return store.list_favorites()


@app.delete("/api/favorites/{item_id}")
def delete_favorite(item_id: str) -> dict[str, bool]:
    store.remove_favorite(item_id)
    return {"ok": True}
