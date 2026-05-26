from __future__ import annotations

from abc import ABC, abstractmethod

from ..models import ResolveRequest, ResolvedMedia


class MediaResolver(ABC):
    @abstractmethod
    async def resolve(self, request: ResolveRequest) -> ResolvedMedia:
        raise NotImplementedError
