import 'package:flutter/material.dart';

import '../models/chore_model.dart';

// ---------------------------------------------------------------------------
// ChoreCard
// ---------------------------------------------------------------------------

class ChoreCard extends StatelessWidget {
  const ChoreCard({
    super.key,
    required this.chore,
    this.isAdmin = false,
    this.onDeleteSeries,
  });

  final ChoreModel chore;
  final bool isAdmin;
  final VoidCallback? onDeleteSeries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = chore.statusColor;
    final catIcon = categoryIcons[chore.category] ?? Icons.home_repair_service;
    final catLabel =
        categoryLabels[chore.category] ?? chore.category;
    final dueDateStr = _formatDate(chore.dueDate);

    final effortLabel =
        '${_capitalize(chore.effortLevel)} ${chore.pointValue}pts';

    Widget card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status border indicator
            Container(
              width: 5,
              decoration: BoxDecoration(color: statusColor),
            ),
            // Card content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category row
                    Row(
                      children: [
                        Icon(catIcon,
                            size: 16,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          catLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        // Effort chip
                        Chip(
                          key: Key('effort_chip_${chore.id}'),
                          label: Text(effortLabel),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          labelStyle: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          backgroundColor:
                              _effortChipColor(chore.effortLevel),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Title
                    Text(
                      chore.title,
                      key: Key('chore_title_${chore.id}'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Assignee + due date row
                    Row(
                      children: [
                        // Assignee
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: chore.assigneeName != null
                              ? theme.colorScheme.onSurface
                              : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            chore.assigneeName ?? 'Unassigned',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: chore.assigneeName != null
                                  ? null
                                  : Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Due date
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: chore.isOverdue
                              ? Colors.red
                              : theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dueDateStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: chore.isOverdue ? Colors.red : null,
                            fontWeight: chore.isOverdue
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                        if (chore.isOverdue) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.warning_amber_rounded,
                            key: Key('overdue_warning_icon'),
                            size: 16,
                            color: Colors.red,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Wrap with long-press gesture for admin actions
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
    final RenderBox renderBox = context.findRenderObject()! as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height * 0.5,
        offset.dx + size.width,
        offset.dy + size.height,
      ),
      items: [
        const PopupMenuItem<String>(
          key: Key('delete_series_menu_item'),
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete series', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        onDeleteSeries?.call();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Formats a date as "Jun 25" without requiring the intl package.
  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Color _effortChipColor(String effortLevel) {
    switch (effortLevel) {
      case 'hard':
        return const Color(0xFFFFCDD2); // light red
      case 'medium':
        return const Color(0xFFFFF9C4); // light yellow
      case 'easy':
      default:
        return const Color(0xFFC8E6C9); // light green
    }
  }
}
