import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chore_app/main.dart';

void main() {
  testWidgets('ChoreApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ChoreApp()),
    );
    // Let the router initialise (auth state is resolved asynchronously).
    await tester.pump();
    // The app should have rendered at least one widget.
    expect(find.byType(ProviderScope), findsOneWidget);
  });
}
