import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'local_store.dart';
import 'models.dart';

const _browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const _neteaseHeaders = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  'Referer': 'https://music.163.com/',
};

class LocalEchoDataSource implements EchoDataSource {
  LocalEchoDataSource({
    required LocalStore store,
    Dio? dio,
    Duration lyricsTimeout = const Duration(seconds: 5),
  })  : _store = store,
        _lyricsTimeout = lyricsTimeout,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
              ),
            );

  final LocalStore _store;
  final Dio _dio;
  final Duration _lyricsTimeout;
  final _searchCache = <String, List<SearchResult>>{};
  final _lyricsCache = <String, LyricsResponse>{};

  @override
  Future<List<SearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final cacheKey = _normalizeText(trimmed);
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;

    try {
      final results = await _searchBilibili(trimmed);
      if (results.isNotEmpty) {
        _searchCache[cacheKey] = results;
        return results;
      }
    } catch (_) {
      // Demo results keep the local-only build useful when public search fails.
    }
    return _demoSearchResults(trimmed);
  }

  @override
  Future<ResolvedMedia> resolve(SearchResult item) async {
    if (item.source == 'bilibili' && item.videoId.startsWith('BV')) {
      try {
        return await _resolveBilibili(item);
      } catch (_) {
        // Fall through to a legal preview when the public DASH endpoint changes.
      }
    }
    return _resolvePreview(item);
  }

  @override
  Future<LyricsResponse> lyrics(SearchResult item) async {
    final cacheKey = _lyricsCacheKey(item);
    final cached = _lyricsCache[cacheKey];
    if (cached != null) return cached;

    final response = await _firstLyricsWithin(item, _lyricsTimeout);
    if (response != null) {
      _lyricsCache[cacheKey] = response;
      return response;
    }
    return _demoLyrics(item);
  }

  @override
  Future<void> recordHistory(SearchResult item) {
    return _store.rememberSearchResult(item);
  }

  @override
  Future<void> addFavorite(SearchResult item) {
    return _store.addFavorite(item);
  }

  @override
  Future<void> removeFavorite(String id) {
    return _store.removeFavorite(id);
  }

  @override
  Future<List<SearchResult>> favorites() {
    return _store.favorites();
  }

  @override
  Future<List<SearchResult>> history() {
    return _store.recentSearches();
  }

  Future<List<SearchResult>> _searchBilibili(String query) async {
    final headers = {
      'User-Agent': _browserUserAgent,
      'Referer': 'https://search.bilibili.com/',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
    final htmlResults = await _trySearchBilibiliHtml(query, headers);
    if (htmlResults.isNotEmpty) return htmlResults;

    return _trySearchBilibiliApi(query, headers);
  }

  Future<List<SearchResult>> _trySearchBilibiliApi(
    String query,
    Map<String, String> headers,
  ) async {
    try {
      return await _searchBilibiliApi(query, headers);
    } catch (_) {
      return const [];
    }
  }

  Future<List<SearchResult>> _searchBilibiliApi(
    String query,
    Map<String, String> headers,
  ) async {
    final response = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/search/type',
      queryParameters: {
        'search_type': 'video',
        'keyword': query,
        'page': 1,
      },
      options: Options(headers: headers),
    );
    final payload = _asMap(response.data);
    if (payload['code'] != 0) {
      return const [];
    }

    final rawResults = (_asMap(payload['data'])['result'] as List?) ?? [];
    final results = <SearchResult>[];
    for (final raw in rawResults) {
      if (results.length >= 8) break;
      if (raw is! Map) continue;
      final bvid = raw['bvid'];
      if (bvid is! String || !bvid.startsWith('BV')) continue;

      final title = _stripHtml('${raw['title'] ?? ''}');
      final duration = _parseDuration(raw['duration']);
      final score = _scoreResult(query, title, duration);
      final pic = '${raw['pic'] ?? ''}';
      results.add(
        SearchResult(
          id: 'bilibili:$bvid',
          source: 'bilibili',
          videoId: bvid,
          title: title,
          artist: raw['author'] as String?,
          duration: duration,
          thumbnailUrl: pic.startsWith('//') ? 'https:$pic' : pic.nonEmpty,
          pageUrl: raw['arcurl'] as String? ??
              'https://www.bilibili.com/video/$bvid',
          confidence: score.confidence,
          tags: score.tags,
        ),
      );
    }
    return results;
  }

  Future<List<SearchResult>> _trySearchBilibiliHtml(
    String query,
    Map<String, String> headers,
  ) async {
    try {
      return await _searchBilibiliHtml(query, headers);
    } catch (_) {
      return const [];
    }
  }

  Future<List<SearchResult>> _searchBilibiliHtml(
    String query,
    Map<String, String> headers,
  ) async {
    final response = await _dio.get<String>(
      'https://search.bilibili.com/all',
      queryParameters: {'keyword': query},
      options: Options(headers: headers),
    );
    final cards = (response.data ?? '').split('bili-video-card__wrap');
    final results = <SearchResult>[];
    final seen = <String>{};

    for (final card in cards) {
      if (results.length >= 8) break;
      final videoMatch =
          RegExp(r'www\.bilibili\.com/video/(BV[0-9A-Za-z]+)').firstMatch(card);
      if (videoMatch == null) continue;

      final bvid = videoMatch.group(1)!;
      if (!seen.add(bvid)) continue;

      final titleMatch =
          RegExp(r'bili-video-card__info--tit"[^>]*title="([^"]+)"')
                  .firstMatch(card) ??
              RegExp(r'<img[^>]+alt="([^"]+)"').firstMatch(card);
      final title = _stripHtml(titleMatch?.group(1) ?? '$query - Bilibili');
      final durationMatch =
          RegExp(r'bili-video-card__stats__duration"[^>]*>([^<]+)')
              .firstMatch(card);
      final authorMatch = RegExp(r'bili-video-card__info--author"[^>]*>([^<]+)')
          .firstMatch(card);
      final imageMatch = RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(card);
      final image = _decodeHtmlEntities(imageMatch?.group(1) ?? '');
      final duration = _parseDuration(durationMatch?.group(1)?.trim());
      final score = _scoreResult(query, title, duration);
      if (!score.tags.contains('query-match') &&
          !score.tags.contains('partial-match')) {
        continue;
      }

      results.add(
        SearchResult(
          id: 'bilibili:$bvid',
          source: 'bilibili',
          videoId: bvid,
          title: title,
          artist:
              authorMatch == null ? null : _stripHtml(authorMatch.group(1)!),
          duration: duration,
          thumbnailUrl:
              image.startsWith('//') ? 'https:$image' : image.nonEmpty,
          pageUrl: 'https://www.bilibili.com/video/$bvid',
          confidence: score.confidence,
          tags: [...score.tags, 'html-fallback'],
        ),
      );
    }
    return results;
  }

  Future<ResolvedMedia> _resolveBilibili(SearchResult item) async {
    final pageUrl = item.pageUrl.isEmpty
        ? 'https://www.bilibili.com/video/${item.videoId}'
        : item.pageUrl;
    final headers = {
      'User-Agent': _browserUserAgent,
      'Referer': pageUrl,
      'Accept': 'application/json, text/plain, */*',
    };

    final viewResponse = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: {'bvid': item.videoId},
      options: Options(headers: headers),
    );
    final viewPayload = _asMap(viewResponse.data);
    if (viewPayload['code'] != 0) {
      throw StateError('Bilibili video metadata failed.');
    }
    final cid = _asMap(viewPayload['data'])['cid'];
    if (cid == null) {
      throw StateError('Bilibili video did not expose a playable cid.');
    }

    final playResponse = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/player/playurl',
      queryParameters: {
        'bvid': item.videoId,
        'cid': cid,
        'qn': 64,
        'fnval': 16,
        'fourk': 1,
      },
      options: Options(headers: headers),
    );
    final playPayload = _asMap(playResponse.data);
    if (playPayload['code'] != 0) {
      throw StateError('Bilibili playurl failed.');
    }

    final audio = _selectAudioStream(
      _asMap(_asMap(_asMap(playPayload['data'])['dash'])),
    );
    final streamUrl = audio?['baseUrl'] ?? audio?['base_url'];
    if (streamUrl is! String || streamUrl.isEmpty) {
      throw StateError('Bilibili did not return a public DASH audio stream.');
    }

    final requestHeaders = {
      'User-Agent': _browserUserAgent,
      'Referer': pageUrl,
    };
    return ResolvedMedia(
      streamUrl: streamUrl,
      mimeType: audio?['mimeType'] as String? ??
          audio?['mime_type'] as String? ??
          'audio/mp4',
      expiresAt: _expiresAt(streamUrl),
      source: 'bilibili-audio',
      isExperimental: true,
      externalPageUrl: pageUrl,
      requestHeaders: requestHeaders,
      waveformPeaks: _syntheticPeaks(item.videoId, buckets: 96),
    );
  }

  Future<ResolvedMedia> _resolvePreview(SearchResult item) async {
    for (final country in const ['CN', 'US']) {
      for (final term in _candidateTerms(item)) {
        final response = await _dio.get<dynamic>(
          'https://itunes.apple.com/search',
          queryParameters: {
            'term': term,
            'media': 'music',
            'entity': 'song',
            'limit': 12,
            'country': country,
          },
        );
        final selected = _selectItunesPreview(
          (_asMap(response.data)['results'] as List?) ?? [],
          term,
          item.duration,
        );
        final previewUrl = selected?['previewUrl'];
        if (selected != null && previewUrl is String) {
          final trackName = '${selected['trackName'] ?? term}';
          return ResolvedMedia(
            streamUrl: previewUrl,
            mimeType: 'audio/mp4',
            expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
            source: 'itunes-preview',
            isExperimental: false,
            externalPageUrl: selected['trackViewUrl'] as String?,
            waveformPeaks: _syntheticPeaks(trackName, buckets: 96),
          );
        }
      }
    }
    throw StateError('No legal preview audio was found for this result.');
  }

  Future<LyricsResponse?> _firstLyricsWithin(
    SearchResult item,
    Duration timeout,
  ) async {
    final completer = Completer<LyricsResponse?>();
    var remaining = 2;

    void watch(Future<LyricsResponse> future) {
      unawaited(
        future
            .then<void>((response) {
              if (!completer.isCompleted && response.lines.isNotEmpty) {
                completer.complete(response);
              }
            })
            .catchError((Object _) {})
            .whenComplete(() {
              remaining -= 1;
              if (remaining == 0 && !completer.isCompleted) {
                completer.complete(null);
              }
            }),
      );
    }

    watch(_fetchLrclibLyrics(item));
    watch(_fetchNeteaseLyrics(item));
    return completer.future.timeout(timeout, onTimeout: () => null);
  }

  Future<LyricsResponse> _fetchLrclibLyrics(SearchResult item) async {
    final metadata = _inferTrackAndArtist(item.title, item.artist);
    final title = metadata.title;
    final artist = metadata.artist;
    dynamic payload;

    for (final params in _lrclibGetParams(metadata, item.duration)) {
      final response = await _dio.get<dynamic>(
        'https://lrclib.net/api/get',
        queryParameters: params,
        options: _lrclibOptions(),
      );
      if (response.statusCode == 404) continue;
      payload = response.data;
      break;
    }

    if (payload == null) {
      for (final query in _lrclibSearchQueries(metadata)) {
        final searchResponse = await _dio.get<dynamic>(
          'https://lrclib.net/api/search',
          queryParameters: {'q': query},
          options: _lrclibOptions(),
        );
        if (searchResponse.statusCode == 404) continue;
        payload = _selectBestLrclibPayload(
          searchResponse.data,
          metadata,
          item.duration,
        );
        if (payload != null) break;
      }
    }

    final lyricPayload = _asMap(payload);
    final synced = '${lyricPayload['syncedLyrics'] ?? ''}';
    final plain = '${lyricPayload['plainLyrics'] ?? ''}';
    var lines = _parseLrc(synced);
    if (lines.isEmpty && plain.trim().isNotEmpty) {
      lines = [
        for (final entry in plain.split('\n').indexed)
          if (entry.$2.trim().isNotEmpty)
            LyricLine(timeMs: entry.$1 * 4000, text: entry.$2.trim()),
      ];
    }
    return LyricsResponse(
      title: '${lyricPayload['trackName'] ?? title}',
      artist: lyricPayload['artistName'] as String? ?? artist,
      confidence: lines.isNotEmpty && synced.trim().isNotEmpty ? 0.86 : 0.45,
      source: 'lrclib',
      lines: lines,
    );
  }

  Options _lrclibOptions() {
    return Options(
      headers: {'User-Agent': 'EchoMV/0.1 personal prototype'},
      validateStatus: (status) => status != null && status < 500,
    );
  }

  Future<LyricsResponse> _fetchNeteaseLyrics(SearchResult item) async {
    final metadata = _inferTrackAndArtist(item.title, item.artist);
    final song = await _searchNeteaseSong(metadata, item.duration);
    if (song == null) {
      return LyricsResponse(
        title: metadata.title,
        artist: metadata.artist,
        confidence: 0,
        source: 'netease',
        lines: const [],
      );
    }

    final response = await _dio.get<dynamic>(
      'https://music.163.com/api/song/lyric',
      queryParameters: {
        'id': song['id'],
        'lv': 1,
        'kv': 1,
        'tv': -1,
      },
      options: Options(headers: _neteaseHeaders),
    );
    final payload = _asMap(response.data);
    final rawLrc = '${_asMap(payload['lrc'])['lyric'] ?? ''}'.trim();
    var lines = _parseLrc(rawLrc);
    if (lines.isEmpty) {
      return LyricsResponse(
        title: '${song['name'] ?? metadata.title}',
        artist: song['artist'] as String? ?? metadata.artist,
        confidence: 0,
        source: 'netease',
        lines: const [],
      );
    }

    final translations =
        _parseTranslatedLrc('${_asMap(payload['tlyric'])['lyric'] ?? ''}');
    if (translations.isNotEmpty) {
      lines = [
        for (final line in lines)
          LyricLine(
            timeMs: line.timeMs,
            text: line.text,
            translatedText: translations[line.timeMs],
          ),
      ];
    }

    return LyricsResponse(
      title: '${song['name'] ?? metadata.title}',
      artist: song['artist'] as String? ?? metadata.artist,
      confidence: 0.82,
      source: 'netease',
      lines: lines,
    );
  }

  Future<Map<String, Object?>?> _searchNeteaseSong(
    ({String title, String? artist}) metadata,
    int? duration,
  ) async {
    final query = [
      if (metadata.artist != null) metadata.artist,
      metadata.title,
    ].join(' ').trim();
    final response = await _dio.get<dynamic>(
      'https://music.163.com/api/search/get/web',
      queryParameters: {
        'csrf_token': '',
        's': query,
        'type': 1,
        'offset': 0,
        'total': 'true',
        'limit': 8,
      },
      options: Options(headers: _neteaseHeaders),
    );
    final songs =
        (_asMap(_asMap(response.data)['result'])['songs'] as List?) ?? const [];
    final scored = <({double score, Map<String, Object?> song})>[];
    final normalizedTrack = _normalizeText(metadata.title);
    final normalizedArtist = _normalizeText(metadata.artist ?? '');

    for (final rawSong in songs) {
      final songMap = _asMap(rawSong);
      final id = songMap['id'];
      if (id == null) continue;
      final songName = '${songMap['name'] ?? ''}';
      final artists = (songMap['artists'] as List? ?? const [])
          .whereType<Map>()
          .map(_asMap)
          .map((artist) => '${artist['name'] ?? ''}')
          .where((name) => name.isNotEmpty)
          .join(' ');
      final haystack = _normalizeText('$artists $songName');
      var score = 0.0;
      if (normalizedTrack.isNotEmpty &&
          _normalizeText(songName).contains(normalizedTrack)) {
        score += 0.5;
      }
      if (normalizedArtist.isNotEmpty &&
          _normalizeText(artists).contains(normalizedArtist)) {
        score += 0.35;
      }
      if (normalizedTrack.isNotEmpty && haystack.contains(normalizedTrack)) {
        score += 0.2;
      }

      final songDuration = songMap['duration'];
      if (duration != null && songDuration is int) {
        final diff = (songDuration / 1000 - duration).abs();
        if (diff <= 20) {
          score += 0.15;
        } else if (diff >= 90) {
          score -= 0.1;
        }
      }

      scored.add((
        score: score,
        song: {
          'id': id,
          'name': songName,
          'artist': artists.isEmpty ? null : artists,
        },
      ));
    }

    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.first.song;
  }

  List<LyricLine> _parseLrc(String raw) {
    final timestamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final lines = <LyricLine>[];
    for (final rawLine in raw.split('\n')) {
      final matches = timestamp.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;
      final text = rawLine.replaceAll(timestamp, '').trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = (match.group(3) ?? '0').padRight(3, '0');
        final millis = int.parse(fraction.substring(0, 3));
        lines.add(
          LyricLine(
            timeMs: minutes * 60000 + seconds * 1000 + millis,
            text: text,
          ),
        );
      }
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  Map<int, String> _parseTranslatedLrc(String raw) {
    return {
      for (final line in _parseLrc(raw)) line.timeMs: line.text,
    };
  }

  LyricsResponse _demoLyrics(SearchResult item) {
    final title = _cleanMusicTerm(item.title);
    return LyricsResponse(
      title: title,
      artist: item.artist,
      confidence: 0.2,
      source: 'demo',
      lines: [
        const LyricLine(timeMs: 0, text: '按下播放，EchoMV 会在这里同步歌词'),
        LyricLine(timeMs: 5500, text: '正在为《$title》寻找匹配歌词'),
        const LyricLine(timeMs: 11000, text: '可以用偏移按钮微调每一行的时间'),
        const LyricLine(timeMs: 16500, text: '找到准确版本后，歌词会跟着音乐滚动'),
      ],
    );
  }

  List<SearchResult> _demoSearchResults(String query) {
    final suffix = query.hashCode.abs().toRadixString(16);
    final titles = [
      '$query - Bilibili 搜索暂不可用',
      '$query - iTunes 试听候选',
    ];
    return [
      for (final entry in titles.indexed)
        SearchResult(
          id: 'demo:${entry.$1}:$suffix',
          source: 'demo',
          videoId: 'demo-${entry.$1}-$suffix',
          title: entry.$2,
          artist: 'EchoMV Local',
          duration: 240,
          thumbnailUrl:
              'https://picsum.photos/seed/echomv-local-${entry.$1}/640/360',
          pageUrl: 'https://search.bilibili.com/all?keyword=$query',
          confidence: 0.2,
          tags: const ['demo'],
        ),
    ];
  }

  List<String> _candidateTerms(SearchResult item) {
    final title = _cleanMusicTerm(item.title);
    final artist = item.artist?.trim();
    final candidates = [
      if (artist != null && artist.isNotEmpty) '$artist $title',
      title,
    ];
    return {
      for (final term in candidates)
        if (term.trim().isNotEmpty) term.trim(),
    }.toList();
  }
}

extension on String {
  String? get nonEmpty => isEmpty ? null : this;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is String) {
    final decoded = jsonDecode(value);
    return _asMap(decoded);
  }
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  return {};
}

Map<String, dynamic>? _selectAudioStream(Map<String, dynamic> dash) {
  final streams = (dash['audio'] as List? ?? [])
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry('$key', value)))
      .where((item) => item['baseUrl'] != null || item['base_url'] != null)
      .toList();
  if (streams.isEmpty) return null;
  streams.sort(
    (a, b) => ((b['bandwidth'] as num?) ?? 0)
        .compareTo(((a['bandwidth'] as num?) ?? 0)),
  );
  return streams.first;
}

DateTime _expiresAt(String streamUrl) {
  final uri = Uri.tryParse(streamUrl);
  final deadline = uri?.queryParameters['deadline'];
  if (deadline != null) {
    final epoch = int.tryParse(deadline);
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
    }
  }
  return DateTime.now().toUtc().add(const Duration(hours: 6));
}

Map<String, dynamic>? _selectItunesPreview(
  List<dynamic> results,
  String term,
  int? requestedDuration,
) {
  final normalizedTerm = _normalizeText(term);
  final termParts =
      normalizedTerm.split(' ').where((part) => part.length > 1).toSet();
  final scored = <({double score, Map<String, dynamic> item})>[];

  for (final raw in results) {
    final item = _asMap(raw);
    if (item['previewUrl'] == null) continue;
    final track = _normalizeText('${item['trackName'] ?? ''}');
    final artist = _normalizeText('${item['artistName'] ?? ''}');
    final haystack = '$artist $track';
    var score = 0.2;
    if (track.isNotEmpty && normalizedTerm.contains(track)) score += 0.35;
    if (normalizedTerm.isNotEmpty && haystack.contains(normalizedTerm)) {
      score += 0.35;
    }
    score += math.min(
      0.3,
      termParts.where((part) => haystack.contains(part)).length * 0.08,
    );

    final durationMs = item['trackTimeMillis'];
    if (requestedDuration != null && durationMs is int) {
      final diff = (durationMs / 1000 - requestedDuration).abs();
      if (diff <= 20) {
        score += 0.12;
      } else if (diff >= 90) {
        score -= 0.08;
      }
    }
    scored.add((score: score, item: item));
  }

  if (scored.isEmpty) return null;
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.first.item;
}

int? _parseDuration(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  final parts = '$value'.split(':');
  var total = 0;
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null) return null;
    total = total * 60 + number;
  }
  return total == 0 ? null : total;
}

String _stripHtml(String value) {
  final decoded = _decodeHtmlEntities(_decodeHtmlEntities(value));
  return decoded.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}

String _decodeHtmlEntities(String value) {
  return value.replaceAllMapped(
    RegExp(r'&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos|#39);'),
    (match) {
      final entity = match.group(1)!;
      if (entity.startsWith('#x')) {
        final code = int.tryParse(entity.substring(2), radix: 16);
        return code == null ? match.group(0)! : String.fromCharCode(code);
      }
      if (entity.startsWith('#')) {
        final code = int.tryParse(entity.substring(1));
        return code == null ? match.group(0)! : String.fromCharCode(code);
      }
      return const {
            'amp': '&',
            'lt': '<',
            'gt': '>',
            'quot': '"',
            'apos': "'",
          }[entity] ??
          match.group(0)!;
    },
  );
}

String _cleanMusicTerm(String value) {
  return _stripHtml(value)
      .replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]|\([^)]*\)|（[^）]*）'), ' ')
      .replaceAll(
        RegExp(
          r'\b(official|music\s*video|lyric\s*video|lyrics?|mv|live|session|cover|remix|karaoke|instrumental|4k|8k|hi-res|2160p|1080p|720p)\b|官方|高清|修复版?|完整版?|无损音质|无损|视听|循环歌曲|字幕|伴奏|现场|翻唱|动态歌词|歌词版|纯享|合集',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[\[\]【】()（）]'), ' ')
      .replaceAll(RegExp(r'\s*[-_:：~～|]\s*'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

({String title, String? artist}) _inferTrackAndArtist(
  String title,
  String? artist,
) {
  final cleanedArtist =
      artist != null && !_looksLikeVideoUploader(artist) ? artist.trim() : null;
  final raw = _stripHtml(title)
      .replaceAll(RegExp(r'【[^】]*】|\[[^\]]*\]|\([^)]*\)|（[^）]*）'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  for (final separator in const [
    ' - ',
    ' – ',
    ' — ',
    '-',
    '~',
    '～',
    '|',
    '：',
    ':'
  ]) {
    if (!raw.contains(separator)) continue;
    final parts = raw.split(separator);
    if (parts.length < 2) continue;
    final left = _cleanMusicTerm(parts.first);
    final right = _cleanMusicTerm(parts.skip(1).join(separator));
    if (left.isNotEmpty && right.isNotEmpty) {
      return (title: right, artist: cleanedArtist ?? left);
    }
  }

  var cleanedTitle = _cleanMusicTerm(raw);
  if (cleanedArtist != null &&
      _normalizeText(cleanedTitle).startsWith(_normalizeText(cleanedArtist))) {
    cleanedTitle = cleanedTitle.substring(cleanedArtist.length).trim();
  }
  return (
    title: cleanedTitle.isEmpty ? title.trim() : cleanedTitle,
    artist: cleanedArtist,
  );
}

bool _looksLikeVideoUploader(String value) {
  final normalized = _normalizeText(value);
  const uploaderTokens = [
    'echo',
    'music',
    'mv',
    'official',
    'channel',
    '频道',
    '音乐',
    '视频',
    '搬运',
    '字幕',
  ];
  return uploaderTokens.any(normalized.contains) || value.contains('_');
}

List<String> _lrclibSearchQueries(({String title, String? artist}) metadata) {
  return {
    if (metadata.artist != null) '${metadata.artist} ${metadata.title}',
    metadata.title,
  }.toList();
}

String _lyricsCacheKey(SearchResult item) {
  final metadata = _inferTrackAndArtist(item.title, item.artist);
  return [
    _normalizeText(metadata.title),
    _normalizeText(metadata.artist ?? ''),
    item.duration ?? '',
  ].join('|');
}

List<Map<String, Object>> _lrclibGetParams(
  ({String title, String? artist}) metadata,
  int? duration,
) {
  return [
    {
      'track_name': metadata.title,
      if (metadata.artist != null) 'artist_name': metadata.artist!,
      if (duration != null) 'duration': duration,
    },
    {
      'track_name': metadata.title,
      if (metadata.artist != null) 'artist_name': metadata.artist!,
    },
    {
      'track_name': metadata.title,
      if (duration != null) 'duration': duration,
    },
    {'track_name': metadata.title},
  ];
}

Map<String, dynamic>? _selectBestLrclibPayload(
  dynamic payload,
  ({String title, String? artist}) metadata,
  int? duration,
) {
  final candidates =
      payload is List ? payload.map(_asMap).toList() : [_asMap(payload)];
  final scored = <({double score, Map<String, dynamic> payload})>[];
  for (final candidate in candidates) {
    final hasLyrics = '${candidate['syncedLyrics'] ?? ''}'.trim().isNotEmpty ||
        '${candidate['plainLyrics'] ?? ''}'.trim().isNotEmpty;
    if (!hasLyrics) continue;
    scored.add((
      score: _scoreLrclibPayload(candidate, metadata, duration),
      payload: candidate,
    ));
  }
  if (scored.isEmpty) return null;
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.first.payload;
}

double _scoreLrclibPayload(
  Map<String, dynamic> payload,
  ({String title, String? artist}) metadata,
  int? duration,
) {
  final track = _normalizeText('${payload['trackName'] ?? ''}');
  final artist = _normalizeText('${payload['artistName'] ?? ''}');
  final wantedTrack = _normalizeText(metadata.title);
  final wantedArtist = _normalizeText(metadata.artist ?? '');
  var score = 0.0;

  if (wantedTrack.isNotEmpty && track == wantedTrack) {
    score += 0.6;
  } else if (wantedTrack.isNotEmpty &&
      (track.contains(wantedTrack) || wantedTrack.contains(track))) {
    score += 0.35;
  }
  if (wantedArtist.isNotEmpty && artist == wantedArtist) {
    score += 0.3;
  } else if (wantedArtist.isNotEmpty && artist.contains(wantedArtist)) {
    score += 0.15;
  }

  final candidateDuration = payload['duration'];
  if (duration != null && candidateDuration is num) {
    final diff = (candidateDuration.toDouble() - duration).abs();
    if (diff <= 3) {
      score += 0.12;
    } else if (diff <= 20) {
      score += 0.06;
    }
  }
  return score;
}

String _normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

({double confidence, List<String> tags}) _scoreResult(
  String query,
  String title,
  int? duration,
) {
  final normalizedQuery = _normalizeText(query);
  final normalizedTitle = _normalizeText(title);
  var score = 0.12;
  final tags = <String>[];

  if (normalizedQuery.isNotEmpty && normalizedTitle.contains(normalizedQuery)) {
    score += 0.7;
    tags.add('query-match');
  } else {
    final parts =
        normalizedQuery.split(' ').where((part) => part.length > 1).toList();
    final matches =
        parts.where((part) => normalizedTitle.contains(part)).length;
    if (matches > 0) {
      score += math.min(0.45, matches * 0.15);
      tags.add('partial-match');
    }
  }

  if (duration != null && duration >= 60 && duration <= 600) {
    score += 0.08;
    tags.add('music-duration');
  }

  return (confidence: score.clamp(0, 1).toDouble(), tags: tags);
}

List<double> _syntheticPeaks(String seed, {required int buckets}) {
  final base = seed.codeUnits.fold<int>(0, (sum, code) => sum + code);
  return [
    for (var index = 0; index < buckets; index++)
      double.parse(
        (0.18 + (((base == 0 ? 1 : base) * (index + 7)) % 73) / 100)
            .clamp(0.0, 1.0)
            .toStringAsFixed(2),
      ),
  ];
}
