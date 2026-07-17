import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'server_config_storage.dart';

// ---------------------------------------------------------------------------
// Server URL state
// ---------------------------------------------------------------------------

enum ServerUrlStatus { unknown, configured, unconfigured }

class ServerUrlState {
  const ServerUrlState({
    this.status = ServerUrlStatus.unknown,
    this.url = AppConfig.baseUrl,
  });

  final ServerUrlStatus status;
  final String url;

  bool get isConfigured => status == ServerUrlStatus.configured;

  ServerUrlState copyWith({ServerUrlStatus? status, String? url}) {
    return ServerUrlState(
      status: status ?? this.status,
      url: url ?? this.url,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ServerUrlNotifier extends Notifier<ServerUrlState> {
  @override
  ServerUrlState build() {
    _initialize();
    // Resolving persisted storage is async; start with the compile-time
    // fallback so dependent providers (dioProvider, authDioProvider) always
    // have a usable baseUrl even before storage has been read.
    return const ServerUrlState();
  }

  Future<void> _initialize() async {
    final stored = await ServerConfigStorage.getUrl();
    if (stored != null && stored.isNotEmpty) {
      state = ServerUrlState(status: ServerUrlStatus.configured, url: stored);
    } else {
      state = const ServerUrlState(status: ServerUrlStatus.unconfigured);
    }
  }

  /// Persists [url] (must already be validated/normalized, see
  /// [ServerUrlValidation.normalize]) and marks the server as configured.
  ///
  /// Callers switching to a *different* server than the one currently
  /// configured are responsible for logging the user out afterwards, since
  /// tokens are server-specific (see `ServerSetupScreen`).
  Future<void> setUrl(String url) async {
    await ServerConfigStorage.setUrl(url);
    state = ServerUrlState(status: ServerUrlStatus.configured, url: url);
  }
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, ServerUrlState>(
  ServerUrlNotifier.new,
);

// ---------------------------------------------------------------------------
// Health-check probe Dio (pre-login "Test connection" action)
// ---------------------------------------------------------------------------

typedef ServerProbeDioFactory = Dio Function(String baseUrl);

/// Builds a bare, short-timeout Dio targeting a *candidate* server URL the
/// user hasn't saved yet — kept separate from [dioProvider]/[authDioProvider]
/// (which always target the persisted/active server) so the setup screen can
/// probe a URL without touching app-wide client state.
///
/// Overridden in tests to inject a fake [HttpClientAdapter].
final serverProbeDioFactoryProvider = Provider<ServerProbeDioFactory>((ref) {
  return (baseUrl) => Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
});
