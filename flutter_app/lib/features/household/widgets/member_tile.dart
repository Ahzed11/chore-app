import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/member_model.dart';
import '../providers/members_provider.dart';

// ---------------------------------------------------------------------------
// Avatar colour palette — deterministic colour from first letter
// ---------------------------------------------------------------------------

const List<Color> _avatarColors = [
  Color(0xFF3F51B5), // Indigo
  Color(0xFF009688), // Teal
  Color(0xFF4CAF50), // Green
  Color(0xFFFF5722), // Deep Orange
  Color(0xFF9C27B0), // Purple
  Color(0xFF2196F3), // Blue
  Color(0xFFE91E63), // Pink
  Color(0xFF607D8B), // Blue Grey
];

Color _colorForName(String name) {
  if (name.isEmpty) return _avatarColors[0];
  return _avatarColors[name.codeUnitAt(0) % _avatarColors.length];
}

// ---------------------------------------------------------------------------
// MemberTile
// ---------------------------------------------------------------------------

class MemberTile extends ConsumerWidget {
  const MemberTile({
    super.key,
    required this.member,
    required this.householdId,
    required this.currentUserId,
  });

  final MemberModel member;
  final String householdId;
  final String? currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrentUser = member.userId == currentUserId;
    final initial =
        member.displayName.isNotEmpty ? member.displayName[0].toUpperCase() : '?';
    final avatarColor = _colorForName(member.displayName);
    final joinedFormatted =
        DateFormat('MMM yyyy').format(member.joinedAt);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: avatarColor,
        foregroundColor: Colors.white,
        child: Text(
          initial,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(
        member.displayName,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            _RoleBadge(isAdmin: member.isAdmin, userId: member.userId),
            const SizedBox(width: 8),
            Text(
              'since $joinedFormatted',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ],
        ),
      ),
      trailing: isCurrentUser
          ? null
          : _MemberPopupMenu(
              member: member,
              householdId: householdId,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role badge chip
// ---------------------------------------------------------------------------

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.isAdmin, required this.userId});

  final bool isAdmin;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Chip(
      key: Key(isAdmin ? 'role_badge_admin_$userId' : 'role_badge_member_$userId'),
      label: Text(
        isAdmin ? 'Admin' : 'Member',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isAdmin ? Colors.amber.shade900 : Colors.grey.shade700,
        ),
      ),
      backgroundColor:
          isAdmin ? Colors.amber.shade100 : Colors.grey.shade200,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      side: BorderSide.none,
    );
  }
}

// ---------------------------------------------------------------------------
// Popup menu
// ---------------------------------------------------------------------------

class _MemberPopupMenu extends ConsumerWidget {
  const _MemberPopupMenu({
    required this.member,
    required this.householdId,
  });

  final MemberModel member;
  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_MenuAction>(
      key: Key('member_menu_${member.userId}'),
      onSelected: (action) => _handleAction(context, ref, action),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _MenuAction.changeRole,
          child: Text(
            member.isAdmin ? 'Change to Member' : 'Change to Admin',
          ),
        ),
        PopupMenuItem(
          value: _MenuAction.remove,
          child: Text(
            'Remove from household',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.changeRole:
        await _changeRole(context, ref);
      case _MenuAction.remove:
        await _confirmRemove(context, ref);
    }
  }

  Future<void> _changeRole(BuildContext context, WidgetRef ref) async {
    final newRole = member.isAdmin ? 'member' : 'admin';
    try {
      await ref
          .read(membersNotifierProvider(householdId).notifier)
          .changeRole(member.userId, newRole);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to change role: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member'),
        content: Text(
          'Remove ${member.displayName} from the household?',
        ),
        actions: [
          TextButton(
            key: const Key('remove_cancel_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('remove_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
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
          SnackBar(
            key: const Key('sole_admin_snackbar'),
            content: const Text('Cannot remove the sole admin.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove member: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

enum _MenuAction { changeRole, remove }
