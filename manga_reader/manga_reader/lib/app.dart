import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/format.dart';
import 'features/home/home_shell.dart';

class MangaReaderApp extends ConsumerWidget {
  const MangaReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final seedIndex = ref.watch(settingsProvider.select((s) => s.seedIndex));
    final seed = kSeedColors[clampInt(seedIndex, 0, kSeedColors.length - 1)];

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      themeMode: themeMode,
      home: const HomeShell(),
    );
  }
}
