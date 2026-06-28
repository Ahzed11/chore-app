import 'package:flutter/material.dart';

import '../models/leaderboard_model.dart';

// ---------------------------------------------------------------------------
// Medal colours
// ---------------------------------------------------------------------------

const _goldColor = Colors.amber;
final _silverColor = Colors.grey.shade400;
const _bronzeColor = Color(0xFFCD7F32);

// ---------------------------------------------------------------------------
// LeaderboardEntryTile
// ---------------------------------------------------------------------------

class LeaderboardEntryTile extends StatelessWidget {
  const LeaderboardEntryTile({
    super.key,
    required this.entry,
    required this.isCurrentUser,
  });

  final LeaderboardEntry entry;

  /// Whether this entry belongs to the currently authenticated user.
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlightColor =
        theme.colorScheme.primaryContainer.withValues(alpha: 0.3);

    return Container(
      key: ValueKey('leaderboard_entry_${entry.userId}'),
      color: isCurrentUser ? highlightColor : null,
      child: ListTile(
        leading: _RankBadge(rank: entry.rank),
        title: Text(
          entry.displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: isCurrentUser ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${entry.choresCompleted} chores completed',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Text(
          '${entry.points} pts',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rank badge
// ---------------------------------------------------------------------------

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    if (rank == 1) {
      return _circleBadge(
        key: const Key('rank_badge_1'),
        color: _goldColor,
        label: '1',
      );
    }
    if (rank == 2) {
      return _circleBadge(
        key: const Key('rank_badge_2'),
        color: _silverColor,
        label: '2',
      );
    }
    if (rank == 3) {
      return _circleBadge(
        key: const Key('rank_badge_3'),
        color: _bronzeColor,
        label: '3',
      );
    }

    // Rank 4 and beyond — plain text number.
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Text(
          '$rank',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  /// Builds a circular medal badge [Container] with the given [key].
  ///
  /// The [Key] is placed on the [Container] so tests can directly cast the
  /// found widget to [Container] and inspect its [BoxDecoration].
  static Widget _circleBadge({
    required Key key,
    required Color color,
    required String label,
  }) {
    return Container(
      key: key,
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
