import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chore_app/core/config/app_locale.dart';
import 'package:chore_app/main.dart';

void main() {
  testWidgets('ChoreApp renders without crashing and pins the Monday-first '
      'locale (TASK-115)', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ChoreApp()),
    );
    // Let the router initialise (auth state is resolved asynchronously).
    await tester.pump();
    // The app should have rendered at least one widget.
    expect(find.byType(ProviderScope), findsOneWidget);

    // The app's real MaterialApp must carry the pinned locale config — the
    // screen tests mirror the config via the shared constants, so they alone
    // would NOT catch a dropped wire in main.dart (adversarial review).
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, kAppLocale);
    expect(app.supportedLocales, kSupportedLocales);
  });
}
