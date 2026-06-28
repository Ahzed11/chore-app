import 'package:flutter/material.dart';

import '../models/chore_model.dart';

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
    final catColor =
        categoryColors[chore.category] ?? const Color(0xFF9CA3AF);
    final catLabel = categoryLabels[chore.category] ?? chore.category;
    final isRecurring = chore.choreType == 'recurring';
    final isComplete = chore.status == 'complete';
    final isOverdue = chore.isOverdue;

    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEBF1F0)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ---- Status circle ----
            _StatusCircle(isComplete: isComplete, isOverdue: isOverdue),

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
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8AA19E),
                        ),
                      ),
                      if (isRecurring) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.refresh_rounded,
                          size: 13,
                          color: Color(0xFFB3C6C3),
                        ),
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
                      color: isComplete
                          ? const Color(0xFF8AA19E)
                          : const Color(0xFF0F2E2C),
                      decoration:
                          isComplete ? TextDecoration.lineThrough : null,
                      decorationColor: const Color(0xFF8AA19E),
                    ),
                  ),

                  const SizedBox(height: 7),

                  // Assignee + due date row
                  Row(
                    children: [
                      _MiniAvatar(
                        name: chore.assigneeName ?? '?',
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          chore.assigneeName ?? 'Unassigned',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF8AA19E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '·',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8AA19E),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(chore.dueDate),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isOverdue
                              ? const Color(0xFFF87171)
                              : const Color(0xFF8AA19E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ---- Points ----
            Text(
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
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
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
              ? Icon(
                  Icons.priority_high,
                  size: 14,
                  color: Colors.red.shade400,
                )
              : null,
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
