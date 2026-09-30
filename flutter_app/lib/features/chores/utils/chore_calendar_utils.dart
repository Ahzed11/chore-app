import '../models/chore_model.dart';

/// The calendar day a chore appears under (combined semantics — agreed 2026-09-30):
/// - complete / dismissed → the LOCAL date it was completed/dismissed;
/// - pending / overdue    → its due date;
/// - cancelled            → null (never shown on the calendar).
///
/// `completedAt` arrives from the server as a UTC ISO-8601 timestamp, so
/// `.toLocal()` is REQUIRED before extracting year/month/day — otherwise a
/// chore finished near midnight lands on the wrong calendar day.
DateTime? calendarDateFor(ChoreModel chore) {
  switch (chore.status) {
    case 'cancelled':
      return null;
    case 'complete':
    case 'dismissed':
      final at = chore.completedAt;
      if (at == null) return null; // no completion time → cannot place on a day
      final local = at.toLocal();
      return DateTime(local.year, local.month, local.day);
    case 'pending':
    case 'overdue':
      final d = chore.dueDate;
      return DateTime(d.year, d.month, d.day);
    default:
      // Unknown/future status — fail closed (drop from the calendar) rather
      // than silently placing it on its due date, mirroring ChoreModel's
      // explicit statusColor split.
      return null;
  }
}

/// Groups chores by their calendar day (date-only, LOCAL keys). Cancelled
/// chores and chores without a placeable date are dropped.
Map<DateTime, List<ChoreModel>> groupChoresByDay(List<ChoreModel> chores) {
  final grouped = <DateTime, List<ChoreModel>>{};
  for (final chore in chores) {
    final day = calendarDateFor(chore);
    if (day == null) continue;
    grouped.putIfAbsent(day, () => <ChoreModel>[]).add(chore);
  }
  return grouped;
}
