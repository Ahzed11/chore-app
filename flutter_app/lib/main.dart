import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'shared/theme/app_theme.dart';

void main() {
  // The bundled Outfit font (see `shared/theme/app_theme.dart`) ships under
  // the OFL — register its license so it shows up in the standard licenses
  // page (Settings > About > Licenses / `showLicensePage`).
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/Outfit-OFL.txt');
    yield LicenseEntryWithLineBreaks(<String>['Outfit'], license);
  });

  runApp(const ProviderScope(child: ChoreApp()));
}

class ChoreApp extends ConsumerWidget {
  const ChoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'ChoreApp',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
