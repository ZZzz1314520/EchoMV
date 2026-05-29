import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:echomv_flutter/src/api_client.dart';
import 'package:echomv_flutter/src/app_controller.dart';
import 'package:echomv_flutter/src/local_store.dart';
import 'package:echomv_flutter/src/models.dart';

void main() {
  test('play opens audio before lyrics finish', () async {
    final item = _track('a', '晴天');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );

    unawaited(controller.play(item));
    api.resolveCompleters[item.id]!.complete(_media('a.mp3'));
    await _flushAsync();

    expect(player.openedMedia?.streamUrl, 'a.mp3');
    expect(controller.state.isResolving, isFalse);
    expect(controller.state.isLoadingLyrics, isTrue);
    expect(controller.state.lyrics, isEmpty);

    api.lyricsCompleters[item.id]!.complete(_lyrics('第一句'));
    await _flushAsync();

    expect(controller.state.isLoadingLyrics, isFalse);
    expect(controller.state.lyrics.single.text, '第一句');
    controller.dispose();
  });

  test('late responses from an old play request do not replace current song',
      () async {
    final first = _track('a', '晴天');
    final second = _track('b', '稻香');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );

    unawaited(controller.play(first));
    await _flushAsync();
    unawaited(controller.play(second));
    await _flushAsync();

    api.resolveCompleters[second.id]!.complete(_media('b.mp3'));
    api.lyricsCompleters[second.id]!.complete(_lyrics('第二首'));
    await _flushAsync();

    expect(controller.state.current?.id, second.id);
    expect(player.openedMedia?.streamUrl, 'b.mp3');
    expect(controller.state.lyrics.single.text, '第二首');

    api.resolveCompleters[first.id]!.complete(_media('a.mp3'));
    api.lyricsCompleters[first.id]!.complete(_lyrics('第一首'));
    await _flushAsync();

    expect(controller.state.current?.id, second.id);
    expect(player.openedMedia?.streamUrl, 'b.mp3');
    expect(controller.state.lyrics.single.text, '第二首');
    controller.dispose();
  });

  test('lyric offset can be adjusted up to ten seconds', () async {
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final controller = EchoController(api, store);
    controller.state = controller.state.copyWith(current: _track('a', '鏅村ぉ'));

    await controller.nudgeLyricOffset(12000);

    expect(controller.state.lyricOffsetMs, lyricOffsetLimitMs);
    expect(store.savedOffsets['a'], lyricOffsetLimitMs);

    await controller.nudgeLyricOffset(-25000);

    expect(controller.state.lyricOffsetMs, -lyricOffsetLimitMs);
    expect(store.savedOffsets['a'], -lyricOffsetLimitMs);
    controller.dispose();
  });

  test('completed playback advances to next search result in order', () async {
    final first = _track('a', 'First');
    final second = _track('b', 'Second');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );
    controller.state = controller.state.copyWith(results: [first, second]);

    unawaited(controller.play(first));
    api.resolveCompleters[first.id]!.complete(_media('a.mp3'));
    api.lyricsCompleters[first.id]!.complete(_lyrics('first lyric'));
    await _flushAsync();

    player.complete();
    await _flushAsync();
    api.resolveCompleters[second.id]!.complete(_media('b.mp3'));
    api.lyricsCompleters[second.id]!.complete(_lyrics('second lyric'));
    await _flushAsync();

    expect(controller.state.current?.id, second.id);
    expect(player.openedMedia?.streamUrl, 'b.mp3');
    controller.dispose();
  });

  test('shuffle next chooses from search results without repeating current',
      () async {
    final first = _track('a', 'First');
    final second = _track('b', 'Second');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );
    controller.state = controller.state.copyWith(
      current: first,
      results: [first, second],
      playbackMode: PlaybackMode.searchShuffle,
    );

    unawaited(controller.playNext());
    await _flushAsync();
    api.resolveCompleters[second.id]!.complete(_media('b.mp3'));
    api.lyricsCompleters[second.id]!.complete(_lyrics('second lyric'));
    await _flushAsync();

    expect(controller.state.current?.id, second.id);
    controller.dispose();
  });

  test('artist radio searches current artist and plays a random result',
      () async {
    final current = _track('a', 'Current', artist: 'Singer');
    final next = _track('b', 'Another song', artist: 'Singer');
    final api = _ControlledApiClient();
    api.searchResults['Singer'] = [current, next];
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );
    controller.state = controller.state.copyWith(
      current: current,
      playbackMode: PlaybackMode.artistRadio,
    );

    unawaited(controller.playNext());
    await _flushAsync();
    api.resolveCompleters[next.id]!.complete(_media('b.mp3'));
    api.lyricsCompleters[next.id]!.complete(_lyrics('next lyric'));
    await _flushAsync();

    expect(api.searchQueries, ['Singer']);
    expect(controller.state.current?.id, next.id);
    expect(controller.state.results.map((item) => item.id), ['a', 'b']);
    controller.dispose();
  });

  test('completed playback advances through current playlist in order',
      () async {
    final first = _track('a', 'First');
    final second = _track('b', 'Second');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );
    final playlist = await controller.createPlaylist('Road songs');
    await controller.addToPlaylist(playlist.id, first);
    await controller.addToPlaylist(playlist.id, second);
    controller.setPlaybackMode(PlaybackMode.playlistOrder);

    unawaited(controller.playFromPlaylist(playlist.id, first));
    api.resolveCompleters[first.id]!.complete(_media('a.mp3'));
    api.lyricsCompleters[first.id]!.complete(_lyrics('first lyric'));
    await _flushAsync();

    player.complete();
    await _flushAsync();
    api.resolveCompleters[second.id]!.complete(_media('b.mp3'));
    api.lyricsCompleters[second.id]!.complete(_lyrics('second lyric'));
    await _flushAsync();

    expect(controller.state.current?.id, second.id);
    expect(controller.state.currentPlaylistId, playlist.id);
    controller.dispose();
  });

  test('playlist shuffle chooses from the current playlist', () async {
    final first = _track('a', 'First');
    final second = _track('b', 'Second');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );
    final playlist = await controller.createPlaylist('Shuffle bag');
    await controller.addToPlaylist(playlist.id, first);
    await controller.addToPlaylist(playlist.id, second);
    controller.state = controller.state.copyWith(
      current: first,
      currentPlaylistId: playlist.id,
      playbackMode: PlaybackMode.playlistShuffle,
    );

    unawaited(controller.playNext());
    await _flushAsync();
    api.resolveCompleters[second.id]!.complete(_media('b.mp3'));
    api.lyricsCompleters[second.id]!.complete(_lyrics('second lyric'));
    await _flushAsync();

    expect(controller.state.current?.id, second.id);
    expect(controller.state.currentPlaylistId, playlist.id);
    controller.dispose();
  });

  test('same song keeps the playlist it was opened from', () async {
    final shared = _track('a', 'Shared');
    final fromFirstPlaylist = _track('b', 'First playlist next');
    final fromSecondPlaylist = _track('c', 'Second playlist next');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );
    final firstPlaylist = await controller.createPlaylist('A');
    await controller.addToPlaylist(firstPlaylist.id, shared);
    await controller.addToPlaylist(firstPlaylist.id, fromFirstPlaylist);
    final secondPlaylist = await controller.createPlaylist('B');
    await controller.addToPlaylist(secondPlaylist.id, shared);
    await controller.addToPlaylist(secondPlaylist.id, fromSecondPlaylist);
    controller.setPlaybackMode(PlaybackMode.playlistOrder);

    unawaited(controller.playFromPlaylist(secondPlaylist.id, shared));
    api.resolveCompleters[shared.id]!.complete(_media('a.mp3'));
    api.lyricsCompleters[shared.id]!.complete(_lyrics('shared lyric'));
    await _flushAsync();

    player.complete();
    await _flushAsync();
    api.resolveCompleters[fromSecondPlaylist.id]!.complete(_media('c.mp3'));
    api.lyricsCompleters[fromSecondPlaylist.id]!
        .complete(_lyrics('second playlist lyric'));
    await _flushAsync();

    expect(controller.state.current?.id, fromSecondPlaylist.id);
    expect(controller.state.currentPlaylistId, secondPlaylist.id);
    controller.dispose();
  });

  test('playlist operations update controller state and avoid duplicates',
      () async {
    final item = _track('a', 'First');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final controller = EchoController(api, store);
    await _flushAsync();

    final playlist = await controller.createPlaylist('Favorites');
    await controller.addToPlaylist(playlist.id, item);
    await controller.addToPlaylist(playlist.id, item);

    expect(controller.state.playlists.single.name, 'Favorites');
    expect(controller.state.playlists.single.items, hasLength(1));
    expect(controller.state.playlists.single.items.single.id, item.id);

    await controller.renamePlaylist(playlist.id, 'Road songs');
    expect(controller.state.playlists.single.name, 'Road songs');

    await controller.removeFromPlaylist(playlist.id, item.id);
    expect(controller.state.playlists.single.items, isEmpty);

    await controller.deletePlaylist(playlist.id);
    expect(controller.state.playlists, isEmpty);
    controller.dispose();
  });

  test('playback history is de-duplicated and moved to the front', () async {
    final first = _track('a', 'First');
    final second = _track('b', 'Second');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final player = _FakeAudioPlayer();
    final controller = EchoController(
      api,
      store,
      audioPlayerFactory: () => player,
    );

    unawaited(controller.play(first));
    api.resolveCompleters[first.id]!.complete(_media('a.mp3'));
    api.lyricsCompleters[first.id]!.complete(_lyrics('first lyric'));
    await _flushAsync();

    unawaited(controller.play(second));
    api.resolveCompleters[second.id]!.complete(_media('b.mp3'));
    api.lyricsCompleters[second.id]!.complete(_lyrics('second lyric'));
    await _flushAsync();

    unawaited(controller.play(first));
    await _flushAsync();

    expect(controller.state.history.map((item) => item.id), ['a', 'b']);
    controller.dispose();
  });

  test('favorite add and remove refresh current favorite state', () async {
    final item = _track('a', 'First');
    final api = _ControlledApiClient();
    final store = _FakeLocalStore();
    final controller = EchoController(api, store);
    controller.state = controller.state.copyWith(current: item);

    await controller.toggleFavorite();
    expect(controller.state.isCurrentFavorite, isTrue);

    await controller.removeFromFavorites(item.id);
    expect(controller.state.isCurrentFavorite, isFalse);
    controller.dispose();
  });
}

SearchResult _track(String id, String title, {String? artist}) {
  return SearchResult(
    id: id,
    source: 'youtube',
    videoId: id,
    title: title,
    artist: artist,
    pageUrl: 'https://example.test/$id',
  );
}

ResolvedMedia _media(String url) {
  return ResolvedMedia(
    streamUrl: url,
    mimeType: 'audio/mpeg',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    source: 'test',
    isExperimental: false,
  );
}

LyricsResponse _lyrics(String text) {
  return LyricsResponse(
    title: 'test',
    confidence: 1,
    source: 'test',
    lines: [LyricLine(timeMs: 0, text: text)],
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _ControlledApiClient extends EchoApiClient {
  final resolveCompleters = <String, Completer<ResolvedMedia>>{};
  final lyricsCompleters = <String, Completer<LyricsResponse>>{};
  final searchResults = <String, List<SearchResult>>{};
  final searchQueries = <String>[];
  final favoriteItems = <SearchResult>[];
  final historyItems = <SearchResult>[];

  @override
  Future<List<SearchResult>> search(String query) async {
    searchQueries.add(query);
    return searchResults[query] ?? [];
  }

  @override
  Future<ResolvedMedia> resolve(SearchResult item) {
    return (resolveCompleters[item.id] ??= Completer<ResolvedMedia>()).future;
  }

  @override
  Future<LyricsResponse> lyrics(SearchResult item) {
    return (lyricsCompleters[item.id] ??= Completer<LyricsResponse>()).future;
  }

  @override
  Future<void> recordHistory(SearchResult item) async {
    historyItems
      ..removeWhere((value) => value.id == item.id)
      ..insert(0, item);
  }

  @override
  Future<void> addFavorite(SearchResult item) async {
    favoriteItems
      ..removeWhere((value) => value.id == item.id)
      ..insert(0, item);
  }

  @override
  Future<void> removeFavorite(String id) async {
    favoriteItems.removeWhere((value) => value.id == id);
  }

  @override
  Future<List<SearchResult>> favorites() async => favoriteItems;

  @override
  Future<List<SearchResult>> history() async => historyItems;
}

class _FakeLocalStore extends LocalStore {
  final savedOffsets = <String, int>{};
  final remembered = <SearchResult>[];
  final storedPlaylists = <Playlist>[];

  @override
  Future<Map<String, int>> lyricOffsets() async => {};

  @override
  Future<void> saveLyricOffset(String itemId, int offsetMs) async {
    savedOffsets[itemId] = offsetMs;
  }

  @override
  Future<void> rememberSearchResult(SearchResult item) async {
    remembered
      ..removeWhere((value) => value.id == item.id)
      ..insert(0, item);
  }

  @override
  Future<List<SearchResult>> recentSearches() async => remembered;

  @override
  Future<void> clearRecentSearches() async {
    remembered.clear();
  }

  @override
  Future<List<Playlist>> playlists() async => List.of(storedPlaylists);

  @override
  Future<Playlist> createPlaylist(String name) async {
    final now = DateTime(2026, 1, storedPlaylists.length + 1);
    final playlist = Playlist(
      id: 'playlist-${storedPlaylists.length + 1}',
      name: name,
      items: const [],
      createdAt: now,
      updatedAt: now,
    );
    storedPlaylists.insert(0, playlist);
    return playlist;
  }

  @override
  Future<void> renamePlaylist(String id, String name) async {
    for (var i = 0; i < storedPlaylists.length; i++) {
      final playlist = storedPlaylists[i];
      if (playlist.id == id) {
        storedPlaylists[i] = playlist.copyWith(name: name);
      }
    }
  }

  @override
  Future<void> deletePlaylist(String id) async {
    storedPlaylists.removeWhere((playlist) => playlist.id == id);
  }

  @override
  Future<void> addToPlaylist(String playlistId, SearchResult item) async {
    for (var i = 0; i < storedPlaylists.length; i++) {
      final playlist = storedPlaylists[i];
      if (playlist.id == playlistId) {
        storedPlaylists[i] = playlist.copyWith(
          items: [
            item,
            ...playlist.items.where((value) => value.id != item.id),
          ],
        );
      }
    }
  }

  @override
  Future<void> removeFromPlaylist(String playlistId, String itemId) async {
    for (var i = 0; i < storedPlaylists.length; i++) {
      final playlist = storedPlaylists[i];
      if (playlist.id == playlistId) {
        storedPlaylists[i] = playlist.copyWith(
          items: [
            for (final item in playlist.items)
              if (item.id != itemId) item,
          ],
        );
      }
    }
  }
}

class _FakeAudioPlayer implements EchoAudioPlayer {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  ResolvedMedia? openedMedia;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Future<void> open(ResolvedMedia media) async {
    openedMedia = media;
    _playing.add(true);
    _completed.add(false);
  }

  @override
  Future<void> pause() async {
    _playing.add(false);
  }

  @override
  Future<void> play() async {
    _playing.add(true);
  }

  @override
  Future<void> seek(Duration position) async {
    _position.add(position);
  }

  void complete() {
    _playing.add(false);
    _completed.add(true);
  }

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _completed.close();
  }
}
