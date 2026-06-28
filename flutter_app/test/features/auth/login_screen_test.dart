import 'package:chore_app/features/auth/providers/auth_provider.dart';
import 'package:chore_app/features/auth/screens/login_screen.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps the widget under test with the minimum needed infrastructure:
/// a [ProviderScope] (with an overridden [authFormProvider] so no real Dio
/// calls are made) and a [MaterialApp] using [AppTheme.lightTheme].
Widget buildLoginScreen({AuthFormState? initialState}) {
  return ProviderScope(
    overrides: [
      authFormProvider.overrideWith(() => _FakeAuthFormNotifier(initialState)),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const LoginScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Fake notifier – never touches Dio
// ---------------------------------------------------------------------------

class _FakeAuthFormNotifier extends AuthFormNotifier {
  _FakeAuthFormNotifier([AuthFormState? initial]) : _initial = initial;

  final AuthFormState? _initial;

  @override
  AuthFormState build() => _initial ?? const AuthFormState();

  @override
  Future<bool> login(String email, String password) async {
    // Do nothing in widget tests – we only exercise UI / validation.
    return false;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LoginScreen – validation', () {
    testWidgets('shows email and password errors when submitted empty',
        (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      // Tap the submit button without filling in anything.
      await tester.tap(find.byKey(const Key('login_submit_button')));
      await tester.pump();

      expect(find.text('Email is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
    });

    testWidgets('shows format error for invalid email', (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'not-an-email',
      );
      await tester.pump();

      expect(
        find.text('Please enter a valid email address.'),
        findsOneWidget,
      );
    });

    testWidgets('shows min-length error when password is too short',
        (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        '1234567', // 7 chars – one short
      );
      await tester.pump();

      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
    });

    testWidgets('does not show errors for valid inputs', (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      await tester.enterText(
        find.byKey(const Key('login_email_field')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('login_password_field')),
        'securePass1',
      );
      await tester.pump();

      expect(find.text('Email is required.'), findsNothing);
      expect(find.text('Please enter a valid email address.'), findsNothing);
      expect(find.text('Password is required.'), findsNothing);
      expect(
        find.text('Password must be at least 8 characters.'),
        findsNothing,
      );
    });
  });

  group('LoginScreen – password visibility toggle', () {
    testWidgets('password field obscures text by default', (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('login_password_field')),
          matching: find.byType(TextField),
        ),
      );

      expect(field.obscureText, isTrue);
    });

    testWidgets('tapping the visibility toggle reveals password', (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      // Initially obscured.
      TextField passwordField() => tester.widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('login_password_field')),
              matching: find.byType(TextField),
            ),
          );

      expect(passwordField().obscureText, isTrue);

      // Tap the toggle.
      await tester.tap(find.byKey(const Key('login_password_toggle')));
      await tester.pump();

      expect(passwordField().obscureText, isFalse);
    });

    testWidgets('tapping the visibility toggle twice re-obscures password',
        (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      TextField passwordField() => tester.widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('login_password_field')),
              matching: find.byType(TextField),
            ),
          );

      await tester.tap(find.byKey(const Key('login_password_toggle')));
      await tester.pump();
      expect(passwordField().obscureText, isFalse);

      await tester.tap(find.byKey(const Key('login_password_toggle')));
      await tester.pump();
      expect(passwordField().obscureText, isTrue);
    });
  });

  group('LoginScreen – error display', () {
    testWidgets('displays inline API error message when state has error',
        (tester) async {
      const errorMsg = 'Invalid email or password.';
      await tester.pumpWidget(
        buildLoginScreen(
          initialState: const AuthFormState(errorMessage: errorMsg),
        ),
      );

      expect(find.text(errorMsg), findsOneWidget);
      expect(find.byKey(const Key('login_error_message')), findsOneWidget);
    });

    testWidgets('hides error message when state has no error', (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      expect(find.byKey(const Key('login_error_message')), findsNothing);
    });
  });

  group('LoginScreen – navigation link', () {
    testWidgets('renders the register navigation link', (tester) async {
      await tester.pumpWidget(buildLoginScreen());

      expect(
        find.byKey(const Key('login_register_link')),
        findsOneWidget,
      );
      expect(
        find.text("Don't have an account? Register"),
        findsOneWidget,
      );
    });
  });
}
