// ---------------------------------------------------------------------------
// Scope enum
// ---------------------------------------------------------------------------

enum LeaderboardScope { allTime, thisWeek, thisMonth }

extension LeaderboardScopeExt on LeaderboardScope {
  String get apiValue => switch (this) {
        LeaderboardScope.allTime => 'all_time',
        LeaderboardScope.thisWeek => 'this_week',
        LeaderboardScope.thisMonth => 'this_month',
      };

  String get label => switch (this) {
        LeaderboardScope.allTime => 'All Time',
        LeaderboardScope.thisWeek => 'This Week',
        LeaderboardScope.thisMonth => 'This Month',
      };
}

// ---------------------------------------------------------------------------
// LeaderboardEntry
// ---------------------------------------------------------------------------

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.points,
    required this.choresCompleted,
  });

  final int rank;
  final String userId;
  final String displayName;
  final int points;
  final int choresCompleted;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: json['rank'] as int,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      points: json['points'] as int,
      choresCompleted: json['chores_completed'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// LeaderboardResult
// ---------------------------------------------------------------------------

class LeaderboardResult {
  const LeaderboardResult({
    required this.scope,
    this.weekStart,
    this.weekEnd,
    this.monthStart,
    this.monthEnd,
    required this.entries,
    this.requestingUserRank,
  });

  final LeaderboardScope scope;
  final String? weekStart;
  final String? weekEnd;
  final String? monthStart;
  final String? monthEnd;
  final List<LeaderboardEntry> entries;
  final int? requestingUserRank;

  factory LeaderboardResult.fromJson(Map<String, dynamic> json) {
    final scopeStr = json['scope'] as String;
    final scope = switch (scopeStr) {
      'all_time' => LeaderboardScope.allTime,
      'this_week' => LeaderboardScope.thisWeek,
      'this_month' => LeaderboardScope.thisMonth,
      _ => LeaderboardScope.allTime,
    };

    final rawEntries = json['entries'] as List<dynamic>? ?? [];
    final entries = rawEntries
        .cast<Map<String, dynamic>>()
        .map(LeaderboardEntry.fromJson)
        .toList();

    return LeaderboardResult(
      scope: scope,
      weekStart: json['week_start'] as String?,
      weekEnd: json['week_end'] as String?,
      monthStart: json['month_start'] as String?,
      monthEnd: json['month_end'] as String?,
      entries: entries,
      requestingUserRank: json['requesting_user_rank'] as int?,
    );
  }
}
