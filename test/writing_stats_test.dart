import 'dart:io';

import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:aura_novel/features/projects/writing_stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final today = DateTime(2026, 11, 8);
  String d(int back) => WritingStats.dayKey(DateTime(2026, 11, 8 - back));

  test('racha cuenta días seguidos hasta hoy', () {
    expect(WritingStats.streak({d(0): 10, d(1): 5, d(2): 1}, today), 3);
  });

  test('hoy vacío no rompe la racha de ayer', () {
    expect(WritingStats.streak({d(1): 100, d(2): 50}, today), 2);
  });

  test('un día sin escribir la corta', () {
    expect(WritingStats.streak({d(0): 10, d(2): 5}, today), 1);
    expect(WritingStats.streak({d(2): 5}, today), 0);
    expect(WritingStats.streak({}, today), 0);
  });

  test('cruza el cambio de mes y de año', () {
    final jan = DateTime(2027, 1, 1);
    expect(WritingStats.streak({'2027-01-01': 1, '2026-12-31': 1, '2026-12-30': 1}, jan), 3);
  });

  test('el repositorio suma por día, ignora negativos y guarda la meta', () async {
    final dir = Directory.systemTemp.createTempSync('aura_stats');
    final repo = ProjectRepository(databasePath: p.join(dir.path, 'projects.db'));
    await repo.addWords('2026-11-08', 120);
    await repo.addWords('2026-11-08', 30);
    await repo.addWords('2026-11-08', -5);
    await repo.addWords('2026-11-07', 10);
    expect(await repo.getWritingLog(), {'2026-11-08': 150, '2026-11-07': 10});
    expect(await repo.getDailyGoal(), 0);
    await repo.setDailyGoal(500);
    expect(await repo.getDailyGoal(), 500);
    await repo.close();
    dir.deleteSync(recursive: true);
  });
}
