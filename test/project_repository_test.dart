import 'dart:io';

import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('aura_repo_test');
    dbPath = p.join(tempDir.path, 'projects.db');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('migra una base v1 sin perder datos y añade summary', () async {
    final v1 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE projects (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
              "synopsis TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)");
          await db.execute('CREATE TABLE chapters (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, '
              'title TEXT NOT NULL, order_index INTEGER NOT NULL DEFAULT 0)');
          await db.execute('CREATE TABLE story_nodes (id TEXT PRIMARY KEY, chapter_id TEXT NOT NULL, '
              "parent_node_id TEXT, content TEXT NOT NULL DEFAULT '', branch_name TEXT NOT NULL DEFAULT '', "
              'timestamp TEXT NOT NULL)');
          await db.insert('chapters', {'id': 'c1', 'project_id': 'p1', 'title': 'Viejo', 'order_index': 0});
        },
      ),
    );
    await v1.close();

    final repo = ProjectRepository(databasePath: dbPath);
    final chapters = await repo.getChaptersForProject('p1');

    expect(chapters.single.title, 'Viejo');
    expect(chapters.single.summary, '');
    await repo.close();
  });

  test('guarda y lee el resumen de un capítulo', () async {
    final repo = ProjectRepository(databasePath: dbPath);
    await repo.saveChapter(const ChapterModel(id: 'c1', projectId: 'p1', title: 'Uno', order: 0));

    await repo.updateChapterSummary('c1', 'Mara llega a la torre.');

    expect((await repo.getChaptersForProject('p1')).single.summary, 'Mara llega a la torre.');
    await repo.close();
  });
}
