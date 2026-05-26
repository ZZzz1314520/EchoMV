class SearchResult {
  const SearchResult({
    required this.id,
    required this.source,
    required this.videoId,
    required this.title,
    required this.pageUrl,
    this.artist,
    this.duration,
    this.thumbnailUrl,
    this.confidence = 0,
    this.tags = const [],
  });

  final String id;
  final String source;
  final String videoId;
  final String title;
  final String? artist;
  final int? duration;
  final String? thumbnailUrl;
  final String pageUrl;
  final double confidence;
  final List<String> tags;

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        id: json['id'] as String,
        source: json['source'] as String,
        videoId: json['videoId'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String?,
        duration: json['duration'] as int?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        pageUrl: json['pageUrl'] as String,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'duration': duration,
        'thumbnailUrl': thumbnailUrl,
        'pageUrl': pageUrl,
        'confidence': confidence,
        'tags': tags,
      };
}

class ResolvedMedia {
  const ResolvedMedia({
    required this.streamUrl,
    required this.mimeType,
    required this.expiresAt,
    required this.source,
    required this.isExperimental,
    this.waveformPeaks,
    this.externalPageUrl,
    this.requestHeaders = const {},
  });

  final String streamUrl;
  final String mimeType;
  final DateTime expiresAt;
  final String source;
  final bool isExperimental;
  final List<double>? waveformPeaks;
  final String? externalPageUrl;
  final Map<String, String> requestHeaders;

  factory ResolvedMedia.fromJson(Map<String, dynamic> json) => ResolvedMedia(
        streamUrl: json['streamUrl'] as String,
        mimeType: json['mimeType'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        source: json['source'] as String,
        isExperimental: json['isExperimental'] as bool,
        waveformPeaks: (json['waveformPeaks'] as List<dynamic>?)
            ?.map((value) => (value as num).toDouble())
            .toList(),
        externalPageUrl: json['externalPageUrl'] as String?,
        requestHeaders:
            (json['requestHeaders'] as Map<String, dynamic>? ?? const {})
                .map((key, value) => MapEntry(key, value as String)),
      );
}

class LyricLine {
  const LyricLine({
    required this.timeMs,
    required this.text,
    this.translatedText,
  });

  final int timeMs;
  final String text;
  final String? translatedText;

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
        timeMs: json['timeMs'] as int,
        text: json['text'] as String,
        translatedText: json['translatedText'] as String?,
      );
}

class LyricsResponse {
  const LyricsResponse({
    required this.title,
    required this.confidence,
    required this.source,
    required this.lines,
    this.artist,
  });

  final String title;
  final String? artist;
  final double confidence;
  final String source;
  final List<LyricLine> lines;

  factory LyricsResponse.fromJson(Map<String, dynamic> json) => LyricsResponse(
        title: json['title'] as String,
        artist: json['artist'] as String?,
        confidence: (json['confidence'] as num).toDouble(),
        source: json['source'] as String,
        lines: (json['lines'] as List<dynamic>)
            .map((line) => LyricLine.fromJson(line as Map<String, dynamic>))
            .toList(),
      );
}
