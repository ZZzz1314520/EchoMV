import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/shell.dart';
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: EchoMvApp()));
}

class EchoMvApp extends StatelessWidget {
  const EchoMvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EchoMV',
      debugShowCheckedModeBanner: false,
      theme: buildEchoTheme(),
      home: const EchoShell(),
    );
  }
}
