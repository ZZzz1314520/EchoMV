from fastapi.testclient import TestClient

from app.main import app


def test_search_resolve_and_lyrics_contracts():
    client = TestClient(app)

    search = client.get("/api/search", params={"q": "晴天", "sources": "youtube"})
    assert search.status_code == 200
    results = search.json()
    assert results
    assert {"id", "source", "videoId", "title", "pageUrl", "confidence", "tags"} <= set(results[0])

    resolve = client.post("/api/resolve", json=results[0])
    assert resolve.status_code == 200
    media = resolve.json()
    assert {"streamUrl", "mimeType", "expiresAt", "source", "isExperimental"} <= set(media)

    lyrics = client.get("/api/lyrics", params={"title": results[0]["title"]})
    assert lyrics.status_code == 200
    payload = lyrics.json()
    assert {"title", "confidence", "source", "lines"} <= set(payload)
    assert payload["source"] in {"lrclib", "netease", "demo"}
