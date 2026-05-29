import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echomv_flutter/main.dart';
import 'package:echomv_flutter/src/api_client.dart';
import 'package:echomv_flutter/src/app_controller.dart';
import 'package:echomv_flutter/src/local_store.dart';
import 'package:echomv_flutter/src/models.dart';

void main() {
  testWidgets('EchoMV app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_FakeEchoApiClient()),
        ],
        child: const EchoMvApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('输入歌曲名称开始搜索'), findsOneWidget);
  });

  testWidgets('lyrics center active line until manual scroll hold expires',
      (WidgetTester tester) async {
    _setDesktopSize(tester);

    final controller = _TestEchoController();
    controller.setEchoState(_playingState(activeIndex: 10, isPlaying: false));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          echoControllerProvider.overrideWith((ref) => controller),
        ],
        child: const EchoMvApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final listFinder = find.byKey(const ValueKey('lyrics-scroll-view'));
    expect(
        _scrollOffset(tester, listFinder), moreOrLessEquals(304, epsilon: 1));

    await tester.drag(listFinder, const Offset(0, -80));
    await tester.pump();
    final manualOffset = _scrollOffset(tester, listFinder);
    expect(manualOffset, greaterThan(304));

    controller.setEchoState(_playingState(activeIndex: 15, isPlaying: false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(_scrollOffset(tester, listFinder),
        moreOrLessEquals(manualOffset, epsilon: 1));

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        _scrollOffset(tester, listFinder), moreOrLessEquals(494, epsilon: 2));
  });

  testWidgets('cover rotates while playing, pauses, and resets for a new song',
      (WidgetTester tester) async {
    _setDesktopSize(tester);

    final controller = _TestEchoController();
    controller.setEchoState(_playingState(activeIndex: 0, isPlaying: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          echoControllerProvider.overrideWith((ref) => controller),
        ],
        child: const EchoMvApp(),
      ),
    );
    await tester.pump();
    final first = _coverTurns(tester);

    await tester.pump(const Duration(seconds: 2));
    final rotating = _coverTurns(tester);
    expect(rotating, isNot(equals(first)));

    controller.setEchoState(_playingState(activeIndex: 0, isPlaying: false));
    await tester.pump();
    final paused = _coverTurns(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(_coverTurns(tester), paused);

    controller.setEchoState(_playingState(
      id: 'next-song',
      activeIndex: 0,
      isPlaying: false,
    ));
    await tester.pump();
    expect(_coverTurns(tester), 0);
  });

  testWidgets('desktop sidebar switches to library collections',
      (WidgetTester tester) async {
    _setDesktopSize(tester);
    final controller = _TestEchoController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          echoControllerProvider.overrideWith((ref) => controller),
        ],
        child: const EchoMvApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('收藏').first);
    await tester.pumpAndSettle();

    expect(controller.state.selectedCollectionView, CollectionView.favorites);
    expect(find.text('曲库'), findsOneWidget);
    expect(find.text('还没有收藏'), findsOneWidget);
  });
}

class _FakeEchoApiClient extends EchoApiClient {
  @override
  Future<List<SearchResult>> favorites() async => [];

  @override
  Future<List<SearchResult>> history() async => [];
}

class _TestEchoController extends EchoController {
  _TestEchoController() : super(_FakeEchoApiClient(), _FakeLocalStore());

  void setEchoState(EchoState next) {
    state = next;
  }

  @override
  Future<void> refreshCollections() async {}
}

class _FakeLocalStore extends LocalStore {
  @override
  Future<Map<String, int>> lyricOffsets() async => {};

  @override
  Future<void> rememberSearchResult(SearchResult item) async {}

  @override
  Future<List<SearchResult>> recentSearches() async => [];

  @override
  Future<List<Playlist>> playlists() async => [];
}

EchoState _playingState({
  String id = 'song',
  required int activeIndex,
  required bool isPlaying,
}) {
  final item = SearchResult(
    id: id,
    source: 'youtube',
    videoId: id,
    title: 'Song $id',
    pageUrl: 'https://example.test/$id',
  );
  return EchoState(
    current: item,
    media: ResolvedMedia(
      streamUrl: 'https://example.test/$id.mp3',
      mimeType: 'audio/mpeg',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      source: 'test',
      isExperimental: false,
      waveformPeaks:
          List<double>.generate(96, (index) => (index % 12 + 1) / 12),
    ),
    lyrics: List<LyricLine>.generate(
      24,
      (index) => LyricLine(timeMs: index * 1000, text: 'Line $index'),
    ),
    position: Duration(seconds: activeIndex),
    duration: const Duration(seconds: 24),
    isPlaying: isPlaying,
  );
}

double _scrollOffset(WidgetTester tester, Finder finder) {
  final scrollable =
      find.descendant(of: finder, matching: find.byType(Scrollable));
  return tester.state<ScrollableState>(scrollable).position.pixels;
}

void _setDesktopSize(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

double _coverTurns(WidgetTester tester) {
  final rotation = tester.widget<RotationTransition>(
    find.byKey(const ValueKey('cover-rotation')),
  );
  return rotation.turns.value;
}
