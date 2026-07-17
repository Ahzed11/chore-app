import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/api/friendly_error.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../leaderboard/providers/leaderboard_provider.dart';
import '../models/household_model.dart';
import '../models/member_model.dart';
import '../models/invite_model.dart';
import '../providers/household_provider.dart';
import '../providers/members_provider.dart';
import '../providers/invite_provider.dart';

// ---------------------------------------------------------------------------
// Colors & helpers
// ---------------------------------------------------------------------------

const _teal = Color(0xFF0D9488);
const _darkText = Color(0xFF0F2E2C);
const _secondaryText = Color(0xFF8AA19E);
const _bgPage = Color(0xFFF4F8F7);
const _borderCard = Color(0xFFEBF1F0);

const List<Color> _avatarColors = [
  Color(0xFF14B8A6),
  Color(0xFF0EA5E9),
  Color(0xFF8B5CF6),
  Color(0xFF22C55E),
  Color(0xFFF472B6),
  Color(0xFFF97316),
  Color(0xFF0D9488),
];

Color _avatarColor(String name) {
  if (name.isEmpty) return _avatarColors[0];
  return _avatarColors[name.codeUnitAt(0) % _avatarColors.length];
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class HouseholdManagementScreen extends ConsumerStatefulWidget {
  const HouseholdManagementScreen({super.key, required this.householdId});

  final String householdId;

  @override
  ConsumerState<HouseholdManagementScreen> createState() =>
      _HouseholdManagementScreenState();
}

class _HouseholdManagementScreenState
    extends ConsumerState<HouseholdManagementScreen> {
  bool _isEditingName = false;
  final _nameController = TextEditingController();
  bool _inviteOpen = false;
  InviteResponse? _inviteResponse;
  bool _generatingInvite = false;
  bool _copied = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Invite
  // -------------------------------------------------------------------------

  /// Opens/closes the invite accordion. Opening it only *lists* existing
  /// active invites (`GET /households/{id}/invites`) — it never generates a
  /// new token. A new token is only ever created via [_generateInvite], which
  /// is wired to an explicit "Generate new invite" button.
  void _toggleInvite() {
    setState(() => _inviteOpen = !_inviteOpen);
  }

  Future<void> _generateInvite() async {
    setState(() => _generatingInvite = true);
    try {
      final inv =
          await ref.read(inviteApiProvider).generateInvite(widget.householdId);
      if (mounted) {
        setState(() {
          _inviteResponse = inv;
          _generatingInvite = false;
        });
        // The newly created token is now the active one — refresh the list
        // so it (and the fact any older token was auto-revoked) is reflected.
        ref.invalidate(invitesProvider(widget.householdId));
      }
    } catch (e) {
      if (mounted) setState(() => _generatingInvite = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate invite: ${friendlyErrorMessage(e)}'),
          ),
        );
      }
    }
  }

  Future<void> _revokeInvite(String inviteId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(inviteApiProvider)
          .revokeInvite(widget.householdId, inviteId);
      ref.invalidate(invitesProvider(widget.householdId));
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Invite revoked.')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to revoke invite: ${friendlyErrorMessage(e)}'),
          ),
        );
      }
    }
  }

  Future<void> _copyInviteLink() async {
    if (_inviteResponse == null) return;
    await Clipboard.setData(ClipboardData(text: _inviteResponse!.inviteUrl));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  // -------------------------------------------------------------------------
  // Leave household
  // -------------------------------------------------------------------------

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('leave_dialog'),
        title: const Text('Leave household'),
        content: const Text(
          'Are you sure you want to leave this household? '
          'You will lose access to all its chores.',
        ),
        actions: [
          TextButton(
            key: const Key('leave_cancel_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('leave_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(householdsNotifierProvider.notifier)
          .leaveHousehold(widget.householdId);
      if (!mounted) return;
      router.go('/households');
    } on SoleAdminException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('sole_admin_error_dialog'),
          title: const Text('Cannot leave'),
          content: const Text(
            'You are the sole admin. Promote another member first.',
          ),
          actions: [
            TextButton(
              key: const Key('sole_admin_error_ok'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to leave household: ${friendlyErrorMessage(e)}'),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final householdsAsync = ref.watch(householdsNotifierProvider);
    final membersAsync = ref.watch(membersNotifierProvider(widget.householdId));
    final currentUserId = ref.watch(currentUserIdProvider);

    final household = householdsAsync.valueOrNull
        ?.where((h) => h.id == widget.householdId)
        .firstOrNull;

    if (householdsAsync.isLoading) {
      return const Scaffold(backgroundColor: _bgPage, body: LoadingWidget());
    }

    if (household == null) {
      return const Scaffold(
        backgroundColor: _bgPage,
        body: Center(child: Text('Household not found')),
      );
    }

    final members = membersAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: _bgPage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroCard(
                      household: household,
                      members: members,
                      isEditingName: _isEditingName,
                      nameController: _nameController,
                      onStartEdit: () {
                        _nameController.text = household.name;
                        setState(() => _isEditingName = true);
                      },
                      onSaveEdit: () async {
                        final newName = _nameController.text.trim();
                        if (newName.isEmpty || newName == household.name) {
                          setState(() => _isEditingName = false);
                          return;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(householdsNotifierProvider.notifier)
                              .updateHouseholdName(
                                widget.householdId,
                                newName,
                              );
                          if (mounted) setState(() => _isEditingName = false);
                        } catch (e) {
                          // Leave the edit UI open (and the previous name,
                          // since nothing here is optimistically mutated) so
                          // the admin sees the failure and can retry instead
                          // of silently losing their edit.
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to rename household: '
                                  '${friendlyErrorMessage(e)}',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      onCancelEdit: () =>
                          setState(() => _isEditingName = false),
                    ),
                    const SizedBox(height: 26),
                    membersAsync.when(
                      loading: () => const LoadingWidget(),
                      error: (error, _) => AppErrorWidget(
                        error: error,
                        onRetry: () => ref.invalidate(
                          membersNotifierProvider(widget.householdId),
                        ),
                      ),
                      data: (memberList) => _MembersSection(
                        members: memberList,
                        householdId: widget.householdId,
                        currentUserId: currentUserId,
                        isAdmin: household.isAdmin,
                      ),
                    ),
                    // Invite generation/listing/revocation are admin-only on
                    // the backend (`require_admin`); hide the whole section
                    // from non-admin members rather than surfacing 403s.
                    if (household.isAdmin) ...[
                      const SizedBox(height: 26),
                      _buildInviteSection(),
                    ],
                    const SizedBox(height: 26),
                    _buildDangerZone(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEF3F2))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE6EDEC)),
                color: Colors.white,
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: _darkText,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Manage Household',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: _darkText,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 11),
          child: Text(
            'INVITE',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _secondaryText,
              letterSpacing: 13 * 0.02,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _borderCard),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              GestureDetector(
                key: const Key('invite_tile'),
                onTap: _toggleInvite,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD8F0EC),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.person_add_rounded,
                          color: _teal,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Invite a housemate',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: _darkText,
                              ),
                            ),
                            SizedBox(height: 1),
                            Text(
                              'Share a link to add them',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: _secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _inviteOpen ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Color(0xFFB3C6C3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                // Only build (and therefore only start watching `invitesProvider`,
                // which triggers the GET request) once the section is actually
                // opened — avoids fetching invites the admin never looks at.
                secondChild:
                    _inviteOpen ? _buildInviteExpanded() : const SizedBox.shrink(),
                crossFadeState: _inviteOpen
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInviteExpanded() {
    final invitesAsync = ref.watch(invitesProvider(widget.householdId));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // ---- Just-generated invite: full URL + QR (session-only) --------
          // The backend never re-exposes a full token/URL after creation, so
          // this block only ever shows the invite most recently generated in
          // this session — older ones fall back to metadata-only rows below.
          if (_inviteResponse != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8F7),
                border: Border.all(color: const Color(0xFFE6EDEC)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.link_rounded,
                    size: 16,
                    color: _secondaryText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _inviteResponse!.inviteUrl,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5B7A76),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE6EDEC)),
                  borderRadius: BorderRadius.circular(16),
                ),
                // The QR encodes the `choreapp://` deep link (TASK-061) so a
                // device with the app installed opens straight into the
                // join flow instead of a browser tab. The URL row above and
                // "Copy invite link" below keep the `https://` URL — see
                // `InviteResponse.deepLink` for why.
                child: QrImageView(
                  data: _inviteResponse!.deepLink,
                  version: QrVersions.auto,
                  size: 160,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: _darkText,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: _darkText,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _copyInviteLink,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _copied ? const Color(0xFF15A394) : _teal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _copied ? 'Link copied!' : 'Copy invite link',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // ---- Generate new invite (explicit user action only) ------------
          GestureDetector(
            key: const Key('generate_invite_button'),
            onTap: _generatingInvite ? null : _generateInvite,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _teal, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_generatingInvite)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: _teal,
                        strokeWidth: 2,
                      ),
                    )
                  else
                    const Icon(Icons.add_link_rounded,
                        size: 18, color: _teal),
                  const SizedBox(width: 8),
                  Text(
                    _inviteResponse == null
                        ? 'Generate invite link'
                        : 'Generate new invite link',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _teal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ---- Active invites (metadata + revoke) --------------------------
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ACTIVE INVITES',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _secondaryText,
                letterSpacing: 11.5 * 0.02,
              ),
            ),
          ),
          const SizedBox(height: 10),
          invitesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(
                color: _teal,
                strokeWidth: 2,
              ),
            ),
            error: (error, _) => Padding(
              key: const Key('invites_error'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Failed to load invites: ${friendlyErrorMessage(error)}',
                style: const TextStyle(fontSize: 12.5, color: Colors.red),
              ),
            ),
            data: (invites) => invites.isEmpty
                ? const Padding(
                    key: Key('no_active_invites'),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No active invites',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _secondaryText,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final invite in invites)
                        _InviteTokenRow(
                          key: Key('invite_row_${invite.id}'),
                          invite: invite,
                          onRevoke: () => _revokeInvite(invite.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 11),
          child: Text(
            'DANGER ZONE',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC98A8A),
              letterSpacing: 13 * 0.02,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFF3DADA)),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDEAEA),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC4D4D),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Leave household',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: _darkText,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          "You'll lose access to all chores, points, and history.",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9A8585),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              GestureDetector(
                key: const Key('leave_household_button'),
                onTap: _confirmLeave,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFF0C4C4),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Leave household',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFDC4D4D),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero card
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.household,
    required this.members,
    required this.isEditingName,
    required this.nameController,
    required this.onStartEdit,
    required this.onSaveEdit,
    required this.onCancelEdit,
  });

  final HouseholdModel household;
  final List<MemberModel> members;
  final bool isEditingName;
  final TextEditingController nameController;
  final VoidCallback onStartEdit;
  final VoidCallback onSaveEdit;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(
        color: Colors.white.withValues(alpha: 0.45),
        width: 1.5,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: _teal,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0xB20D9488),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.home_rounded,
                  size: 26,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: isEditingName
                    ? TextField(
                        key: const Key('household_name_field'),
                        controller: nameController,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                        decoration: InputDecoration(
                          border: outlineBorder,
                          enabledBorder: outlineBorder,
                          focusedBorder: outlineBorder,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.16),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                      )
                    : Column(
                        key: const Key('household_name_tile'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            household.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Created ${DateFormat("MMM yyyy").format(household.createdAt)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              if (!isEditingName)
                GestureDetector(
                  key: const Key('edit_name_button'),
                  onTap: onStartEdit,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          if (isEditingName) ...[
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onSaveEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Text(
                        'Save',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _teal,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: GestureDetector(
                    onTap: onCancelEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Text(
                        'Cancel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!isEditingName) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 15),
            Row(
              children: [
                _MemberAvatarStack(members: members),
                const SizedBox(width: 14),
                Text(
                  '${members.length} members',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member avatar stack (hero card footer)
// ---------------------------------------------------------------------------

class _MemberAvatarStack extends StatelessWidget {
  const _MemberAvatarStack({required this.members});

  final List<MemberModel> members;

  @override
  Widget build(BuildContext context) {
    final show = members.take(4).toList();
    final extra = members.length - show.length;
    final width = show.length * 20.0 + 8 + (extra > 0 ? 20.0 : 0.0);

    return SizedBox(
      height: 28,
      width: width,
      child: Stack(
        children: [
          ...show.asMap().entries.map(
                (e) => Positioned(
                  left: e.key * 20.0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _avatarColor(e.value.displayName),
                      border: Border.all(color: _teal, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        e.value.displayName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          if (extra > 0)
            Positioned(
              left: show.length * 20.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.22),
                  border: Border.all(color: _teal, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$extra',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Members section
// ---------------------------------------------------------------------------

class _MembersSection extends StatelessWidget {
  const _MembersSection({
    required this.members,
    required this.householdId,
    required this.currentUserId,
    required this.isAdmin,
  });

  final List<MemberModel> members;
  final String householdId;
  final String? currentUserId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MEMBERS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _secondaryText,
                  letterSpacing: 13 * 0.02,
                ),
              ),
              Text(
                '${members.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB3C6C3),
                ),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _borderCard),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: List.generate(
                members.length,
                (i) => _MemberRow(
                  member: members[i],
                  index: i,
                  householdId: householdId,
                  currentUserId: currentUserId,
                  canManage: isAdmin && members[i].userId != currentUserId,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Member row
// ---------------------------------------------------------------------------

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.index,
    required this.householdId,
    required this.currentUserId,
    required this.canManage,
  });

  final MemberModel member;
  final int index;
  final String householdId;
  final String? currentUserId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: index == 0
            ? null
            : const Border(top: BorderSide(color: Color(0xFFF1F5F4))),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _avatarColor(member.displayName),
            ),
            child: Center(
              child: Text(
                member.displayName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.displayName,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: _darkText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (member.userId == currentUserId) ...[
                      const SizedBox(width: 7),
                      const _YouPill(),
                    ],
                    const SizedBox(width: 7),
                    _RolePill(
                      isAdmin: member.isAdmin,
                      userId: member.userId,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Joined ${DateFormat("MMM yyyy").format(member.joinedAt)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: _secondaryText,
                  ),
                ),
              ],
            ),
          ),
          if (canManage)
            GestureDetector(
              key: Key('member_menu_${member.userId}'),
              onTap: () =>
                  _showMemberActions(context, ref, member, householdId),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8F7),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: _secondaryText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YOU pill
// ---------------------------------------------------------------------------

class _YouPill extends StatelessWidget {
  const _YouPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _teal,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'YOU',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.36,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role pill
// ---------------------------------------------------------------------------

class _RolePill extends StatelessWidget {
  const _RolePill({required this.isAdmin, required this.userId});

  final bool isAdmin;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key(
        isAdmin ? 'role_badge_admin_$userId' : 'role_badge_member_$userId',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFFFEF3C7) : const Color(0xFFF1F6F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAdmin ? 'ADMIN' : 'MEMBER',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isAdmin
              ? const Color(0xFF92600A)
              : const Color(0xFF8AA19E),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member actions bottom sheet
// ---------------------------------------------------------------------------

void _showMemberActions(
  BuildContext context,
  WidgetRef ref,
  MemberModel member,
  String householdId,
) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            key: const Key('change_role_action'),
            leading: Icon(
              member.isAdmin
                  ? Icons.person_rounded
                  : Icons.admin_panel_settings_rounded,
              color: _teal,
            ),
            title: Text(
              member.isAdmin ? 'Change to Member' : 'Change to Admin',
            ),
            onTap: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(membersNotifierProvider(householdId).notifier)
                    .changeRole(
                      member.userId,
                      member.isAdmin ? 'member' : 'admin',
                    );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: ${friendlyErrorMessage(e)}')),
                  );
                }
              }
            },
          ),
          ListTile(
            key: const Key('remove_member_action'),
            leading:
                const Icon(Icons.person_remove_rounded, color: Colors.red),
            title: const Text(
              'Remove from household',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Remove member'),
                  content: Text(
                    'Remove ${member.displayName} from the household?',
                  ),
                  actions: [
                    TextButton(
                      key: const Key('remove_cancel_button'),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      key: const Key('remove_confirm_button'),
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              try {
                await ref
                    .read(membersNotifierProvider(householdId).notifier)
                    .removeMember(member.userId);
              } on SoleAdminException {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      key: Key('sole_admin_snackbar'),
                      content: Text('Cannot remove the sole admin.'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: ${friendlyErrorMessage(e)}')),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Active invite row (metadata + revoke)
// ---------------------------------------------------------------------------

/// A single row in the "Active invites" list. Only shows the masked
/// [InviteTokenSummary.tokenPreview] — the backend's `GET
/// /households/{id}/invites` endpoint never returns full tokens/URLs, so
/// there is no link/QR to display here (that's only ever available for the
/// invite most recently generated in this session; see [InviteResponse]).
class _InviteTokenRow extends StatelessWidget {
  const _InviteTokenRow({
    super.key,
    required this.invite,
    required this.onRevoke,
  });

  final InviteTokenSummary invite;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final expiresAt = invite.expiresAt.toLocal();
    final isExpiringSoon =
        expiresAt.difference(DateTime.now()).inHours < 24;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F7),
        border: Border.all(color: const Color(0xFFE6EDEC)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.vpn_key_rounded, size: 16, color: _secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.tokenPreview,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5B7A76),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Expires ${DateFormat("MMM d, h:mm a").format(expiresAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isExpiringSoon
                        ? const Color(0xFFDC4D4D)
                        : _secondaryText,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            key: Key('revoke_invite_${invite.id}'),
            onTap: onRevoke,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFFDEAEA),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Color(0xFFDC4D4D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
