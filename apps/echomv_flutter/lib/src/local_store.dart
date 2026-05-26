import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class LocalStore {
  static const _lyricOffsetsKey = 'lyric_offsets';
  static const _recentSearchesKey = 'recent_searches';

  Future<Map<String, int>> lyricOffsets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lyricOffsetsKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, value as int));
  }

  Future<void> saveLyricOffset(String itemId, int offsetMs) async {
    final prefs = await SharedPreferences.getInstance();
    final offsets = await lyricOffsets();
    offsets[itemId] = offsetMs;
    await prefs.setString(_lyricOffsetsKey, jsonEncode(offsets));
  }

  Future<List<SearchResult>> recentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentSearchesKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> rememberSearchResult(SearchResult item) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await recentSearches();
    final next = [
      item,
      ...current.where((value) => value.id != item.id),
    ].take(30).map((value) => value.toJson()).toList();
    await prefs.setString(_recentSearchesKey, jsonEncode(next));
  }
}
