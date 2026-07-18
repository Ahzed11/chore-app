import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/chore_constants.dart';
import '../../../router/app_router.dart';
import '../../../shared/widgets/accessible_tap.dart';
import '../../../shared/widgets/avatar_colors.dart';
import '../../household/models/member_model.dart';
import '../models/chore_form_init_data.dart';
import '../models/chore_model.dart';
import '../providers/chores_provider.dart';

const _teal = Color(0xFF0D9488);

bool _isToday(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

// ---------------------------------------------------------------------------
// ChoreCard
// ---------------------------------------------------------------------------

class ChoreCard extends StatelessWidget {
  const ChoreCard({
    super.key,
    required this.chore,
    this.isAdmin = false,
    this.onDeleteSeries,
    this.showAssignee = true,
    this.onCompleteTap,
    this.members = const [],
    this.onReassign,
  });

  final ChoreModel chore;
  final bool isAdmin;
  final VoidCallback? onDeleteSeries;

  /// When false, the assignee row is replaced by a calendar-icon + due date row.
  final bool showAssignee;

  /// If non-null and the chore is not complete, the status circle becomes tappable.
  final VoidCallback? onCompleteTap;

  /// Household members available to reassign this chore to. Passed down from
  /// the parent screen (`membersNotifierProvider`) rather than fetched here.
  final List<MemberModel> members;

  /// Called with the selected member's `userId` when the admin picks a new
  /// assignee from the reassign sheet. When null the "Reassign chore" action
  /// is hidden.
  final ValueChanged<String>? onReassign;

  @override
  Widget build(BuildContext context) {
    final catColor = categoryColors[chore.category] ?? const Color(0xFF9CA3AF);
    final catLabel = categoryLabels[chore.category] ?? chore.category;
    final isRecurring = chore.choreType == 'recurring';
    final isComplete = chore.status == 'complete';
    final isOverdue = chore.isOverdue;

    // Done state colours from design spec
    final cardBg = isComplete ? const Color(0xFFF4F9F8) : Colors.white;
    final cardBorder = isComplete
        ? const Color(0xFFE6EFED)
        : const Color(0xFFEBF1F0);
    final titleColor = isComplete
        ? const Color(0xFF9FB6B3)
        : const Color(0xFF0F2E2C);
    final metaColor = isComplete
        ? const Color(0xFFB3C6C3)
        : const Color(0xFF8AA19E);

    // Due date colour: teal if today + pending, red if overdue, else meta
    final todayAndPending =
        !isComplete && !isOverdue && _isToday(chore.dueDate);
    final dueColor = isComplete
        ? metaColor
        : (isOverdue
              ? const Color(0xFFF87171)
              : (todayAndPending ? const Color(0xFF0D9488) : metaColor));

    final statusLabel = isComplete
        ? 'Completed'
        : (isOverdue ? 'Overdue' : 'Pending');

    Widget statusCircle = _StatusCircle(
      isComplete: isComplete,
      isOverdue: isOverdue,
    );

    if (onCompleteTap != null && !isComplete) {
      // The visible circle is 30dp (below the 48dp minimum tap-target size);
      // `OverflowBox` lets the tap/ripple area grow to 48dp without shifting
      // the surrounding Row layout (TASK-066) — the extra hit area simply
      // overflows the 30dp slot the Row still measures.
      statusCircle = SizedBox(
        width: 30,
        height: 30,
        child: OverflowBox(
          minWidth: 48,
          minHeight: 48,
          maxWidth: 48,
          maxHeight: 48,
          child: AccessibleTap(
            key: Key('mark_done_button_${chore.id}'),
            onTap: onCompleteTap,
            label: 'Mark "${chore.title}" as done',
            customBorder: const CircleBorder(),
            child: statusCircle,
          ),
        ),
      );
    }

    // ---- Detail sheet tap target + admin long-press context menu ----
    final semanticLabel = [
      chore.title,
      catLabel,
      statusLabel,
      if (isRecurring) 'recurring',
      if (showAssignee)
        (chore.assigneeName != null
            ? 'assigned to ${chore.assigneeName}'
            : 'unassigned'),
      '${chore.pointValue} points',
    ].join(', ');

    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: cardBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: AccessibleTap(
        key: Key('chore_card_tap_${chore.id}'),
        onTap: () => _showDetailSheet(context),
        onLongPress: isAdmin ? () => _showAdminMenu(context) : null,
        label: semanticLabel,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ---- Status circle ----
              statusCircle,

              const SizedBox(width: 14),

              // ---- Content ----
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category row
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: catColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          catLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: metaColor,
                          ),
                        ),
                        if (isRecurring) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.refresh_rounded,
                            size: 13,
                            color: metaColor,
                          ),
                        ],
                        if (isComplete) ...[
                          const SizedBox(width: 6),
                          const _DonePill(),
                        ],
                      ],
                    ),

                    const SizedBox(height: 5),

                    // Title
                    Text(
                      chore.title,
                      key: Key('chore_title_${chore.id}'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                        decoration: isComplete
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: titleColor,
                      ),
                    ),

                    const SizedBox(height: 7),

                    // Bottom info row
                    if (showAssignee)
                      _AssigneeRow(
                        chore: chore,
                        metaColor: metaColor,
                        isOverdue: isOverdue,
                      )
                    else
                      _DueDateRow(date: chore.dueDate, dueColor: dueColor),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // ---- Points ----
              isComplete
                  ? _PointsPill(points: chore.pointsAwarded ?? chore.pointValue)
                  : Text(
                      '+${chore.pointValue}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D9488),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );

    return card;
  }

  // ---------------------------------------------------------------------------
  // Detail sheet (TASK-067 F-17 — the description was previously write-only)
  // ---------------------------------------------------------------------------

  void _showDetailSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ChoreDetailSheet(chore: chore),
    );
  }

  // ---------------------------------------------------------------------------
  // Admin context menu
  // ---------------------------------------------------------------------------

  void _showAdminMenu(BuildContext context) {
    final canReassign =
        onReassign != null &&
        (chore.status == 'pending' || chore.status == 'overdue');

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
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            if (canReassign)
              ListTile(
                key: const Key('reassign_chore_menu_item'),
                leading: const Icon(Icons.swap_horiz_rounded, color: _teal),
                title: const Text(
                  'Reassign chore',
                  style: TextStyle(color: _teal),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showMemberPicker(context);
                },
              ),
            ListTile(
              key: const Key('edit_series_menu_item'),
              leading: const Icon(Icons.edit_outlined, color: _teal),
              title: const Text('Edit series', style: TextStyle(color: _teal)),
              onTap: () {
                Navigator.of(context).pop();
                context.pushNamed(
                  AppRoutes.createChore,
                  pathParameters: {'householdId': chore.householdId},
                  extra: ChoreFormInitData.fromModel(chore),
                );
              },
            ),
            ListTile(
              key: const Key('delete_series_menu_item'),
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete series',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(context).pop();
                onDeleteSeries?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Reassign member picker
  // ---------------------------------------------------------------------------

  void _showMemberPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Reassign to',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F2E2C),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (members.isEmpty)
              const Padding(
                key: Key('no_members_to_reassign'),
                padding: EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: Text(
                  'No household members available.',
                  style: TextStyle(color: Color(0xFF8AA19E)),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isCurrent = member.userId == chore.assigneeId;
                    return ListTile(
                      key: Key('reassign_member_${member.userId}'),
                      leading: _MiniAvatar(name: member.displayName),
                      title: Text(member.displayName),
                      trailing: isCurrent
                          ? const Icon(Icons.check_rounded, color: _teal)
                          : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        onReassign?.call(member.userId);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Assignee + due date row (default — shown in All Chores)
// ---------------------------------------------------------------------------

class _AssigneeRow extends StatelessWidget {
  const _AssigneeRow({
    required this.chore,
    required this.metaColor,
    required this.isOverdue,
  });

  final ChoreModel chore;
  final Color metaColor;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateStr = '${months[chore.dueDate.month - 1]} ${chore.dueDate.day}';

    return Row(
      children: [
        _MiniAvatar(name: chore.assigneeName ?? '?'),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            chore.assigneeName ?? 'Unassigned',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: metaColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text('·', style: TextStyle(fontSize: 13, color: metaColor)),
        const SizedBox(width: 8),
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isOverdue ? const Color(0xFFF87171) : metaColor,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar icon + due date row (My Chores — no assignee)
// ---------------------------------------------------------------------------

class _DueDateRow extends StatelessWidget {
  const _DueDateRow({required this.date, required this.dueColor});

  final DateTime date;
  final Color dueColor;

  @override
  Widget build(BuildContext context) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final isToday = _isToday(date);
    final label = isToday ? 'Today' : '${months[date.month - 1]} ${date.day}';

    return Row(
      children: [
        Icon(Icons.calendar_today_outlined, size: 14, color: dueColor),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: dueColor,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status circle
// ---------------------------------------------------------------------------

class _StatusCircle extends StatelessWidget {
  const _StatusCircle({required this.isComplete, required this.isOverdue});

  final bool isComplete;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0D9488);
    const borderIdle = Color(0xFFD4E0DF);
    const borderOverdue = Color(0xFFF87171);

    final borderColor = isComplete
        ? teal
        : (isOverdue ? borderOverdue : borderIdle);
    final fillColor = isComplete ? teal : Colors.transparent;

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: isComplete
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : isOverdue
          ? Icon(Icons.priority_high, size: 14, color: Colors.red.shade400)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// "Done" pill shown in category row
// ---------------------------------------------------------------------------

class _DonePill extends StatelessWidget {
  const _DonePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFD8F0EC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 11, color: Color(0xFF0D9488)),
          SizedBox(width: 4),
          Text(
            'Done',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D9488),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teal points pill shown when chore is complete
// ---------------------------------------------------------------------------

class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0D9488),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$points',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Complete-chore confirmation sheet (shared between All Chores + My Chores)
// ---------------------------------------------------------------------------

/// Shows a bottom sheet asking the user to confirm completing [chore].
/// Returns `true` when confirmed, `false`/`null` when dismissed.
Future<bool?> showChoreCompleteSheet(BuildContext context, ChoreModel chore) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ChoreCompleteSheet(chore: chore),
  );
}

/// Shared "mark as done" flow — shows the confirmation sheet, calls the
/// complete-chore API, and surfaces a success/error snackbar. Used to be
/// duplicated near-verbatim in `chore_list_screen.dart` and
/// `my_chores_screen.dart` (TASK-065).
Future<void> confirmCompleteChore({
  required BuildContext context,
  required WidgetRef ref,
  required String householdId,
  required ChoreModel chore,
}) async {
  final scaffoldMessenger = ScaffoldMessenger.of(context);

  final confirmed = await showChoreCompleteSheet(context, chore);
  if (confirmed != true || !context.mounted) return;

  try {
    final updatedChore = await ref
        .read(choresNotifierProvider(householdId).notifier)
        .completeChore(chore.id);
    if (!context.mounted) return;
    final awarded = updatedChore.pointsAwarded ?? updatedChore.pointValue;
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('You earned $awarded points!'),
        backgroundColor: _teal,
      ),
    );
  } on DioException catch (e) {
    if (!context.mounted) return;
    final code = e.response?.statusCode;
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          code == 409
              ? 'This chore was already completed.'
              : code == 403
              ? 'You are not assigned to this chore.'
              : 'Failed to complete chore. Please try again.',
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Failed to complete chore. Please try again.'),
      ),
    );
  }
}

class _ChoreCompleteSheet extends StatelessWidget {
  const _ChoreCompleteSheet({required this.chore});

  final ChoreModel chore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Complete chore?',
              key: const Key('complete_sheet_title'),
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              chore.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Effort: ${_capitalize(chore.effortLevel)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFD8F0EC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFFBBF24),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Complete this task and earn ${chore.pointValue} points!',
                      key: const Key('confirm_points_text'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('confirm_cancel_button'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('confirm_done_button'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Complete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------------------
// Chore detail sheet — tap a card to see the description, category,
// assignee, due date, and recurrence (TASK-067 F-17: the description used to
// be write-only, only ever entered on the create/edit form).
// ---------------------------------------------------------------------------

class _ChoreDetailSheet extends StatelessWidget {
  const _ChoreDetailSheet({required this.chore});

  final ChoreModel chore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catLabel = categoryLabels[chore.category] ?? chore.category;
    final catColor = categoryColors[chore.category] ?? const Color(0xFF9CA3AF);
    final isComplete = chore.status == 'complete';
    final statusLabel = isComplete
        ? 'Completed'
        : (chore.isOverdue ? 'Overdue' : 'Pending');
    final statusColor = chore.statusColor;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              chore.title,
              key: const Key('detail_sheet_title'),
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DetailChip(
                  icon: categoryIcons[chore.category],
                  label: catLabel,
                  color: catColor,
                ),
                _DetailChip(
                  icon: isComplete
                      ? Icons.check_circle_rounded
                      : (chore.isOverdue
                            ? Icons.priority_high_rounded
                            : Icons.schedule_rounded),
                  label: statusLabel,
                  color: statusColor,
                ),
                if (chore.choreType == 'recurring')
                  const _DetailChip(
                    icon: Icons.refresh_rounded,
                    label: 'Recurring',
                    color: Color(0xFF8AA19E),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Description', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              (chore.description == null || chore.description!.trim().isEmpty)
                  ? 'No description provided.'
                  : chore.description!,
              key: const Key('detail_sheet_description'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    (chore.description == null ||
                        chore.description!.trim().isEmpty)
                    ? Colors.grey.shade500
                    : null,
                fontStyle:
                    (chore.description == null ||
                        chore.description!.trim().isEmpty)
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.person_outline_rounded,
              label: 'Assignee',
              value: chore.assigneeName ?? 'Unassigned',
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.event_outlined,
              label: chore.choreType == 'recurring' ? 'Next due' : 'Due date',
              value: DateFormat('EEE, d MMM yyyy').format(chore.dueDate),
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.star_border_rounded,
              label: 'Worth',
              value:
                  '${chore.pointsAwarded ?? chore.pointValue} points (${_capitalize(chore.effortLevel)} effort)',
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData? icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF8AA19E)),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F2E2C),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, color: Color(0xFF5B7A76)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mini avatar (18×18)
// ---------------------------------------------------------------------------

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = avatarColorForName(name);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
