import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;

import 'api_client.dart';
import 'local_data_source.dart';
import 'local_store.dart';
import 'models.dart';

final localStoreProvider = Provider((ref) => LocalStore());
final apiClientProvider = Provider<EchoDataSource>((ref) {
  final store = ref.read(localStoreProvider);
  if (localOnlyMode) {
    return LocalEchoDataSource(store: store);
  }
  return EchoApiClient();
});
const lyricOffsetLimitMs = 10000;

final echoControllerProvider =
    StateNotifierProvider<EchoController, EchoState>((ref) {
  return EchoController(
      ref.read(apiClientProvider), ref.read(localStoreProvider));
});

typedef EchoAudioPlayerFactory = EchoAudioPlayer Function();

abstract class EchoAudioPlayer {
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get completedStream;

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
  Stream<bool> get completedStream => _player.stream.completed;

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

enum PlaybackMode {
  searchOrder,
  searchShuffle,
  playlistOrder,
  playlistShuffle,
  artistRadio,
}

enum CollectionView {
  discover,
  playlists,
  history,
  favorites,
}

class EchoState {
  const EchoState({
    this.query = '',
    this.results = const [],
    this.favorites = const [],
    this.history = const [],
    this.playlists = const [],
    this.selectedCollectionView = CollectionView.discover,
    this.currentPlaylistId,
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
    this.playbackMode = PlaybackMode.searchOrder,
    this.error,
  });

  final String query;
  final List<SearchResult> results;
  final List<SearchResult> favorites;
  final List<SearchResult> history;
  final List<Playlist> playlists;
  final CollectionView selectedCollectionView;
  final String? currentPlaylistId;
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
  final PlaybackMode playbackMode;
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
    List<Playlist>? playlists,
    CollectionView? selectedCollectionView,
    String? currentPlaylistId,
    bool clearCurrentPlaylist = false,
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
    PlaybackMode? playbackMode,
    String? error,
    bool clearError = false,
  }) {
    return EchoState(
      query: query ?? this.query,
      results: results ?? this.results,
      favorites: favorites ?? this.favorites,
      history: history ?? this.history,
      playlists: playlists ?? this.playlists,
      selectedCollectionView:
          selectedCollectionView ?? this.selectedCollectionView,
      currentPlaylistId: clearCurrentPlaylist
          ? null
          : currentPlaylistId ?? this.currentPlaylistId,
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
      playbackMode: playbackMode ?? this.playbackMode,
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

  final EchoDataSource _api;
  final LocalStore _store;
  final EchoAudioPlayerFactory _audioPlayerFactory;
  EchoAudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  final _random = math.Random();
  var _playRequestId = 0;
  var _handlingCompletion = false;

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
    _completedSub = player.completedStream.listen((completed) {
      if (completed) {
        unawaited(_handlePlaybackCompleted());
      }
    });
    return player;
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      query: trimmed,
      selectedCollectionView: CollectionView.discover,
      isSearching: true,
      clearError: true,
    );
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

  Future<void> play(SearchResult item, {String? playlistId}) async {
    final requestId = ++_playRequestId;
    state = state.copyWith(
      current: item,
      currentPlaylistId: playlistId,
      clearCurrentPlaylist: playlistId == null,
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

  void setPlaybackMode(PlaybackMode mode) {
    state = state.copyWith(playbackMode: mode, clearError: true);
  }

  void selectCollectionView(CollectionView view) {
    state = state.copyWith(selectedCollectionView: view, clearError: true);
  }

  Future<void> playNext() async {
    final next = await _nextPlaybackItem();
    if (next == null) return;
    final playlistId = switch (state.playbackMode) {
      PlaybackMode.playlistOrder ||
      PlaybackMode.playlistShuffle =>
        state.currentPlaylistId,
      PlaybackMode.searchOrder ||
      PlaybackMode.searchShuffle ||
      PlaybackMode.artistRadio =>
        null,
    };
    await play(next, playlistId: playlistId);
  }

  Future<void> _handlePlaybackCompleted() async {
    if (_handlingCompletion) return;
    _handlingCompletion = true;
    try {
      await playNext();
    } finally {
      _handlingCompletion = false;
    }
  }

  Future<SearchResult?> _nextPlaybackItem() async {
    return switch (state.playbackMode) {
      PlaybackMode.searchOrder => _nextFromSearchOrder(),
      PlaybackMode.searchShuffle => _randomFromSearchResults(),
      PlaybackMode.playlistOrder => _nextFromPlaylistOrder(),
      PlaybackMode.playlistShuffle => _randomFromCurrentPlaylist(),
      PlaybackMode.artistRadio => _randomFromCurrentArtist(),
    };
  }

  SearchResult? _nextFromSearchOrder() {
    final results = state.results;
    final current = state.current;
    if (results.isEmpty) return null;
    if (current == null) return results.first;
    if (results.length == 1 && results.first.id == current.id) return null;

    final currentIndex = results.indexWhere((item) => item.id == current.id);
    if (currentIndex < 0) return results.first;
    return results[(currentIndex + 1) % results.length];
  }

  SearchResult? _randomFromSearchResults() {
    return _randomFromCandidates(state.results);
  }

  SearchResult? _nextFromPlaylistOrder() {
    final playlist = _currentPlaybackPlaylist();
    final current = state.current;
    if (playlist == null) return null;
    final items = playlist.items;
    if (items.isEmpty) return null;
    if (current == null) return items.first;
    if (items.length == 1 && items.first.id == current.id) return null;

    final currentIndex = items.indexWhere((item) => item.id == current.id);
    if (currentIndex < 0) return items.first;
    return items[(currentIndex + 1) % items.length];
  }

  SearchResult? _randomFromCurrentPlaylist() {
    final playlist = _currentPlaybackPlaylist();
    if (playlist == null) return null;
    return _randomFromCandidates(playlist.items);
  }

  Playlist? _currentPlaybackPlaylist() {
    final playlistId = state.currentPlaylistId;
    if (playlistId == null) {
      state = state.copyWith(error: '当前歌曲不是从歌单打开的，无法按歌单自动播放。');
      return null;
    }
    for (final playlist in state.playlists) {
      if (playlist.id == playlistId) return playlist;
    }
    state = state.copyWith(error: '当前歌单不存在，无法继续按歌单播放。');
    return null;
  }

  Future<SearchResult?> _randomFromCurrentArtist() async {
    final current = state.current;
    final artist = current?.artist?.trim();
    if (artist == null || artist.isEmpty) {
      state = state.copyWith(error: '当前歌曲没有歌手信息，无法自动搜索歌手。');
      return null;
    }

    state = state.copyWith(query: artist, isSearching: true, clearError: true);
    try {
      final results = await _api.search(artist);
      state = state.copyWith(results: results, isSearching: false);
      return _randomFromCandidates(results);
    } catch (error) {
      state = state.copyWith(
        isSearching: false,
        error: '自动搜索歌手失败：$error',
      );
      return null;
    }
  }

  SearchResult? _randomFromCandidates(List<SearchResult> results) {
    final currentId = state.current?.id;
    final candidates = [
      for (final item in results)
        if (item.id != currentId) item,
    ];
    if (candidates.isEmpty) return null;
    return candidates[_random.nextInt(candidates.length)];
  }

  Future<void> playFromPlaylist(String playlistId, SearchResult item) {
    return play(item, playlistId: playlistId);
  }

  Future<void> nudgeLyricOffset(int deltaMs) async {
    final current = state.current;
    if (current == null) return;
    final next = (state.lyricOffsetMs + deltaMs)
        .clamp(-lyricOffsetLimitMs, lyricOffsetLimitMs)
        .toInt();
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

  Future<void> removeFromFavorites(String itemId) async {
    await _api.removeFavorite(itemId);
    await refreshCollections();
  }

  Future<void> clearHistory() async {
    await _store.clearRecentSearches();
    await refreshCollections();
  }

  Future<Playlist> createPlaylist(String name) async {
    final playlist = await _store.createPlaylist(name);
    await refreshCollections();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    await _store.renamePlaylist(id, name);
    await refreshCollections();
  }

  Future<void> deletePlaylist(String id) async {
    await _store.deletePlaylist(id);
    await refreshCollections();
  }

  Future<void> addToPlaylist(String playlistId, SearchResult item) async {
    await _store.addToPlaylist(playlistId, item);
    await refreshCollections();
  }

  Future<void> removeFromPlaylist(String playlistId, String itemId) async {
    await _store.removeFromPlaylist(playlistId, itemId);
    await refreshCollections();
  }

  Future<void> refreshCollections() async {
    final playlists = await _store.playlists();
    try {
      final values = await Future.wait([
        _api.favorites(),
        _api.history(),
      ]);
      state = state.copyWith(
        favorites: values[0],
        history: values[1],
        playlists: playlists,
      );
    } catch (_) {
      final recent = await _store.recentSearches();
      final favorites = await _store.favorites();
      state = state.copyWith(
        favorites: favorites,
        history: recent,
        playlists: playlists,
      );
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    final player = _player;
    if (player != null) {
      unawaited(player.dispose());
    }
    super.dispose();
  }
}
