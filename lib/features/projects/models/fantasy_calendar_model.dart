import 'dart:convert';

class CalendarMonth {
  final String name;
  final int days;

  const CalendarMonth({required this.name, required this.days});

  Map<String, dynamic> toJson() => {'name': name, 'days': days};

  factory CalendarMonth.fromJson(Map<String, dynamic> json) =>
      CalendarMonth(name: json['name'] as String, days: json['days'] as int);
}

/// A made-up calendar: an era label and an ordered list of months. It only
/// formats dates for the timeline; it doesn't do date arithmetic.
class FantasyCalendar {
  final String eraName;
  final List<CalendarMonth> months;

  const FantasyCalendar({this.eraName = 'Año', required this.months});

  /// "12 de Brumario, Año 312". Throws [RangeError] for a month or day the
  /// calendar doesn't have, so a bad date is never written silently.
  String format({required int year, required int monthIndex, required int day}) {
    final month = months[monthIndex];
    if (day < 1 || day > month.days) {
      throw RangeError.range(day, 1, month.days, 'day', '${month.name} has ${month.days} days');
    }
    return '$day de ${month.name}, $eraName $year';
  }

  String toJsonString() => jsonEncode({
        'eraName': eraName,
        'months': months.map((m) => m.toJson()).toList(),
      });

  /// Returns null for empty or unreadable input: a corrupt calendar must not
  /// stop the project from opening.
  static FantasyCalendar? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final months = (map['months'] as List<dynamic>)
          .map((m) => CalendarMonth.fromJson(m as Map<String, dynamic>))
          .where((m) => m.days > 0 && m.name.trim().isNotEmpty)
          .toList();
      if (months.isEmpty) return null;
      return FantasyCalendar(eraName: map['eraName'] as String? ?? 'Año', months: months);
    } on Object {
      return null;
    }
  }
}
