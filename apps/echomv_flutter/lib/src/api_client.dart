import 'package:dio/dio.dart';

import 'models.dart';

const defaultApiBase = String.fromEnvironment(
  'ECHOMV_API_BASE',
  defaultValue: 'http://127.0.0.1:8787',
);

class EchoApiClient {
  EchoApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: defaultApiBase,
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
              ),
            );

  final Dio _dio;

  Future<List<SearchResult>> search(String query) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/search',
      queryParameters: {'q': query, 'sources': 'bilibili,youtube'},
    );
    return (response.data ?? const [])
        .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ResolvedMedia> resolve(SearchResult item) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/resolve',
      data: item.toJson(),
    );
    return ResolvedMedia.fromJson(response.data!);
  }

  Future<LyricsResponse> lyrics(SearchResult item) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/lyrics',
      queryParameters: {
        'title': item.title,
        if (item.artist != null) 'artist': item.artist,
        if (item.duration != null) 'duration': item.duration,
      },
    );
    return LyricsResponse.fromJson(response.data!);
  }

  Future<void> recordHistory(SearchResult item) async {
    await _dio.post('/api/history', data: {'item': item.toJson()});
  }

  Future<void> addFavorite(SearchResult item) async {
    await _dio.post('/api/favorites', data: {'item': item.toJson()});
  }

  Future<void> removeFavorite(String id) async {
    await _dio.delete('/api/favorites/$id');
  }

  Future<List<SearchResult>> favorites() async {
    final response = await _dio.get<List<dynamic>>('/api/favorites');
    return (response.data ?? const [])
        .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SearchResult>> history() async {
    final response = await _dio.get<List<dynamic>>('/api/history');
    return (response.data ?? const [])
        .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
