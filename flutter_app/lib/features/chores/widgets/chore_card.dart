import 'package:flutter/material.dart';

import '../../household/models/member_model.dart';
import '../models/chore_model.dart';

const _teal = Color(0xFF0D9488);

// ---------------------------------------------------------------------------
// Avatar colour palette
// ---------------------------------------------------------------------------

const List<Color> _avatarColors = [
  Color(0xFF14B8A6),
  Color(0xFF0EA5E9),
  Color(0xFF8B5CF6),
  Color(0xFF22C55E),
  Color(0xFFF472B6),
  Color(0xFFF97316),
];

Color _colorForName(String name) {
  if (name.isEmpty) return _avatarColors[0];
  return _avatarColors[name.codeUnitAt(0) % _avatarColors.length];
}

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
    final catColor =
        categoryColors[chore.category] ?? const Color(0xFF9CA3AF);
    final catLabel = categoryLabels[chore.category] ?? chore.category;
    final isRecurring = chore.choreType == 'recurring';
    final isComplete = chore.status == 'complete';
    final isOverdue = chore.isOverdue;

    // Done state colours from design spec
    final cardBg = isComplete ? const Color(0xFFF4F9F8) : Colors.white;
    final cardBorder =
        isComplete ? const Color(0xFFE6EFED) : const Color(0xFFEBF1F0);
    final titleColor =
        isComplete ? const Color(0xFF9FB6B3) : const Color(0xFF0F2E2C);
    final metaColor =
        isComplete ? const Color(0xFFB3C6C3) : const Color(0xFF8AA19E);

    // Due date colour: teal if today + pending, red if overdue, else meta
    final todayAndPending = !isComplete && !isOverdue && _isToday(chore.dueDate);
    final dueColor = isComplete
        ? metaColor
        : (isOverdue
            ? const Color(0xFFF87171)
            : (todayAndPending ? const Color(0xFF0D9488) : metaColor));

    Widget statusCircle =
        _StatusCircle(isComplete: isComplete, isOverdue: isOverdue);

    if (onCompleteTap != null && !isComplete) {
      statusCircle = GestureDetector(
        key: Key('mark_done_button_${chore.id}'),
        onTap: onCompleteTap,
        child: statusCircle,
      );
    }

    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: cardBorder),
        borderRadius: BorderRadius.circular(18),
      ),
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
                      decoration:
                          isComplete ? TextDecoration.lineThrough : null,
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
                    _DueDateRow(
                      date: chore.dueDate,
                      dueColor: dueColor,
                    ),
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
    );

    if (isAdmin) {
      card = GestureDetector(
        onLongPress: () => _showAdminMenu(context),
        child: card,
      );
    }

    return card;
  }

  // ---------------------------------------------------------------------------
  // Admin context menu
  // ---------------------------------------------------------------------------

  void _showAdminMenu(BuildContext context) {
    final canReassign = onReassign != null &&
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateStr =
        '${months[chore.dueDate.month - 1]} ${chore.dueDate.day}';

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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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

    final borderColor =
        isComplete ? teal : (isOverdue ? borderOverdue : borderIdle);
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
              style:
                  theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Effort: ${_capitalize(chore.effortLevel)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.grey.shade600),
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
                  const Icon(Icons.star_rounded,
                      color: Color(0xFFFBBF24), size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Complete this task and earn ${chore.pointValue} points!',
                      key: const Key('confirm_points_text'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
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
// Mini avatar (18×18)
// ---------------------------------------------------------------------------

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = _colorForName(name);
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
