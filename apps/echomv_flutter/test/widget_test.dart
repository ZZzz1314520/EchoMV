import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echomv_flutter/main.dart';
import 'package:echomv_flutter/src/api_client.dart';
import 'package:echomv_flutter/src/app_controller.dart';
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
}

class _FakeEchoApiClient extends EchoApiClient {
  @override
  Future<List<SearchResult>> favorites() async => [];

  @override
  Future<List<SearchResult>> history() async => [];
}
