import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/config/server_config_storage.dart';
import '../../../core/config/server_url_provider.dart';

/// Shown before login when no server URL is configured yet, and reachable
/// later (with [canCancel] true) to point the app at a different server.
///
/// Entering a URL and tapping "Test Connection" validates the input, probes
/// `GET /health` on the candidate server, and — on success — persists it via
/// [serverUrlProvider] and logs the user out locally (tokens are
/// server-specific). The router's redirect logic then takes it from there:
/// once the server is configured, an unauthenticated user lands on `/login`.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key, this.canCancel = false});

  /// True when the user navigated here voluntarily to change an
  /// already-configured server (shows a close button). False on the
  /// mandatory first-run flow, where there is nothing to cancel back to.
  final bool canCancel;

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  bool _isTesting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final current = ref.read(serverUrlProvider).url;
    _urlController = TextEditingController(text: current);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Server URL is required.';
    }
    if (ServerUrlValidation.normalize(value) == null) {
      return 'Enter a full URL, including http:// or https://.';
    }
    return null;
  }

  Future<void> _testAndContinue() async {
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final normalized = ServerUrlValidation.normalize(_urlController.text);
    if (normalized == null) {
      setState(() {
        _errorMessage = 'Enter a full URL, including http:// or https://.';
      });
      return;
    }

    setState(() => _isTesting = true);

    try {
      final probe = ref.read(serverProbeDioFactoryProvider)(normalized);
      final response = await probe.get<dynamic>(ApiEndpoints.health);
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      await ref.read(serverUrlProvider.notifier).setUrl(normalized);
      // Tokens are server-specific: switching servers invalidates any
      // locally-stored session (a no-op if there was none, as on first run).
      await ref.read(authNotifierProvider.notifier).clearOnUnauthorized();

      if (!mounted) return;
      if (widget.canCancel && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      // Otherwise the router's redirect logic navigates away automatically
      // now that serverUrlProvider has flipped to `configured`.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not connect to that server. Check the URL and try again.';
      });
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: widget.canCancel
          ? AppBar(
              title: const Text('Change Server'),
              leading: IconButton(
                key: const Key('server_setup_cancel_button'),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Cancel',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.dns_rounded,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Connect to your server',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the address of your ChoreApp server.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('server_setup_url_field'),
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _testAndContinue(),
                          decoration: const InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'https://chores.example.com',
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                          validator: _validateUrl,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          key: const Key('server_setup_test_button'),
                          onPressed: _isTesting ? null : _testAndContinue,
                          child: _isTesting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Test Connection'),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            key: const Key('server_setup_error_message'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
