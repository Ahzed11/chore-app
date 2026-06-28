import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/invite_model.dart';
import '../providers/invite_provider.dart';

class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({
    super.key,
    required this.householdId,
    this.initialInvite,
  });

  final String householdId;

  /// Pre-fetched invite passed from `HouseholdManagementScreen` via
  /// `GoRouter.extra`.  When null the screen fetches on first build.
  final InviteResponse? initialInvite;

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  InviteResponse? _invite;
  late bool _isLoading;
  String? _error;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _invite = widget.initialInvite;

    if (widget.initialInvite != null) {
      _isLoading = false;
    } else {
      // Show loading from the very first frame, then fetch.
      _isLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _generateInvite();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _generateInvite() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final invite = await ref
          .read(inviteApiProvider)
          .generateInvite(widget.householdId);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('copy_snackbar'),
        content: Text('Copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _share(String text) async {
    await Share.share(text);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _expiryText(DateTime expiresAt) {
    final diff = expiresAt.toLocal().difference(DateTime.now());
    if (diff.isNegative) return 'This invite has expired';
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    return 'Expires in $hours h $minutes min';
  }

  bool _isExpired(DateTime expiresAt) =>
      expiresAt.toLocal().isBefore(DateTime.now());

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite Members')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Full-screen loading on initial fetch (no invite to show yet).
    if (_isLoading && _invite == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('loading_indicator')),
      );
    }

    // Full-screen error when there is nothing to fall back on.
    if (_error != null && _invite == null) {
      return _ErrorView(
        message: _error!,
        onRetry: _generateInvite,
      );
    }

    final invite = _invite!;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Expiry banner ------------------------------------------------
          _ExpiryBanner(
            expiryText: _expiryText(invite.expiresAt),
            isExpired: _isExpired(invite.expiresAt),
          ),
          const SizedBox(height: 28),

          // ---- QR code ------------------------------------------------------
          Center(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: QrImageView(
                  key: const Key('qr_code'),
                  data: invite.inviteUrl,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ---- URL display --------------------------------------------------
          _UrlCard(
            inviteUrl: invite.inviteUrl,
            onCopy: () => _copyToClipboard(invite.inviteUrl),
          ),
          const SizedBox(height: 32),

          // ---- Share --------------------------------------------------------
          ElevatedButton.icon(
            key: const Key('share_button'),
            onPressed: () => _share(invite.inviteUrl),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share Link'),
          ),
          const SizedBox(height: 12),

          // ---- Regenerate ---------------------------------------------------
          OutlinedButton.icon(
            key: const Key('regenerate_button'),
            onPressed: _isLoading ? null : _generateInvite,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      key: Key('regenerate_loading'),
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            label: const Text('Regenerate Link'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expiry banner
// ---------------------------------------------------------------------------

class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner({required this.expiryText, required this.isExpired});

  final String expiryText;
  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        isExpired ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer;
    final background =
        isExpired ? colorScheme.errorContainer : colorScheme.primaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isExpired ? Icons.timer_off_rounded : Icons.timer_rounded,
            color: foreground,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            expiryText,
            key: const Key('expiry_text'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// URL display card
// ---------------------------------------------------------------------------

class _UrlCard extends StatelessWidget {
  const _UrlCard({required this.inviteUrl, required this.onCopy});

  final String inviteUrl;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('invite_url_container'),
      padding: const EdgeInsets.only(left: 16, top: 12, bottom: 12, right: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              inviteUrl,
              key: const Key('invite_url_text'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: Colors.grey.shade800,
                    height: 1.5,
                  ),
            ),
          ),
          IconButton(
            key: const Key('copy_button'),
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy link',
            onPressed: onCopy,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_off_rounded,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not generate invite',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              key: const Key('retry_button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
