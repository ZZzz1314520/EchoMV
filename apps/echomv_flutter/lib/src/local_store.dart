import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class LocalStore {
  static const _lyricOffsetsKey = 'lyric_offsets';
  static const _recentSearchesKey = 'recent_searches';
  static const _favoritesKey = 'favorites';
  static const _playlistsKey = 'playlists';

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
    return _readSearchResultList(_recentSearchesKey);
  }

  Future<void> rememberSearchResult(SearchResult item) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await recentSearches();
    final next = [
      item,
      ...current.where((value) => value.id != item.id),
    ].take(50).map((value) => value.toJson()).toList();
    await prefs.setString(_recentSearchesKey, jsonEncode(next));
  }

  Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
  }

  Future<List<SearchResult>> favorites() async {
    return _readSearchResultList(_favoritesKey);
  }

  Future<void> addFavorite(SearchResult item) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await favorites();
    final next = [
      item,
      ...current.where((value) => value.id != item.id),
    ].map((value) => value.toJson()).toList();
    await prefs.setString(_favoritesKey, jsonEncode(next));
  }

  Future<void> removeFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final next = [
      for (final item in await favorites())
        if (item.id != id) item.toJson(),
    ];
    await prefs.setString(_favoritesKey, jsonEncode(next));
  }

  Future<List<Playlist>> playlists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Playlist> createPlaylist(String name) async {
    final now = DateTime.now();
    final playlist = Playlist(
      id: 'playlist_${now.microsecondsSinceEpoch}',
      name: _normalizePlaylistName(name),
      items: const [],
      createdAt: now,
      updatedAt: now,
    );
    final next = [playlist, ...await playlists()];
    await _writePlaylists(next);
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final trimmed = _normalizePlaylistName(name);
    final now = DateTime.now();
    final next = [
      for (final playlist in await playlists())
        if (playlist.id == id)
          playlist.copyWith(name: trimmed, updatedAt: now)
        else
          playlist,
    ];
    await _writePlaylists(next);
  }

  Future<void> deletePlaylist(String id) async {
    final next = [
      for (final playlist in await playlists())
        if (playlist.id != id) playlist,
    ];
    await _writePlaylists(next);
  }

  Future<void> addToPlaylist(String playlistId, SearchResult item) async {
    final now = DateTime.now();
    final next = [
      for (final playlist in await playlists())
        if (playlist.id == playlistId)
          playlist.copyWith(
            items: [
              item,
              ...playlist.items.where((value) => value.id != item.id),
            ],
            updatedAt: now,
          )
        else
          playlist,
    ];
    await _writePlaylists(next);
  }

  Future<void> removeFromPlaylist(String playlistId, String itemId) async {
    final now = DateTime.now();
    final next = [
      for (final playlist in await playlists())
        if (playlist.id == playlistId)
          playlist.copyWith(
            items: [
              for (final item in playlist.items)
                if (item.id != itemId) item,
            ],
            updatedAt: now,
          )
        else
          playlist,
    ];
    await _writePlaylists(next);
  }

  Future<List<SearchResult>> _readSearchResultList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => SearchResult.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writePlaylists(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playlistsKey,
      jsonEncode(playlists.map((playlist) => playlist.toJson()).toList()),
    );
  }

  String _normalizePlaylistName(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '新歌单' : trimmed;
  }
}
