import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/accessible_tap.dart';
import '../models/chore_model.dart';
import '../utils/chore_calendar_utils.dart';
import 'chore_card.dart';

const _teal = Color(0xFF0D9488);
const _darkText = Color(0xFF0F2E2C);
const _secondaryText = Color(0xFF7F9794);
const _borderLight = Color(0xFFE6EDEC);

const List<String> _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Monday-first month grid of chores (TASK-117).
///
/// Places each chore on its calendar day via [groupChoresByDay] and opens a
/// read-only day sheet on tap. The widget is purely presentational — it never
/// mutates chores (no complete/dismiss/reassign callbacks are wired).
class ChoreCalendar extends StatefulWidget {
  const ChoreCalendar({super.key, required this.chores});
  final List<ChoreModel> chores;
  @override
  State<ChoreCalendar> createState() => _ChoreCalendarState();
}

class _ChoreCalendarState extends State<ChoreCalendar> {
  late DateTime _focusedMonth; // day forced to 1
  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime(_today.year, _today.month);
  }

  void _shiftMonth(int delta) => setState(() {
    // Day pinned to 1 so month arithmetic can never drift (e.g. Jan 31 + 1 →
    // Mar 3). The day is always 1 in practice, but this makes the invariant
    // explicit and future-proof.
    _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta, 1);
  });

  @override
  Widget build(BuildContext context) {
    // Recomputed on every build (no cached map, no didUpdateWidget): the
    // provider replaces the chore list wholesale, so recomputing is always
    // correct and cannot go stale.
    final byDay = groupChoresByDay(widget.chores);
    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final leadingBlanks = (firstOfMonth.weekday - DateTime.monday) % 7;
    final weeks = ((leadingBlanks + daysInMonth) / 7).ceil();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
        child: Row(children: [
          // Flexible (not a fixed Text + Spacer) so a long month label
          // ellipsizes instead of overflowing the row at large text scales.
          // With a single flexible child the label box absorbs all the free
          // space, so the buttons stay flush right exactly as before.
          Flexible(
            child: Text(
              DateFormat('MMMM yyyy').format(_focusedMonth),
              key: const Key('calendar_month_label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _darkText),
            ),
          ),
          IconButton(key: const Key('calendar_prev_month'), icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shiftMonth(-1)),
          TextButton(
              key: const Key('calendar_today'),
              onPressed: () => setState(() => _focusedMonth = DateTime(_today.year, _today.month)),
              child: const Text('Today')),
          IconButton(key: const Key('calendar_next_month'), icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shiftMonth(1)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          // Each label gets exactly 1/7 of the width; scale it down rather
          // than let it overflow at large text scales.
          for (final l in _weekdayLabels)
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(l, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _secondaryText)),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(children: [
            for (var week = 0; week < weeks; week++)
              Expanded(child: Row(children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _dayCell(week, col, leadingBlanks, daysInMonth, byDay)),
              ])),
          ]),
        ),
      ),
    ]);
  }

  Widget _dayCell(int week, int col, int leadingBlanks, int daysInMonth, Map<DateTime, List<ChoreModel>> byDay) {
    final dayNum = week * 7 + col - leadingBlanks + 1;
    if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();
    final day = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
    final chores = byDay[day] ?? const <ChoreModel>[];
    final isToday = DateUtils.isSameDay(day, _today);
    final countLabel = chores.isEmpty
        ? 'no chores'
        : '${chores.length} chore${chores.length == 1 ? '' : 's'}';
    return AccessibleTap(
      key: Key('calendar_day_${day.year}_${day.month}_${day.day}'),
      onTap: () => _showDaySheet(day, chores),
      // The grid is otherwise opaque to screen readers (a bare number);
      // announce the full date (including the year — otherwise Dec 2025 and
      // Dec 2026 cells are indistinguishable) plus how many chores land on it.
      label: '${DateFormat('EEEE, d MMMM yyyy').format(day)}, '
          '$countLabel${isToday ? ', today' : ''}',
      borderRadius: BorderRadius.circular(10),
      // The cell content is wrapped in a scale-down FittedBox: the grid hands
      // each week a share of whatever height is left, and on a landscape phone
      // that is far shorter than the number circle + marker row, so a
      // fixed-size Column would overflow. Scaling keeps every cell legible and
      // makes grid overflow impossible at any cell size (ported from the
      // portrait/large-text review).
      child: ExcludeSemantics(
        // The label above fully describes the cell; the bare day number and
        // the status dots are decorative and must not be announced twice.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? _teal : Colors.transparent, border: isToday ? null : Border.all(color: _borderLight)),
              child: FittedBox(fit: BoxFit.scaleDown, child: Padding(
                padding: const EdgeInsets.all(3),
                child: Text('${day.day}', style: TextStyle(fontSize: 13, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500, color: isToday ? Colors.white : _darkText)),
              )),
            ),
            const SizedBox(height: 4),
            SizedBox(height: 8, child: chores.isEmpty ? null : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < chores.length && i < 3; i++)
                Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(shape: BoxShape.circle, color: chores[i].statusColor)),
              // The overflow count shares an 8px-tall band with the dots; scale
              // it down so large text scales cannot clip it.
              if (chores.length > 3)
                FittedBox(fit: BoxFit.scaleDown, child: Text('+${chores.length - 3}', style: const TextStyle(fontSize: 8, color: _secondaryText))),
            ])),
          ]),
        ),
      ),
    );
  }

  void _showDaySheet(DateTime day, List<ChoreModel> chores) {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.5, minChildSize: 0.2, maxChildSize: 0.85,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.paddingOf(context).bottom),
          children: [
            Text(DateFormat('EEEE, d MMMM').format(day), key: const Key('calendar_day_sheet_title'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _darkText)),
            const SizedBox(height: 4),
            Text(chores.isEmpty ? 'Nothing done or due on this day.' : '${chores.length} chore${chores.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 14, color: _secondaryText)),
            const SizedBox(height: 12),
            if (chores.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Icon(
                    Icons.event_busy_rounded,
                    size: 48,
                    color: _secondaryText,
                  ),
                ),
              )
            else
              ...chores.map((c) => ChoreCard(chore: c)), // read-only: no mutation callbacks
          ],
        ),
      ),
    );
  }
}
