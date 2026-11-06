import 'dart:io';

import 'package:aura_novel/features/projects/models/fantasy_calendar_model.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/project_controller.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const calendar = FantasyCalendar(
    eraName: 'Era del Sol',
    months: [CalendarMonth(name: 'Brumario', days: 30), CalendarMonth(name: 'Ventoso', days: 12)],
  );

  group('FantasyCalendar', () {
    test('formatea la fecha con mes y era', () {
      expect(calendar.format(year: 312, monthIndex: 0, day: 12), '12 de Brumario, Era del Sol 312');
    });

    test('rechaza días fuera del mes', () {
      expect(() => calendar.format(year: 1, monthIndex: 1, day: 13), throwsRangeError);
      expect(() => calendar.format(year: 1, monthIndex: 0, day: 0), throwsRangeError);
    });

    test('ida y vuelta por JSON', () {
      final back = FantasyCalendar.fromJsonString(calendar.toJsonString())!;
      expect(back.eraName, 'Era del Sol');
      expect(back.months.map((m) => m.days), [30, 12]);
    });

    test('JSON vacío, roto o sin meses válidos da null y no lanza', () {
      expect(FantasyCalendar.fromJsonString(''), isNull);
      expect(FantasyCalendar.fromJsonString(null), isNull);
      expect(FantasyCalendar.fromJsonString('{no es json'), isNull);
      expect(FantasyCalendar.fromJsonString('{"months": [{"name": "X", "days": 0}]}'), isNull);
      expect(FantasyCalendar.fromJsonString('{"months": 3}'), isNull);
    });
  });

  group('persistencia', () {
    late Directory tempDir;
    late ProjectRepository repo;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('aura_calendar_test');
      repo = ProjectRepository(databasePath: p.join(tempDir.path, 'projects.db'));
    });

    tearDown(() async {
      await repo.close();
      tempDir.deleteSync(recursive: true);
    });

    test('el calendario sobrevive guardar y leer el proyecto', () async {
      await repo.saveProject(ProjectModel(id: 'p', title: 'T', createdAt: DateTime(2026), updatedAt: DateTime(2026), calendar: calendar));
      final loaded = (await repo.getProject('p'))!;
      expect(loaded.calendar!.months.first.name, 'Brumario');
    });

    test('renombrar con una copia vieja del proyecto no borra el calendario', () async {
      final stale = ProjectModel(id: 'p', title: 'T', createdAt: DateTime(2026), updatedAt: DateTime(2026));
      await repo.saveProject(stale.copyWith(calendar: calendar));

      await ProjectController(repository: repo).renameProject(stale, title: 'Nuevo', synopsis: '');

      final loaded = (await repo.getProject('p'))!;
      expect(loaded.title, 'Nuevo');
      expect(loaded.calendar, isNotNull);
    });
  });
}
