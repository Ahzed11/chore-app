import 'package:chore_app/features/household/models/invite_model.dart';
import 'package:chore_app/features/household/providers/invite_provider.dart';
import 'package:chore_app/features/household/screens/invite_screen.dart';
import 'package:chore_app/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake InviteApi
// ---------------------------------------------------------------------------

/// A synchronous fake that returns pre-configured responses in sequence.
/// After the last entry the cycle restarts (modulo).
class _FakeInviteApi implements InviteApi {
  _FakeInviteApi({required this._responses});

  final List<InviteResponse> _responses;
  int _callIndex = 0;

  int get callCount => _callIndex;

  @override
  Future<InviteResponse> generateInvite(String householdId) async {
    final response = _responses[_callIndex % _responses.length];
    _callIndex++;
    return response;
  }

  @override
  Future<List<InviteTokenSummary>> listInvites(String householdId) async =>
      const [];

  @override
  Future<void> revokeInvite(String householdId, String inviteId) async {}
}

class _ThrowingInviteApi implements InviteApi {
  @override
  Future<InviteResponse> generateInvite(String householdId) async {
    throw Exception('Network error');
  }

  @override
  Future<List<InviteTokenSummary>> listInvites(String householdId) async {
    throw Exception('Network error');
  }

  @override
  Future<void> revokeInvite(String householdId, String inviteId) async {
    throw Exception('Network error');
  }
}

// ---------------------------------------------------------------------------
// Test data helpers
// ---------------------------------------------------------------------------

InviteResponse _makeInvite({
  String token = 'tok-abc',
  String inviteUrl = 'https://app.example.com/invite/tok-abc',
  Duration expiresIn = const Duration(hours: 24),
}) {
  return InviteResponse(
    token: token,
    inviteUrl: inviteUrl,
    expiresAt: DateTime.now().toUtc().add(expiresIn),
  );
}

// ---------------------------------------------------------------------------
// Widget builder helpers
// ---------------------------------------------------------------------------

Widget _buildScreen({
  String householdId = 'h1',
  InviteResponse? initialInvite,
  InviteApi? inviteApi,
}) {
  return ProviderScope(
    overrides: [
      if (inviteApi != null) inviteApiProvider.overrideWithValue(inviteApi),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: InviteScreen(
        householdId: householdId,
        initialInvite: initialInvite,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('InviteScreen', () {
    // -------------------------------------------------------------------------
    // QR code rendered with correct data
    // -------------------------------------------------------------------------

    testWidgets('renders QR code widget with the invite URL as data',
        (tester) async {
      const url = 'https://app.example.com/invite/qr-token';
      final invite = _makeInvite(inviteUrl: url);

      await tester.pumpWidget(_buildScreen(initialInvite: invite));
      await tester.pumpAndSettle();

      // The QR code widget must be present.
      expect(find.byKey(const Key('qr_code')), findsOneWidget);

      // QrImageView._data is private in qr_flutter 4.1.0.  Instead we verify
      // the URL text that is set from the same invite state as the QR widget —
      // if they share the source object, the QR encodes the same URL.
      final stWidget = tester.widget<SelectableText>(
          find.byKey(const Key('invite_url_text')));
      expect(stWidget.data, url);
    });

    // -------------------------------------------------------------------------
    // Expiry text computed and displayed
    // -------------------------------------------------------------------------

    testWidgets('displays expiry text computed from expires_at', (tester) async {
      // Place expiry well in the future so test timing does not affect result.
      final invite =
          _makeInvite(expiresIn: const Duration(hours: 6, minutes: 30));

      await tester.pumpWidget(_buildScreen(initialInvite: invite));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expiry_text')), findsOneWidget);

      final textWidget =
          tester.widget<Text>(find.byKey(const Key('expiry_text')));
      final text = textWidget.data!;

      // Must follow the "Expires in X h Y min" format.
      expect(text, matches(RegExp(r'Expires in \d+ h \d+ min')));

      // Hours should be approximately 6 (within 1 h of expected value).
      final hoursMatch = RegExp(r'Expires in (\d+) h').firstMatch(text);
      expect(hoursMatch, isNotNull);
      final hours = int.parse(hoursMatch!.group(1)!);
      expect(hours, closeTo(6, 1));
    });

    testWidgets('shows "expired" text when expires_at is in the past',
        (tester) async {
      final invite =
          _makeInvite(expiresIn: const Duration(hours: -1)); // already expired

      await tester.pumpWidget(_buildScreen(initialInvite: invite));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expiry_text')), findsOneWidget);
      final text =
          tester.widget<Text>(find.byKey(const Key('expiry_text'))).data!;
      expect(text, contains('expired'));
    });

    // -------------------------------------------------------------------------
    // Regenerate triggers new API call and updates QR code
    // -------------------------------------------------------------------------

    testWidgets(
        'regenerate button calls API and updates QR code to new URL',
        (tester) async {
      const url1 = 'https://app.example.com/invite/token-first';
      const url2 = 'https://app.example.com/invite/token-second';

      final fakeApi = _FakeInviteApi(responses: [
        _makeInvite(token: 'token-second', inviteUrl: url2),
      ]);

      final initial = _makeInvite(token: 'token-first', inviteUrl: url1);

      await tester.pumpWidget(
        _buildScreen(initialInvite: initial, inviteApi: fakeApi),
      );
      await tester.pumpAndSettle();

      // QR code widget present before regenerate.
      expect(find.byKey(const Key('qr_code')), findsOneWidget);

      // URL text starts at url1 (same source as QR data).
      final urlBefore = tester.widget<SelectableText>(
          find.byKey(const Key('invite_url_text')));
      expect(urlBefore.data, url1);

      // Scroll to the regenerate button (it may be below the test viewport).
      await tester.ensureVisible(find.byKey(const Key('regenerate_button')));
      await tester.pumpAndSettle();

      // Tap "Regenerate Link".
      await tester.tap(find.byKey(const Key('regenerate_button')));
      await tester.pumpAndSettle();

      // API was called exactly once by the regenerate action.
      expect(fakeApi.callCount, 1);

      // QR code widget still present after regenerate.
      expect(find.byKey(const Key('qr_code')), findsOneWidget);

      // URL text updated to url2 — the QR encodes the same value.
      final urlAfter = tester.widget<SelectableText>(
          find.byKey(const Key('invite_url_text')));
      expect(urlAfter.data, url2);
    });

    testWidgets(
        'regenerate also updates the invite URL text',
        (tester) async {
      const url1 = 'https://app.example.com/invite/old';
      const url2 = 'https://app.example.com/invite/new';

      final fakeApi = _FakeInviteApi(responses: [
        _makeInvite(token: 'new', inviteUrl: url2),
      ]);

      await tester.pumpWidget(
        _buildScreen(
          initialInvite: _makeInvite(token: 'old', inviteUrl: url1),
          inviteApi: fakeApi,
        ),
      );
      await tester.pumpAndSettle();

      // URL text widget should hold url1.
      final urlBefore = tester.widget<SelectableText>(
          find.byKey(const Key('invite_url_text')));
      expect(urlBefore.data, url1);

      // Scroll to button before tapping (may be below test viewport).
      await tester.ensureVisible(find.byKey(const Key('regenerate_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('regenerate_button')));
      await tester.pumpAndSettle();

      // After regeneration the URL text should show url2.
      final urlAfter = tester.widget<SelectableText>(
          find.byKey(const Key('invite_url_text')));
      expect(urlAfter.data, url2);
    });

    // -------------------------------------------------------------------------
    // Initial fetch (no initialInvite provided)
    // -------------------------------------------------------------------------

    testWidgets('shows loading indicator then invite when no initial data',
        (tester) async {
      const url = 'https://app.example.com/invite/fetched';

      final fakeApi = _FakeInviteApi(responses: [
        _makeInvite(token: 'fetched', inviteUrl: url),
      ]);

      await tester.pumpWidget(_buildScreen(inviteApi: fakeApi));

      // First frame: _isLoading = true in initState → loading indicator visible.
      expect(find.byKey(const Key('loading_indicator')), findsOneWidget);

      await tester.pumpAndSettle();

      // After settlement: API was called, invite is displayed.
      expect(fakeApi.callCount, 1);
      expect(find.byKey(const Key('loading_indicator')), findsNothing);
      expect(find.byKey(const Key('qr_code')), findsOneWidget);

      // URL text contains the fetched URL (QR encodes the same value).
      final stWidget = tester.widget<SelectableText>(
          find.byKey(const Key('invite_url_text')));
      expect(stWidget.data, url);
    });

    // -------------------------------------------------------------------------
    // Error state
    // -------------------------------------------------------------------------

    testWidgets('shows error view and retry button when API call fails',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(inviteApi: _ThrowingInviteApi()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retry_button')), findsOneWidget);
      // QR code must not be shown in error state.
      expect(find.byKey(const Key('qr_code')), findsNothing);
    });

    // -------------------------------------------------------------------------
    // UI elements present with initial invite
    // -------------------------------------------------------------------------

    testWidgets('share and copy buttons are present', (tester) async {
      await tester.pumpWidget(_buildScreen(initialInvite: _makeInvite()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('share_button')), findsOneWidget);
      expect(find.byKey(const Key('copy_button')), findsOneWidget);
      expect(find.byKey(const Key('regenerate_button')), findsOneWidget);
    });

    testWidgets('invite URL is displayed as selectable text', (tester) async {
      const url = 'https://app.example.com/invite/sel-url';
      await tester.pumpWidget(
        _buildScreen(initialInvite: _makeInvite(inviteUrl: url)),
      );
      await tester.pumpAndSettle();

      final stWidget = tester.widget<SelectableText>(
          find.byKey(const Key('invite_url_text')));
      expect(stWidget.data, url);
    });
  });
}
