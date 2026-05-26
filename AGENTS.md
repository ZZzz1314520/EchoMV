# AGENTS.md

EchoMV is a personal prototype for a cross-platform MV-driven music player. The
repository has two main parts:

- `services/api`: Python FastAPI backend for video search aggregation, lyric
  lookup, media resolution contracts, favorites, history, and search caching.
- `apps/echomv_flutter`: Flutter client for Windows and Android, using Riverpod,
  Dio, shared preferences, and media_kit audio playback.

## Project Boundaries

- Keep the project scoped to a personal prototype. Do not add DRM bypassing,
  member-only content bypassing, bulk downloading, redistribution workflows, or
  extraction features that turn third-party videos into downloadable media.
- The resolver design intentionally prefers legal preview audio. YouTube results
  resolve through preview lookup, and Bilibili has a public DASH audio resolver
  marked experimental.
- Treat media resolution changes as sensitive: preserve the existing explicit
  contracts, request headers, expiry metadata, and `isExperimental` signaling.

## Backend Notes

Backend entry point: `services/api/app/main.py`.

Main modules:

- `config.py`: environment-backed settings such as DB path, YouTube key, demo
  stream URL, experimental switch, and search cache TTL.
- `models.py`: Pydantic API contracts. JSON field names use camelCase aliases
  such as `videoId`, `pageUrl`, `streamUrl`, and `expiresAt`.
- `providers/`: search providers. `BilibiliProvider` calls Bilibili search with
  an HTML fallback. `YouTubeProvider` uses the YouTube Data API when
  `YOUTUBE_API_KEY` is set and deterministic demo results otherwise.
- `resolvers/`: media resolvers. `PreviewResolver` searches iTunes previews.
  `BilibiliAudioResolver` resolves public BV video audio and marks responses
  experimental.
- `lyrics.py`: LRCLIB lookup and LRC parsing, with demo lyrics fallback.
- `storage.py`: SQLite persistence for favorites, history, and search cache.
- `scoring.py` and `music_metadata.py`: query normalization, ranking, and music
  title cleanup helpers.

Backend commands:

```powershell
cd services/api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8787
```

Run backend tests:

```powershell
cd services/api
python -m pytest
```

Useful backend environment variables:

- `YOUTUBE_API_KEY`: enables live YouTube Data API search.
- `ECHOMV_DB_PATH`: overrides the SQLite DB path, defaulting to
  `data/echomv.sqlite3` relative to `services/api`.
- `ECHOMV_DEMO_STREAM_URL`: stream URL used by demo/safe playback responses.
- `ECHOMV_ALLOW_EXPERIMENTAL_RESOLVE`: reserved local switch for experimental
  resolving.
- `ECHOMV_SEARCH_CACHE_TTL_SECONDS`: search cache TTL, default `900`.

## Flutter Notes

Flutter entry point: `apps/echomv_flutter/lib/main.dart`.

Main modules:

- `src/api_client.dart`: Dio client for backend endpoints. API base defaults to
  `http://127.0.0.1:8787` and can be overridden with
  `--dart-define=ECHOMV_API_BASE=...`.
- `src/app_controller.dart`: Riverpod `StateNotifier` coordinating search,
  playback, lyrics, favorites, history, and local fallback state.
- `src/models.dart`: Dart mirrors of backend API contracts.
- `src/local_store.dart`: shared_preferences storage for lyric offsets and
  recent searches.
- `src/shell.dart`: responsive UI shell, search pane, now-playing pane,
  collections, lyric panel, and controls.
- `src/theme.dart`: Material 3 dark theme.
- `src/visualizer.dart`: custom painter audio visualizer.

Flutter commands:

```powershell
cd apps/echomv_flutter
flutter pub get
flutter run -d windows --dart-define=ECHOMV_API_BASE=http://127.0.0.1:8787
```

For Android emulator runs:

```powershell
cd apps/echomv_flutter
flutter run -d android --dart-define=ECHOMV_API_BASE=http://10.0.2.2:8787
```

Flutter checks:

```powershell
cd apps/echomv_flutter
flutter analyze
flutter test
```

## Testing Expectations

- Backend tests live in `services/api/tests` and cover API contracts, storage,
  scoring, lyrics, metadata cleanup, Bilibili resolution helpers, and preview
  selection.
- Flutter currently has a widget smoke test in `apps/echomv_flutter/test`.
- For backend contract changes, update both Pydantic models and Dart models.
- For UI or state changes, prefer adding focused controller/model tests or
  widget tests around the touched behavior.

## Style And Conventions

- Python code uses type hints and simple module-level helper functions. Keep API
  responses typed with Pydantic models.
- Dart code follows `flutter_lints` and `prefer_single_quotes`.
- Keep JSON contracts camelCase across the API boundary.
- Do not commit generated or local state directories such as `.venv/`,
  `.pytest_cache/`, `.dart_tool/`, `build/`, `pubspec.lock`, or
  `services/api/data/`.
- Avoid broad refactors. This repo is small and benefits from direct,
  discoverable modules.

## Known Cautions

- Some Chinese UI/test strings currently appear mojibake-encoded in source
  reads. Be careful when editing text literals: fix encoding intentionally and
  locally rather than mixing unrelated text cleanup into feature work.
- `rg` and `git` may not be available in every local shell environment. Use
  PowerShell file commands as a fallback when necessary.
- Search providers depend on external services and may fail or change shape.
  Existing code should degrade to demo results or skip failed providers where
  possible.
