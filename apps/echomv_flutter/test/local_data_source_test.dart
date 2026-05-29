import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:echomv_flutter/src/local_data_source.dart';
import 'package:echomv_flutter/src/local_store.dart';
import 'package:echomv_flutter/src/models.dart';

void main() {
  test('local Bilibili search parses JSON results', () async {
    SharedPreferences.setMockInitialValues({});
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/all': _json({}, statusCode: 404),
        '/x/web-interface/search/type': _json({
          'code': 0,
          'data': {
            'result': [
              {
                'bvid': 'BV123',
                'title': '<em class="keyword">清明雨上</em> MV',
                'author': '许嵩',
                'duration': '04:00',
                'pic': '//i0.hdslb.com/test.jpg',
                'arcurl': 'https://www.bilibili.com/video/BV123',
              },
            ],
          },
        }),
      }),
    );

    final results = await dataSource.search('清明雨上');

    expect(results, hasLength(1));
    expect(results.single.id, 'bilibili:BV123');
    expect(results.single.title, '清明雨上 MV');
    expect(results.single.duration, 240);
    expect(results.single.tags, contains('query-match'));
  });

  test('local Bilibili search uses HTML fallback after HTTP 412', () async {
    SharedPreferences.setMockInitialValues({});
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/all': _html('''
bili-video-card__wrap
<a href="//www.bilibili.com/video/BVHTML/"></a>
<h3 class="bili-video-card__info--tit" title="清明雨上 官方MV"></h3>
<span class="bili-video-card__info--author">许嵩</span>
<span class="bili-video-card__stats__duration">03:52</span>
<img src="//i0.hdslb.com/html.jpg">
'''),
        '/x/web-interface/search/type': _json({'code': -412}, statusCode: 412),
      }),
    );

    final results = await dataSource.search('清明雨上');

    expect(results.map((item) => item.videoId), ['BVHTML']);
    expect(results.single.title, '清明雨上 官方MV');
  });

  test('local Bilibili search caches repeated queries', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/all': _html('''
bili-video-card__wrap
<a href="//www.bilibili.com/video/BVCACHE/"></a>
<h3 class="bili-video-card__info--tit" title="清明雨上 官方MV"></h3>
'''),
      }, requests: requests),
    );

    await dataSource.search('清明雨上');
    await dataSource.search(' 清明雨上 ');

    expect(requests.where((uri) => uri.path == '/all'), hasLength(1));
  });

  test('local Bilibili search falls back to relevant HTML cards', () async {
    SharedPreferences.setMockInitialValues({});
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/x/web-interface/search/type': _json({'code': -412}),
        '/all': _html('''
bili-video-card__wrap
<a href="//www.bilibili.com/video/BVREAL"></a>
<h3 class="bili-video-card__info--tit" title="清明雨上 现场版"></h3>
<span class="bili-video-card__info--author">许嵩</span>
<span class="bili-video-card__stats__duration">03:52</span>
<img src="//i0.hdslb.com/real.jpg">
bili-video-card__wrap
<a href="//www.bilibili.com/video/BVOTHER"></a>
<h3 class="bili-video-card__info--tit" title="完全不相关"></h3>
'''),
      }),
    );

    final results = await dataSource.search('清明雨上');

    expect(results.map((item) => item.videoId), ['BVREAL']);
    expect(results.single.tags, contains('html-fallback'));
  });

  test('local Bilibili resolve returns stream headers and expiry', () async {
    SharedPreferences.setMockInitialValues({});
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/x/web-interface/view': _json({
          'code': 0,
          'data': {'cid': 42},
        }),
        '/x/player/playurl': _json({
          'code': 0,
          'data': {
            'dash': {
              'audio': [
                {
                  'baseUrl':
                      'https://audio.example.test/song.m4a?deadline=1893456000',
                  'mimeType': 'audio/mp4',
                  'bandwidth': 128000,
                },
              ],
            },
          },
        }),
      }),
    );

    final media = await dataSource.resolve(_track());

    expect(media.streamUrl, contains('song.m4a'));
    expect(media.source, 'bilibili-audio');
    expect(media.isExperimental, isTrue);
    expect(media.requestHeaders['Referer'],
        'https://www.bilibili.com/video/BV123');
    expect(media.waveformPeaks, hasLength(96));
    expect(media.expiresAt.toUtc().year, 2030);
  });

  test('local lyrics parses LRCLIB synced lyrics', () async {
    SharedPreferences.setMockInitialValues({});
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/api/get': _json({
          'trackName': '清明雨上',
          'artistName': '许嵩',
          'syncedLyrics': '[00:01.25]第一句\n[00:05.000]第二句',
        }),
      }),
    );

    final lyrics = await dataSource.lyrics(_track());

    expect(lyrics.source, 'lrclib');
    expect(lyrics.lines.map((line) => line.text), ['第一句', '第二句']);
    expect(lyrics.lines.first.timeMs, 1250);
  });

  test(
      'local lyrics falls back to title-only LRCLIB search when author is uploader',
      () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/api/get': _json({}, statusCode: 404),
        '/api/search': _json([
          {
            'trackName': '清明雨上',
            'artistName': '许嵩',
            'duration': 240,
            'syncedLyrics': '[00:02.000]窗透初晓',
          },
        ]),
      }, requests: requests),
    );

    final lyrics = await dataSource.lyrics(
      const SearchResult(
        id: 'bilibili:BVUP',
        source: 'bilibili',
        videoId: 'BVUP',
        title: '许嵩 - 清明雨上 官方MV',
        artist: '音乐搬运频道',
        duration: 240,
        pageUrl: 'https://www.bilibili.com/video/BVUP',
      ),
    );

    expect(lyrics.source, 'lrclib');
    expect(lyrics.title, '清明雨上');
    expect(lyrics.artist, '许嵩');
    expect(lyrics.lines.single.text, '窗透初晓');
    expect(
      requests
          .where((uri) => uri.path == '/api/search')
          .single
          .queryParameters['q'],
      isNot(contains('音乐搬运频道')),
    );
  });

  test('local lyrics falls back to Netease when LRCLIB has no match', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/api/get': _json({}, statusCode: 404),
        '/api/search': _json([]),
        '/api/search/get/web': _json({
          'result': {
            'songs': [
              {
                'id': 100,
                'name': '清明雨上',
                'duration': 240000,
                'artists': [
                  {'name': '许嵩'},
                ],
              },
            ],
          },
        }),
        '/api/song/lyric': _json({
          'lrc': {
            'lyric': '[00:01.000]作词 : 许嵩\n[00:05.000]窗透初晓',
          },
        }),
      }, requests: requests),
    );

    final lyrics = await dataSource.lyrics(
      const SearchResult(
        id: 'bilibili:BVUP',
        source: 'bilibili',
        videoId: 'BVUP',
        title: '许嵩 - 清明雨上 官方MV',
        artist: '音乐搬运频道',
        duration: 240,
        pageUrl: 'https://www.bilibili.com/video/BVUP',
      ),
    );

    expect(lyrics.source, 'netease');
    expect(lyrics.lines.map((line) => line.text), ['作词 : 许嵩', '窗透初晓']);
    expect(
      requests
          .where((uri) => uri.path == '/api/search/get/web')
          .single
          .queryParameters['s'],
      '许嵩 清明雨上',
    );
  });

  test('local lyrics returns within configured timeout when providers are slow',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      lyricsTimeout: const Duration(milliseconds: 60),
      dio: _dioWith({
        '/api/get': _json({},
            statusCode: 404, delay: const Duration(milliseconds: 300)),
        '/api/search/get/web': _json(
          {
            'result': {'songs': []},
          },
          delay: const Duration(milliseconds: 300),
        ),
      }),
    );
    final stopwatch = Stopwatch()..start();

    final lyrics = await dataSource.lyrics(_track());
    stopwatch.stop();

    expect(lyrics.source, 'demo');
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
  });

  test('local lyrics caches successful results', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({
        '/api/get': _json({
          'trackName': '清明雨上',
          'artistName': '许嵩',
          'syncedLyrics': '[00:01.000]第一句',
        }),
        '/api/search/get/web': _json({
          'result': {'songs': []},
        }),
      }, requests: requests),
    );

    await dataSource.lyrics(_track());
    await dataSource.lyrics(_track());

    expect(requests.where((uri) => uri.path == '/api/get'), hasLength(1));
  });

  test('local favorites and history are persisted in SharedPreferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dataSource = LocalEchoDataSource(
      store: LocalStore(),
      dio: _dioWith({}),
    );
    final item = _track();

    await dataSource.addFavorite(item);
    await dataSource.recordHistory(item);

    expect((await dataSource.favorites()).single.id, item.id);
    expect((await dataSource.history()).single.id, item.id);

    await dataSource.removeFavorite(item.id);

    expect(await dataSource.favorites(), isEmpty);
  });

  test('local store persists playlists without mixing collections', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore();
    final item = _track();

    final playlist = await store.createPlaylist('夜跑');
    await store.addToPlaylist(playlist.id, item);
    await store.addFavorite(item);
    await store.rememberSearchResult(item);

    final playlists = await store.playlists();
    expect(playlists.single.name, '夜跑');
    expect(playlists.single.items.single.id, item.id);
    expect((await store.favorites()).single.id, item.id);
    expect((await store.recentSearches()).single.id, item.id);

    await store.deletePlaylist(playlist.id);
    expect(await store.playlists(), isEmpty);
    expect((await store.favorites()).single.id, item.id);
    expect((await store.recentSearches()).single.id, item.id);
  });

  test('local store safely ignores corrupt collection json', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': '{bad json',
      'recent_searches': '{bad json',
      'playlists': '{bad json',
    });
    final store = LocalStore();

    expect(await store.favorites(), isEmpty);
    expect(await store.recentSearches(), isEmpty);
    expect(await store.playlists(), isEmpty);
  });
}

SearchResult _track() {
  return const SearchResult(
    id: 'bilibili:BV123',
    source: 'bilibili',
    videoId: 'BV123',
    title: '清明雨上 MV',
    artist: '许嵩',
    duration: 240,
    pageUrl: 'https://www.bilibili.com/video/BV123',
  );
}

Dio _dioWith(Map<String, _FakeResponse> routes, {List<Uri>? requests}) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter(routes, requests: requests);
  return dio;
}

_FakeResponse _json(
  Object body, {
  int statusCode = 200,
  Duration delay = Duration.zero,
}) {
  return _FakeResponse(
    jsonEncode(body),
    statusCode: statusCode,
    delay: delay,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

_FakeResponse _html(String body) {
  return _FakeResponse(
    body,
    headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    },
  );
}

class _FakeResponse {
  const _FakeResponse(
    this.body, {
    this.statusCode = 200,
    this.delay = Duration.zero,
    this.headers = const {},
  });

  final String body;
  final int statusCode;
  final Duration delay;
  final Map<String, List<String>> headers;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.routes, {this.requests});

  final Map<String, _FakeResponse> routes;
  final List<Uri>? requests;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests?.add(options.uri);
    final route = routes[options.uri.path];
    if (route == null) {
      throw StateError('No fake response for ${options.uri}');
    }
    if (route.delay > Duration.zero) {
      await Future<void>.delayed(route.delay);
    }
    return ResponseBody.fromString(
      route.body,
      route.statusCode,
      headers: route.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}
