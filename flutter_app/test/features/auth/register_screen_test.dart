import 'package:chore_app/features/auth/providers/auth_provider.dart';
import 'package:chore_app/features/auth/screens/register_screen.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget buildRegisterScreen({AuthFormState? initialState}) {
  return ProviderScope(
    overrides: [
      authFormProvider.overrideWith(
        () => _FakeAuthFormNotifier(initialState),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const RegisterScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Fake notifier – no Dio calls
// ---------------------------------------------------------------------------

class _FakeAuthFormNotifier extends AuthFormNotifier {
  _FakeAuthFormNotifier([AuthFormState? initial]) : _initial = initial;

  final AuthFormState? _initial;

  @override
  AuthFormState build() => _initial ?? const AuthFormState();

  @override
  Future<bool> register(
    String displayName,
    String email,
    String password,
  ) async {
    return false;
  }

  @override
  Future<bool> login(String email, String password) async {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Convenience pump helpers
// ---------------------------------------------------------------------------

/// Fills in all four fields with valid data, optionally overriding individual
/// values with the named parameters.
Future<void> fillForm(
  WidgetTester tester, {
  String displayName = 'Alice',
  String email = 'alice@example.com',
  String password = 'secret123',
  String confirmPassword = 'secret123',
}) async {
  await tester.enterText(
    find.byKey(const Key('register_display_name_field')),
    displayName,
  );
  await tester.enterText(
    find.byKey(const Key('register_email_field')),
    email,
  );
  await tester.enterText(
    find.byKey(const Key('register_password_field')),
    password,
  );
  await tester.enterText(
    find.byKey(const Key('register_confirm_password_field')),
    confirmPassword,
  );
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RegisterScreen – display name validation', () {
    testWidgets('shows error when display name is empty', (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pump();

      expect(find.text('Display name is required.'), findsOneWidget);
    });

    testWidgets('shows error when display name is a single character',
        (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      await tester.enterText(
        find.byKey(const Key('register_display_name_field')),
        'A',
      );
      await tester.pump();

      expect(
        find.text('Display name must be at least 2 characters.'),
        findsOneWidget,
      );
    });

    testWidgets('accepts a display name with 2 or more characters',
        (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      await tester.enterText(
        find.byKey(const Key('register_display_name_field')),
        'Al',
      );
      await tester.pump();

      expect(find.text('Display name is required.'), findsNothing);
      expect(
        find.text('Display name must be at least 2 characters.'),
        findsNothing,
      );
    });
  });

  group('RegisterScreen – password validation', () {
    testWidgets('shows error when password is shorter than 8 characters',
        (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'short',
      );
      await tester.pump();

      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
    });

    testWidgets('accepts a password with 8 or more characters', (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'validpass',
      );
      await tester.pump();

      expect(find.text('Password is required.'), findsNothing);
      expect(
        find.text('Password must be at least 8 characters.'),
        findsNothing,
      );
    });
  });

  group('RegisterScreen – confirm password validation', () {
    testWidgets('shows error when passwords do not match', (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'password123',
      );
      await tester.enterText(
        find.byKey(const Key('register_confirm_password_field')),
        'differentPass',
      );
      await tester.pump();

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('no error when passwords match', (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      await tester.enterText(
        find.byKey(const Key('register_password_field')),
        'password123',
      );
      await tester.enterText(
        find.byKey(const Key('register_confirm_password_field')),
        'password123',
      );
      await tester.pump();

      expect(find.text('Passwords do not match.'), findsNothing);
    });
  });

  group('RegisterScreen – password visibility toggles', () {
    testWidgets('password field is obscured by default', (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('register_password_field')),
          matching: find.byType(TextField),
        ),
      );

      expect(field.obscureText, isTrue);
    });

    testWidgets('confirm password field is obscured by default', (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('register_confirm_password_field')),
          matching: find.byType(TextField),
        ),
      );

      expect(field.obscureText, isTrue);
    });

    testWidgets('password toggle reveals and re-obscures the password field',
        (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      TextField passwordField() => tester.widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('register_password_field')),
              matching: find.byType(TextField),
            ),
          );

      expect(passwordField().obscureText, isTrue);

      await tester.tap(find.byKey(const Key('register_password_toggle')));
      await tester.pump();
      expect(passwordField().obscureText, isFalse);

      await tester.tap(find.byKey(const Key('register_password_toggle')));
      await tester.pump();
      expect(passwordField().obscureText, isTrue);
    });

    testWidgets(
        'confirm-password toggle reveals and re-obscures the confirm field',
        (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      TextField confirmField() => tester.widget<TextField>(
            find.descendant(
              of: find.byKey(
                const Key('register_confirm_password_field'),
              ),
              matching: find.byType(TextField),
            ),
          );

      expect(confirmField().obscureText, isTrue);

      await tester.tap(
        find.byKey(const Key('register_confirm_password_toggle')),
      );
      await tester.pump();
      expect(confirmField().obscureText, isFalse);

      await tester.tap(
        find.byKey(const Key('register_confirm_password_toggle')),
      );
      await tester.pump();
      expect(confirmField().obscureText, isTrue);
    });
  });

  group('RegisterScreen – submit with all-empty fields', () {
    testWidgets('shows required errors for every field when submitted blank',
        (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pump();

      expect(find.text('Display name is required.'), findsOneWidget);
      expect(find.text('Email is required.'), findsOneWidget);
      expect(find.text('Password is required.'), findsOneWidget);
      expect(find.text('Please confirm your password.'), findsOneWidget);
    });
  });

  group('RegisterScreen – inline API error', () {
    testWidgets('displays error message when state carries one', (tester) async {
      const errorMsg = 'Email already registered';
      await tester.pumpWidget(
        buildRegisterScreen(
          initialState: const AuthFormState(errorMessage: errorMsg),
        ),
      );

      expect(find.text(errorMsg), findsOneWidget);
      expect(find.byKey(const Key('register_error_message')), findsOneWidget);
    });

    testWidgets('hides error message when state has none', (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      expect(find.byKey(const Key('register_error_message')), findsNothing);
    });
  });

  group('RegisterScreen – navigation link', () {
    testWidgets('renders the login navigation link', (tester) async {
      await tester.pumpWidget(buildRegisterScreen());

      expect(find.byKey(const Key('register_login_link')), findsOneWidget);
      expect(
        find.text('Already have an account? Log in'),
        findsOneWidget,
      );
    });
  });
}
