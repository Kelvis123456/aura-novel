import 'dart:io';

import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/models/timeline_event_model.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late ProjectRepository repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('aura_timeline_test');
    repo = ProjectRepository(databasePath: p.join(tempDir.path, 'projects.db'));
  });

  tearDown(() async {
    await repo.close();
    tempDir.deleteSync(recursive: true);
  });

  TimelineEvent event(String id, {String project = 'p', String? chapter, int position = 0}) =>
      TimelineEvent(id: id, projectId: project, chapterId: chapter, title: 'Evento $id', worldDate: 'Año 1', position: position);

  test('guarda, ordena por posición y filtra por proyecto', () async {
    await repo.saveTimelineEvent(event('b', position: 1));
    await repo.saveTimelineEvent(event('a', position: 0));
    await repo.saveTimelineEvent(event('x', project: 'otro'));

    final events = await repo.getTimelineEvents('p');

    expect(events.map((e) => e.id), ['a', 'b']);
    expect(events.first.worldDate, 'Año 1');
  });

  test('reorderTimeline reescribe las posiciones', () async {
    await repo.saveTimelineEvent(event('a', position: 0));
    await repo.saveTimelineEvent(event('b', position: 1));

    await repo.reorderTimeline(['b', 'a']);

    expect((await repo.getTimelineEvents('p')).map((e) => e.id), ['b', 'a']);
  });

  test('borrar un capítulo desenlaza sus eventos en vez de borrarlos', () async {
    await repo.saveChapter(const ChapterModel(id: 'c', projectId: 'p', title: 'Uno', order: 0));
    await repo.saveTimelineEvent(event('a', chapter: 'c'));

    await repo.deleteChapterCascade('c');

    final events = await repo.getTimelineEvents('p');
    expect(events.single.chapterId, isNull);
  });

  test('borrar el proyecto borra sus eventos', () async {
    await repo.saveProject(ProjectModel(id: 'p', title: 'T', createdAt: DateTime(2026), updatedAt: DateTime(2026)));
    await repo.saveTimelineEvent(event('a'));
    await repo.saveTimelineEvent(event('x', project: 'otro'));

    await repo.deleteProjectCascade('p');

    expect(await repo.getTimelineEvents('p'), isEmpty);
    expect(await repo.getTimelineEvents('otro'), hasLength(1));
  });

  test('exportAll e importAll incluyen los eventos', () async {
    await repo.saveTimelineEvent(event('a'));
    final data = await repo.exportAll();
    expect(data['timeline_events'], hasLength(1));

    await repo.deleteTimelineEvent('a');
    await repo.importAll(data);

    expect(await repo.getTimelineEvents('p'), hasLength(1));
  });

  test('migra una base v3 sin perder datos y crea la tabla', () async {
    await repo.close();
    final path = p.join(tempDir.path, 'old.db');
    final old = await openDatabase(path, version: 3, onCreate: (db, _) async {
      await db.execute('CREATE TABLE projects (id TEXT PRIMARY KEY, title TEXT NOT NULL, synopsis TEXT NOT NULL DEFAULT \'\', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE chapters (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, title TEXT NOT NULL, order_index INTEGER NOT NULL DEFAULT 0, summary TEXT NOT NULL DEFAULT \'\')');
      await db.execute('CREATE TABLE story_nodes (id TEXT PRIMARY KEY, chapter_id TEXT NOT NULL, parent_node_id TEXT, content TEXT NOT NULL DEFAULT \'\', branch_name TEXT NOT NULL DEFAULT \'\', timestamp TEXT NOT NULL)');
      await db.execute('CREATE TABLE drafts (chapter_id TEXT PRIMARY KEY, node_id TEXT NOT NULL, content TEXT NOT NULL, updated_at TEXT NOT NULL)');
      await db.insert('projects', {'id': 'p', 'title': 'Vieja', 'created_at': '2026-01-01T00:00:00', 'updated_at': '2026-01-01T00:00:00'});
    });
    await old.close();

    final migrated = ProjectRepository(databasePath: path);
    addTearDown(migrated.close);

    expect((await migrated.getAllProjects()).single.title, 'Vieja');
    await migrated.saveTimelineEvent(event('a'));
    expect(await migrated.getTimelineEvents('p'), hasLength(1));
  });
}
