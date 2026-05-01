import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/editor_screen.dart';

class M4bChapterizerApp extends ConsumerWidget {
  const M4bChapterizerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'm4b chapterizer',
      theme: ThemeData(useMaterial3: true),
      home: const EditorScreen(),
    );
  }
}
