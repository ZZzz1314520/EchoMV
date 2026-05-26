# EchoMV

EchoMV is a personal prototype for a cross-platform MV-driven music player.

The workspace contains two projects:

- `services/api`: Python FastAPI backend for video search aggregation, lyrics lookup, media resolution contracts, favorites, and history.
- `apps/echomv_flutter`: Flutter client source for Windows and Android.

This prototype intentionally keeps video-site media resolution behind a local switch. It does not include DRM bypassing, member-only content bypassing, bulk downloading, or redistribution features.

## Backend

```powershell
cd services/api
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8787
```

Useful environment variables:

- `YOUTUBE_API_KEY`: enables YouTube Data API search. Without it, YouTube returns deterministic demo results.
- `ECHOMV_DEMO_STREAM_URL`: stream URL used by the safe resolver for UI playback testing.
- `ECHOMV_ALLOW_EXPERIMENTAL_RESOLVE`: reserved switch for local-only experimental resolvers. The bundled resolver does not extract audio from video sites.

## Flutter

Flutter is not bundled in this repository. After installing Flutter, initialize platform folders and run:

```powershell
cd apps/echomv_flutter
flutter create --platforms=windows,android .
flutter pub get
flutter run -d windows --dart-define=ECHOMV_API_BASE=http://127.0.0.1:8787
```

For Android emulator testing, use your host bridge address:

```powershell
flutter run -d android --dart-define=ECHOMV_API_BASE=http://10.0.2.2:8787
```

## Tests

```powershell
cd services/api
python -m pytest
```
