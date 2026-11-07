/// Daily word counts and the streak built from them. Days are local `yyyy-mm-dd` keys.
class WritingStats {
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Consecutive days with writing, ending today. A day without writing yet does not break a
  /// streak until it is over: if today is empty the count runs back from yesterday.
  static int streak(Map<String, int> wordsByDay, DateTime today) {
    var day = DateTime(today.year, today.month, today.day);
    if ((wordsByDay[dayKey(day)] ?? 0) <= 0) day = day.subtract(const Duration(days: 1));
    var count = 0;
    // DST-safe: step by calendar day, not by 24 hours.
    while ((wordsByDay[dayKey(day)] ?? 0) > 0) {
      count++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }
}
