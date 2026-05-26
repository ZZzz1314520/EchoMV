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

  test('late responses from an old play request do not replace current song', () async {
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
}

SearchResult _track(String id, String title) {
  return SearchResult(
    id: id,
    source: 'youtube',
    videoId: id,
    title: title,
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

  @override
  Future<ResolvedMedia> resolve(SearchResult item) {
    return (resolveCompleters[item.id] ??= Completer<ResolvedMedia>()).future;
  }

  @override
  Future<LyricsResponse> lyrics(SearchResult item) {
    return (lyricsCompleters[item.id] ??= Completer<LyricsResponse>()).future;
  }

  @override
  Future<void> recordHistory(SearchResult item) async {}

  @override
  Future<List<SearchResult>> favorites() async => [];

  @override
  Future<List<SearchResult>> history() async => [];
}

class _FakeLocalStore extends LocalStore {
  @override
  Future<Map<String, int>> lyricOffsets() async => {};

  @override
  Future<void> rememberSearchResult(SearchResult item) async {}

  @override
  Future<List<SearchResult>> recentSearches() async => [];
}

class _FakeAudioPlayer implements EchoAudioPlayer {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  ResolvedMedia? openedMedia;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> open(ResolvedMedia media) async {
    openedMedia = media;
    _playing.add(true);
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

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _playing.close();
  }
}
