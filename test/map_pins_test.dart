import 'dart:io';

import 'package:aura_novel/features/projects/models/map_pin_model.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
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
    tempDir = Directory.systemTemp.createTempSync('aura_map_test');
    repo = ProjectRepository(databasePath: p.join(tempDir.path, 'projects.db'));
  });

  tearDown(() async {
    await repo.close();
    tempDir.deleteSync(recursive: true);
  });

  MapPin pin(String id, {String project = 'p', double x = 0.25}) =>
      MapPin(id: id, projectId: project, x: x, y: 0.5, label: 'Pin $id', loreItemId: 'lore');

  test('guarda, lee por proyecto y borra pines', () async {
    await repo.saveMapPin(pin('a'));
    await repo.saveMapPin(pin('b', project: 'otro'));

    final pins = await repo.getMapPins('p');
    expect(pins.single.x, 0.25);
    expect(pins.single.loreItemId, 'lore');

    await repo.deleteMapPin('a');
    expect(await repo.getMapPins('p'), isEmpty);
    expect(await repo.getMapPins('otro'), hasLength(1));
  });

  test('borrar el proyecto borra sus pines', () async {
    await repo.saveProject(ProjectModel(id: 'p', title: 'T', createdAt: DateTime(2026), updatedAt: DateTime(2026)));
    await repo.saveMapPin(pin('a'));

    await repo.deleteProjectCascade('p');

    expect(await repo.getMapPins('p'), isEmpty);
  });

  test('mapPath se guarda con el proyecto y vale vacío por defecto', () async {
    await repo.saveProject(ProjectModel(id: 'p', title: 'T', createdAt: DateTime(2026), updatedAt: DateTime(2026)));
    expect((await repo.getProject('p'))!.mapPath, '');

    final updated = (await repo.getProject('p'))!.copyWith(mapPath: '/x/mapa.png');
    await repo.saveProject(updated);
    expect((await repo.getProject('p'))!.mapPath, '/x/mapa.png');
  });

  test('exportAll e importAll incluyen los pines', () async {
    await repo.saveMapPin(pin('a'));
    final data = await repo.exportAll();
    expect(data['map_pins'], hasLength(1));

    await repo.deleteMapPin('a');
    await repo.importAll(data);
    expect(await repo.getMapPins('p'), hasLength(1));
  });

  test('migra una base v5 sin perder datos y crea mapa y pines', () async {
    await repo.close();
    final path = p.join(tempDir.path, 'old.db');
    final old = await openDatabase(path, version: 5, onCreate: (db, _) async {
      await db.execute("CREATE TABLE projects (id TEXT PRIMARY KEY, title TEXT NOT NULL, synopsis TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL, calendar TEXT NOT NULL DEFAULT '')");
      await db.execute("CREATE TABLE chapters (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, title TEXT NOT NULL, order_index INTEGER NOT NULL DEFAULT 0, summary TEXT NOT NULL DEFAULT '')");
      await db.execute("CREATE TABLE story_nodes (id TEXT PRIMARY KEY, chapter_id TEXT NOT NULL, parent_node_id TEXT, content TEXT NOT NULL DEFAULT '', branch_name TEXT NOT NULL DEFAULT '', timestamp TEXT NOT NULL)");
      await db.execute("CREATE TABLE drafts (chapter_id TEXT PRIMARY KEY, node_id TEXT NOT NULL, content TEXT NOT NULL, updated_at TEXT NOT NULL)");
      await db.execute("CREATE TABLE timeline_events (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, chapter_id TEXT, title TEXT NOT NULL, world_date TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL DEFAULT 0)");
      await db.insert('projects', {'id': 'p', 'title': 'Vieja', 'created_at': '2026-01-01T00:00:00', 'updated_at': '2026-01-01T00:00:00'});
    });
    await old.close();

    final migrated = ProjectRepository(databasePath: path);
    addTearDown(migrated.close);

    expect((await migrated.getAllProjects()).single.mapPath, '');
    await migrated.saveMapPin(pin('a'));
    expect(await migrated.getMapPins('p'), hasLength(1));
  });
}
