import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'api_client.dart';
import 'local_store.dart';
import 'models.dart';

final apiClientProvider = Provider((ref) => EchoApiClient());
final localStoreProvider = Provider((ref) => LocalStore());

final echoControllerProvider =
    StateNotifierProvider<EchoController, EchoState>((ref) {
  return EchoController(ref.read(apiClientProvider), ref.read(localStoreProvider));
});

typedef EchoAudioPlayerFactory = EchoAudioPlayer Function();

abstract class EchoAudioPlayer {
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;

  Future<void> open(ResolvedMedia media);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class MediaKitEchoAudioPlayer implements EchoAudioPlayer {
  MediaKitEchoAudioPlayer() : _player = Player();

  final Player _player;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Future<void> open(ResolvedMedia media) {
    return _player.open(
      Media(
        media.streamUrl,
        httpHeaders: media.requestHeaders.isEmpty ? null : media.requestHeaders,
      ),
      play: true,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() => _player.dispose();
}

class EchoState {
  const EchoState({
    this.query = '',
    this.results = const [],
    this.favorites = const [],
    this.history = const [],
    this.current,
    this.media,
    this.lyrics = const [],
    this.lyricOffsetMs = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isSearching = false,
    this.isResolving = false,
    this.isLoadingLyrics = false,
    this.error,
  });

  final String query;
  final List<SearchResult> results;
  final List<SearchResult> favorites;
  final List<SearchResult> history;
  final SearchResult? current;
  final ResolvedMedia? media;
  final List<LyricLine> lyrics;
  final int lyricOffsetMs;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isSearching;
  final bool isResolving;
  final bool isLoadingLyrics;
  final String? error;

  int get activeLyricIndex {
    if (lyrics.isEmpty) return -1;
    final currentMs = position.inMilliseconds + lyricOffsetMs;
    var index = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if (lyrics[i].timeMs <= currentMs) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  bool get isCurrentFavorite =>
      current != null && favorites.any((item) => item.id == current!.id);

  EchoState copyWith({
    String? query,
    List<SearchResult>? results,
    List<SearchResult>? favorites,
    List<SearchResult>? history,
    SearchResult? current,
    bool clearCurrent = false,
    ResolvedMedia? media,
    bool clearMedia = false,
    List<LyricLine>? lyrics,
    int? lyricOffsetMs,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isSearching,
    bool? isResolving,
    bool? isLoadingLyrics,
    String? error,
    bool clearError = false,
  }) {
    return EchoState(
      query: query ?? this.query,
      results: results ?? this.results,
      favorites: favorites ?? this.favorites,
      history: history ?? this.history,
      current: clearCurrent ? null : current ?? this.current,
      media: clearMedia ? null : media ?? this.media,
      lyrics: lyrics ?? this.lyrics,
      lyricOffsetMs: lyricOffsetMs ?? this.lyricOffsetMs,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isSearching: isSearching ?? this.isSearching,
      isResolving: isResolving ?? this.isResolving,
      isLoadingLyrics: isLoadingLyrics ?? this.isLoadingLyrics,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class EchoController extends StateNotifier<EchoState> {
  EchoController(
    this._api,
    this._store, {
    EchoAudioPlayerFactory? audioPlayerFactory,
  })  : _audioPlayerFactory = audioPlayerFactory ?? MediaKitEchoAudioPlayer.new,
        super(const EchoState()) {
    unawaited(refreshCollections());
  }

  final EchoApiClient _api;
  final LocalStore _store;
  final EchoAudioPlayerFactory _audioPlayerFactory;
  EchoAudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  var _playRequestId = 0;

  EchoAudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;

    final player = _audioPlayerFactory();
    _player = player;
    _positionSub = player.positionStream.listen((position) {
      state = state.copyWith(position: position);
    });
    _durationSub = player.durationStream.listen((duration) {
      state = state.copyWith(duration: duration);
    });
    _playingSub = player.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });
    return player;
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(query: trimmed, isSearching: true, clearError: true);
    try {
      final results = await _api.search(trimmed);
      state = state.copyWith(results: results, isSearching: false);
    } catch (error) {
      state = state.copyWith(
        isSearching: false,
        error: '搜索失败：$error',
      );
    }
  }

  Future<void> play(SearchResult item) async {
    final requestId = ++_playRequestId;
    state = state.copyWith(
      current: item,
      isResolving: true,
      isLoadingLyrics: true,
      clearMedia: true,
      lyrics: const [],
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      clearError: true,
    );
    unawaited(_loadLyricsFor(item, requestId));

    try {
      final media = await _api.resolve(item);
      if (!_isActivePlayback(requestId, item)) return;

      final offsets = await _store.lyricOffsets();
      if (!_isActivePlayback(requestId, item)) return;

      await _ensurePlayer().open(media);
      if (!_isActivePlayback(requestId, item)) return;

      state = state.copyWith(
        media: media,
        lyricOffsetMs: offsets[item.id] ?? 0,
        isResolving: false,
      );
      unawaited(_recordPlayback(item));
    } catch (error) {
      if (_isActivePlayback(requestId, item)) {
        state = state.copyWith(
          isResolving: false,
          isLoadingLyrics: false,
          error: '播放准备失败：$error',
        );
      }
    }
  }

  bool _isActivePlayback(int requestId, SearchResult item) {
    return requestId == _playRequestId && state.current?.id == item.id;
  }

  Future<void> _loadLyricsFor(SearchResult item, int requestId) async {
    try {
      final lyrics = await _api.lyrics(item);
      if (!_isActivePlayback(requestId, item)) return;
      state = state.copyWith(lyrics: lyrics.lines, isLoadingLyrics: false);
    } catch (_) {
      if (!_isActivePlayback(requestId, item)) return;
      state = state.copyWith(lyrics: const [], isLoadingLyrics: false);
    }
  }

  Future<void> _recordPlayback(SearchResult item) async {
    try {
      await _api.recordHistory(item);
    } catch (_) {
      // Local recents still keep the UI useful if the backend is unavailable.
    }
    await _store.rememberSearchResult(item);
    await refreshCollections();
  }

  Future<void> togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (state.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  Future<void> nudgeLyricOffset(int deltaMs) async {
    final current = state.current;
    if (current == null) return;
    final next = (state.lyricOffsetMs + deltaMs).clamp(-2000, 2000).toInt();
    state = state.copyWith(lyricOffsetMs: next);
    await _store.saveLyricOffset(current.id, next);
  }

  Future<void> toggleFavorite() async {
    final current = state.current;
    if (current == null) return;
    if (state.isCurrentFavorite) {
      await _api.removeFavorite(current.id);
    } else {
      await _api.addFavorite(current);
    }
    await refreshCollections();
  }

  Future<void> refreshCollections() async {
    try {
      final values = await Future.wait([
        _api.favorites(),
        _api.history(),
      ]);
      state = state.copyWith(
        favorites: values[0],
        history: values[1],
      );
    } catch (_) {
      final recent = await _store.recentSearches();
      state = state.copyWith(history: recent);
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    final player = _player;
    if (player != null) {
      unawaited(player.dispose());
    }
    super.dispose();
  }
}
