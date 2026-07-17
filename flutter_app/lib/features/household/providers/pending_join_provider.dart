import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Pending invite-join stash (TASK-061)
// ---------------------------------------------------------------------------

/// Holds an invite token captured from a `/join/:token` deep link while the
/// user isn't authenticated yet, so the app router can complete the join
/// automatically right after login/registration succeeds instead of losing
/// the invite.
///
/// Purely in-memory by design: a deep link opened after the process was
/// killed re-delivers the token via a fresh `VIEW` intent when the OS
/// (re)launches the app, so nothing here needs to survive a restart — and
/// stashing it in secure storage would risk silently re-joining a household
/// on a later, unrelated login if it were ever left un-cleared.
class PendingJoinNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void stash(String token) => state = token;

  void clear() => state = null;
}

final pendingJoinTokenProvider =
    NotifierProvider<PendingJoinNotifier, String?>(PendingJoinNotifier.new);
