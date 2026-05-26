from __future__ import annotations

from .base import MediaResolver
from ..config import settings
from ..models import ResolveRequest, ResolvedMedia


class SafeDemoResolver(MediaResolver):
    async def resolve(self, request: ResolveRequest) -> ResolvedMedia:
        return ResolvedMedia.demo(settings.demo_stream_url, request.page_url)
