import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../router/app_router.dart';
import '../../../shared/widgets/error_widget.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../household/providers/household_provider.dart';
import '../models/leaderboard_model.dart';
import '../providers/leaderboard_provider.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _teal = Color(0xFF0D9488);
const _darkText = Color(0xFF0F2E2C);
const _secondaryText = Color(0xFF7F9794);
const _mutedText = Color(0xFF9FB6B3);
const _borderLight = Color(0xFFE6EDEC);

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
// Helpers
// ---------------------------------------------------------------------------

String _fmtShort(String iso) => DateFormat('MMM d').format(DateTime.parse(iso));

String _rangeLabel(LeaderboardScope scope, LeaderboardResult? result) {
  if (result == null) return '';
  switch (scope) {
    case LeaderboardScope.thisWeek:
      if (result.weekStart != null && result.weekEnd != null) {
        return '${_fmtShort(result.weekStart!)} – ${_fmtShort(result.weekEnd!)}';
      }
      return 'This Week';
    case LeaderboardScope.thisMonth:
      if (result.monthStart != null) {
        return DateFormat('MMMM yyyy').format(DateTime.parse(result.monthStart!));
      }
      return 'This Month';
    case LeaderboardScope.allTime:
      return 'All Time';
  }
}

String _computeStanding(LeaderboardResult result, String? currentUserId) {
  final entries = result.entries;
  if (entries.isEmpty) return 'Complete a chore to climb the ranks';
  final myEntry = entries.where((e) => e.userId == currentUserId).firstOrNull;
  if (myEntry == null) return 'Complete a chore to climb the ranks';
  if (entries.length == 1) return 'Your household, your rules 🏠';
  if (myEntry.rank == 1) return "You're in the lead 👑 keep it up!";
  final leader = entries.first;
  return "You're #${myEntry.rank} — ${leader.points - myEntry.points} pts behind ${leader.displayName}";
}

// ---------------------------------------------------------------------------
// LeaderboardScreen
// ---------------------------------------------------------------------------

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key, required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(leaderboardScopeNotifierProvider);
    final leaderboardAsync = ref.watch(leaderboardProvider(householdId));
    final currentUserId = ref.watch(currentUserIdProvider);
    final bool isAdmin = ref
            .watch(householdsNotifierProvider)
            .valueOrNull
            ?.where((h) => h.id == householdId)
            .firstOrNull
            ?.isAdmin ??
        false;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/households');
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LeaderboardHeader(
                leaderboardAsync: leaderboardAsync,
                currentUserId: currentUserId,
                isAdmin: isAdmin,
                householdId: householdId,
              ),
              _PeriodPicker(
                scope: scope,
                onScopeChanged: (s) =>
                    ref.read(leaderboardScopeNotifierProvider.notifier).setScope(s),
              ),
              _RangeLabel(scope: scope, leaderboardAsync: leaderboardAsync),
              Expanded(
                child: RefreshIndicator(
                  color: _teal,
                  onRefresh: () async =>
                      ref.invalidate(leaderboardProvider(householdId)),
                  child: leaderboardAsync.when(
                    loading: () => const LoadingWidget(
                      key: Key('loading_widget'),
                      message: 'Loading leaderboard…',
                    ),
                    error: (error, _) => AppErrorWidget(
                      key: const Key('error_widget'),
                      message: error.toString(),
                      onRetry: () =>
                          ref.invalidate(leaderboardProvider(householdId)),
                    ),
                    data: (result) => _LeaderboardBody(
                      result: result,
                      currentUserId: currentUserId,
                      householdId: householdId,
                      isAdmin: isAdmin,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _LeaderboardBottomNav(
          householdId: householdId,
          currentIndex: 2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _LeaderboardHeader extends StatelessWidget {
  const _LeaderboardHeader({
    required this.leaderboardAsync,
    required this.currentUserId,
    required this.isAdmin,
    required this.householdId,
  });

  final AsyncValue<LeaderboardResult> leaderboardAsync;
  final String? currentUserId;
  final bool isAdmin;
  final String householdId;

  @override
  Widget build(BuildContext context) {
    final standing = leaderboardAsync.whenOrNull(
          data: (result) => _computeStanding(result, currentUserId),
        ) ??
        'Loading…';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Leaderboard',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: _darkText,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  standing,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _secondaryText,
                  ),
                ),
              ],
            ),
          ),
          if (isAdmin)
            GestureDetector(
              onTap: () => context.pushNamed(
                AppRoutes.householdManage,
                pathParameters: {'householdId': householdId},
              ),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _borderLight),
                  color: Colors.white,
                ),
                child:
                    const Icon(Icons.group_rounded, size: 20, color: _darkText),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period picker (pill segmented control)
// ---------------------------------------------------------------------------

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.scope, required this.onScopeChanged});

  final LeaderboardScope scope;
  final void Function(LeaderboardScope) onScopeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _PeriodButton(
            label: 'This Week',
            isActive: scope == LeaderboardScope.thisWeek,
            onTap: () => onScopeChanged(LeaderboardScope.thisWeek),
          ),
          _PeriodButton(
            label: 'This Month',
            isActive: scope == LeaderboardScope.thisMonth,
            onTap: () => onScopeChanged(LeaderboardScope.thisMonth),
          ),
          _PeriodButton(
            label: 'All Time',
            isActive: scope == LeaderboardScope.allTime,
            onTap: () => onScopeChanged(LeaderboardScope.allTime),
          ),
        ],
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isActive
                ? [
                    const BoxShadow(
                      color: Color(0x40133E3A),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isActive ? _teal : _secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Range label
// ---------------------------------------------------------------------------

class _RangeLabel extends StatelessWidget {
  const _RangeLabel({required this.scope, required this.leaderboardAsync});

  final LeaderboardScope scope;
  final AsyncValue<LeaderboardResult> leaderboardAsync;

  @override
  Widget build(BuildContext context) {
    final label = leaderboardAsync.whenOrNull(
      data: (result) => _rangeLabel(scope, result),
    );

    if (label == null || label.isEmpty) {
      return const SizedBox(height: 12);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: _mutedText,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body (ListView wrapping podium + invite + rest)
// ---------------------------------------------------------------------------

class _LeaderboardBody extends StatelessWidget {
  const _LeaderboardBody({
    required this.result,
    required this.currentUserId,
    required this.householdId,
    required this.isAdmin,
  });

  final LeaderboardResult result;
  final String? currentUserId;
  final String householdId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final entries = result.entries;
    final showInvite = entries.length < 3;

    return ListView(
      key: const Key('leaderboard_list'),
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 110),
      children: [
        _Podium(entries: entries, currentUserId: currentUserId),
        if (showInvite)
          _InviteNudge(
            entryCount: entries.length,
            householdId: householdId,
            isAdmin: isAdmin,
          ),
        if (entries.length > 3)
          _RestList(entries: entries, currentUserId: currentUserId),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Podium
// ---------------------------------------------------------------------------

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, required this.currentUserId});

  final List<LeaderboardEntry> entries;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final p1 = entries.isNotEmpty ? entries[0] : null;
    final p2 = entries.length >= 2 ? entries[1] : null;
    final p3 = entries.length >= 3 ? entries[2] : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 34, 4, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd
          p2 != null
              ? _PodiumSlot(
                  entry: p2,
                  rank: 2,
                  avatarSize: 56,
                  avatarFontSize: 19,
                  borderColor: const Color(0xFFCBD5E1),
                  pedestalHeight: 74,
                  pedestalGradient: const [
                    Color(0xFFEEF4F3),
                    Color(0xFFE3EDEB)
                  ],
                  pedestalNumColor: const Color(0xFF9AA8A6),
                  pedestalNumSize: 26,
                  nameFontSize: 13,
                  pointsFontSize: 13,
                  pointsFontWeight: FontWeight.w700,
                  currentUserId: currentUserId,
                )
              : const SizedBox(width: 106),

          const SizedBox(width: 8),

          // 1st
          p1 != null
              ? _PodiumSlotFirst(
                  entry: p1,
                  currentUserId: currentUserId,
                )
              : const SizedBox(width: 106),

          const SizedBox(width: 8),

          // 3rd
          p3 != null
              ? _PodiumSlot(
                  entry: p3,
                  rank: 3,
                  avatarSize: 56,
                  avatarFontSize: 19,
                  borderColor: const Color(0xFFE0B48C),
                  pedestalHeight: 58,
                  pedestalGradient: const [
                    Color(0xFFF5ECE4),
                    Color(0xFFEADDD0)
                  ],
                  pedestalNumColor: const Color(0xFFB78A63),
                  pedestalNumSize: 24,
                  nameFontSize: 13,
                  pointsFontSize: 13,
                  pointsFontWeight: FontWeight.w700,
                  currentUserId: currentUserId,
                )
              : const SizedBox(width: 106),
        ],
      ),
    );
  }
}

class _PodiumSlotFirst extends StatelessWidget {
  const _PodiumSlotFirst({required this.entry, required this.currentUserId});

  final LeaderboardEntry entry;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final isYou = entry.userId == currentUserId;

    return SizedBox(
      width: 106,
      child: Column(
        children: [
          // Crown
          const Icon(
            Icons.workspace_premium_rounded,
            size: 30,
            color: Color(0xFFFBBF24),
          ),
          const SizedBox(height: 3),

          // Avatar with star + YOU pill
          Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // Avatar
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: _avatarColor(entry.displayName),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFFFBBF24), width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xCCFBBF24),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        entry.displayName.isNotEmpty
                            ? entry.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  // Twinkle star
                  const Positioned(
                    top: -4,
                    right: -6,
                    child: Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Color(0xFFFBBF24),
                    ),
                  ),
                ],
              ),
              if (isYou) ...[
                const SizedBox(height: 4),
                _YouPill(),
              ],
            ],
          ),

          const SizedBox(height: 9),

          // Name
          SizedBox(
            width: 104,
            child: Text(
              entry.displayName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _darkText,
              ),
            ),
          ),

          const SizedBox(height: 2),

          // Points
          Text(
            '${entry.points} pts',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _teal,
            ),
          ),

          const SizedBox(height: 9),

          // Pedestal
          Container(
            width: double.infinity,
            height: 100,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFEF3C7), Color(0xFFFDE9A8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 11),
                child: Text(
                  '1',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD99A16),
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

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({
    required this.entry,
    required this.rank,
    required this.avatarSize,
    required this.avatarFontSize,
    required this.borderColor,
    required this.pedestalHeight,
    required this.pedestalGradient,
    required this.pedestalNumColor,
    required this.pedestalNumSize,
    required this.nameFontSize,
    required this.pointsFontSize,
    required this.pointsFontWeight,
    required this.currentUserId,
  });

  final LeaderboardEntry entry;
  final int rank;
  final double avatarSize;
  final double avatarFontSize;
  final Color borderColor;
  final double pedestalHeight;
  final List<Color> pedestalGradient;
  final Color pedestalNumColor;
  final double pedestalNumSize;
  final double nameFontSize;
  final double pointsFontSize;
  final FontWeight pointsFontWeight;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final isYou = entry.userId == currentUserId;

    return SizedBox(
      width: 106,
      child: Column(
        children: [
          // Avatar + YOU pill
          Column(
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: _avatarColor(entry.displayName),
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Center(
                  child: Text(
                    entry.displayName.isNotEmpty
                        ? entry.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: avatarFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (isYou) ...[
                const SizedBox(height: 4),
                _YouPill(),
              ],
            ],
          ),

          const SizedBox(height: 9),

          // Name
          SizedBox(
            width: 96,
            child: Text(
              entry.displayName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: nameFontSize,
                fontWeight: FontWeight.w700,
                color: _darkText,
              ),
            ),
          ),

          const SizedBox(height: 2),

          // Points
          Text(
            '${entry.points} pts',
            style: TextStyle(
              fontSize: pointsFontSize,
              fontWeight: pointsFontWeight,
              color: _teal,
            ),
          ),

          const SizedBox(height: 9),

          // Pedestal
          Container(
            width: double.infinity,
            height: pedestalHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: pedestalGradient,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: pedestalNumSize,
                    fontWeight: FontWeight.w800,
                    color: pedestalNumColor,
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
// YOU pill
// ---------------------------------------------------------------------------

class _YouPill extends StatelessWidget {
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
// Invite nudge
// ---------------------------------------------------------------------------

class _InviteNudge extends StatelessWidget {
  const _InviteNudge({
    required this.entryCount,
    required this.householdId,
    required this.isAdmin,
  });

  final int entryCount;
  final String householdId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final title = entryCount == 1
        ? "It's just you so far"
        : 'Add one more to fill the podium';

    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4FBF9),
        border: Border.all(color: const Color(0xFFB9DDD6), width: 1.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFD8F0EC),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.group_add_rounded, color: _teal, size: 24),
          ),
          const SizedBox(height: 11),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _darkText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chores are more fun with a little friendly competition.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: _secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: isAdmin
                ? () => context.pushNamed(
                      AppRoutes.householdManage,
                      pathParameters: {'householdId': householdId},
                    )
                : null,
            style: TextButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              shape: const StadiumBorder(),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16),
                SizedBox(width: 4),
                Text(
                  'Invite housemates',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rest list (rank 4+)
// ---------------------------------------------------------------------------

class _RestList extends StatelessWidget {
  const _RestList({required this.entries, required this.currentUserId});

  final List<LeaderboardEntry> entries;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final rest = entries.skip(3).toList();
    if (rest.isEmpty) return const SizedBox.shrink();

    return Column(
      children: rest.map((e) {
        final isYou = e.userId == currentUserId;
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding:
              const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: isYou ? const Color(0xFFEAFAF7) : Colors.white,
            border: Border.all(
              color: isYou
                  ? const Color(0xFFBCE7DF)
                  : const Color(0xFFEBF1F0),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${e.rank}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isYou ? _teal : _mutedText,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              _Avatar(name: e.displayName, size: 40, fontSize: 15),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _darkText,
                            ),
                          ),
                        ),
                        if (isYou) ...[
                          const SizedBox(width: 7),
                          _YouPill(),
                        ],
                      ],
                    ),
                    Text(
                      '${e.choresCompleted} chores completed',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF8AA19E),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${e.points} pts',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _teal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    this.size = 40,
    this.fontSize = 15,
  });

  final String name;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _avatarColor(name),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation bar
// ---------------------------------------------------------------------------

class _LeaderboardBottomNav extends StatelessWidget {
  const _LeaderboardBottomNav({
    required this.householdId,
    required this.currentIndex,
  });

  final String householdId;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      key: const Key('bottom_nav_bar'),
      currentIndex: currentIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            context.goNamed(
              AppRoutes.choreList,
              pathParameters: {'householdId': householdId},
            );
          case 1:
            context.goNamed(
              AppRoutes.myChores,
              pathParameters: {'householdId': householdId},
            );
          case 2:
            break; // Already on leaderboard.
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.checklist_rounded),
          label: 'All Chores',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_rounded),
          label: 'My Chores',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.leaderboard_rounded),
          label: 'Leaderboard',
        ),
      ],
    );
  }
}
