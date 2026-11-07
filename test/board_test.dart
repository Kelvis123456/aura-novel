import 'dart:io';

import 'package:aura_novel/features/projects/board_screen.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ChapterModel ch(String id, int order, {String status = 'borrador', List<String> threads = const []}) =>
    ChapterModel(id: id, projectId: 'p', title: 'Cap $id', order: order, status: status, threads: threads);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('groupByStatus reparte por etapa, respeta el orden y filtra por hilo', () {
    final all = [
      ch('c', 2, status: 'listo', threads: ['faro']),
      ch('a', 0, status: 'idea'),
      ch('b', 1, threads: ['faro', 'herencia']),
      ch('d', 3, threads: ['herencia']),
    ];
    final cols = groupByStatus(all);
    expect(cols['idea']!.map((c) => c.id), ['a']);
    expect(cols['borrador']!.map((c) => c.id), ['b', 'd']);
    expect(cols['listo']!.map((c) => c.id), ['c']);
    expect(cols['revision'], isEmpty);
    expect(groupByStatus(all, thread: 'faro').values.expand((l) => l).map((c) => c.id), unorderedEquals(['b', 'c']));
  });

  test('threadsOf ordena por uso y luego por nombre', () {
    final all = [ch('a', 0, threads: ['b', 'a']), ch('b', 1, threads: ['b']), ch('c', 2, threads: ['c'])];
    expect(threadsOf(all), ['b', 'a', 'c']);
  });

  test('el capítulo guarda estado e hilos, y un estado desconocido vuelve a borrador', () {
    final back = ChapterModel.fromMap(ch('a', 0, status: 'revision', threads: ['x', 'y']).toMap());
    expect(back.status, 'revision');
    expect(back.threads, ['x', 'y']);
    expect(ChapterModel.fromMap({'id': 'a', 'project_id': 'p', 'status': 'raro'}).status, 'borrador');
    expect(ChapterModel.splitThreads(' a | | b '), ['a', 'b']);
  });

  group('con base de datos', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('aura_board'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('updateChapterBoard toca solo estado e hilos', () async {
      final repo = ProjectRepository(databasePath: p.join(dir.path, 'a.db'));
      await repo.saveChapter(const ChapterModel(id: 'c', projectId: 'p', title: 'Título', order: 0, summary: 'Resumen'));
      await repo.updateChapterBoard('c', status: 'listo', threads: ['faro']);
      final saved = (await repo.getChaptersForProject('p')).single;
      expect([saved.title, saved.summary, saved.status], ['Título', 'Resumen', 'listo']);
      expect(saved.threads, ['faro']);
      await repo.close();
    });

    test('migra una base v9 con capítulos sin perderlos', () async {
      final path = p.join(dir.path, 'v9.db');
      final old = await openDatabase(path, version: 9, onCreate: (db, _) async {
        await db.execute("CREATE TABLE projects (id TEXT PRIMARY KEY, title TEXT NOT NULL, synopsis TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL, calendar TEXT NOT NULL DEFAULT '', map_path TEXT NOT NULL DEFAULT '', writing_profile TEXT NOT NULL DEFAULT '')");
        await db.execute("CREATE TABLE chapters (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, title TEXT NOT NULL, order_index INTEGER NOT NULL DEFAULT 0, summary TEXT NOT NULL DEFAULT '')");
        await db.insert('chapters', {'id': 'c', 'project_id': 'p', 'title': 'Viejo', 'order_index': 0, 'summary': 's'});
      });
      await old.close();

      final repo = ProjectRepository(databasePath: path);
      final chapter = (await repo.getChaptersForProject('p')).single;
      expect([chapter.title, chapter.summary, chapter.status], ['Viejo', 's', 'borrador']);
      expect(chapter.threads, isEmpty);
      await repo.close();
    });
  });
}
