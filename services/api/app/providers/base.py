from __future__ import annotations

from abc import ABC, abstractmethod

from ..models import SearchResult


class VideoSourceProvider(ABC):
    source: str

    @abstractmethod
    async def search(self, query: str, limit: int = 8) -> list[SearchResult]:
        raise NotImplementedError
