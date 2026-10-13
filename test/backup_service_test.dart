import 'dart:convert';
import 'dart:io';

import 'package:aura_novel/features/lore/lore_repository.dart';
import 'package:aura_novel/features/lore/models/character_model.dart';
import 'package:aura_novel/features/projects/backup_service.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/models/story_node_model.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  var counter = 0;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('aura_backup_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  ({ProjectRepository projects, LoreRepository lore, BackupService service}) newApp() {
    final n = counter++;
    final projects = ProjectRepository(databasePath: p.join(tempDir.path, 'projects$n.db'));
    final lore = LoreRepository(databasePath: p.join(tempDir.path, 'lore$n.db'));
    return (projects: projects, lore: lore, service: BackupService(projects: projects, lore: lore));
  }

  Future<void> seed(ProjectRepository projects, LoreRepository lore) async {
    await projects.saveProject(ProjectModel(
      id: 'p1',
      title: 'Ceniza',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    ));
    await projects.saveChapter(const ChapterModel(id: 'c1', projectId: 'p1', title: 'Uno', order: 0, summary: 'resumen'));
    await projects.saveNode(StoryNodeModel(id: 'n1', chapterId: 'c1', content: 'texto', timestamp: DateTime(2026, 1, 3)));
    await lore.saveCharacter(const CharacterModel(id: 'ch1', name: 'Mara', aliases: ['la Cuervo']));
  }

  test('exportar y restaurar en otra instalación devuelve lo mismo', () async {
    final source = newApp();
    await seed(source.projects, source.lore);
    final json = await source.service.buildJson();

    final target = newApp();
    final summary = await target.service.restoreFromJson(json);

    expect(summary.projects, 1);
    expect(summary.chapters, 1);
    expect(summary.characters, 1);
    expect((await target.projects.getProject('p1'))!.title, 'Ceniza');
    expect((await target.projects.getChaptersForProject('p1')).single.summary, 'resumen');
    expect((await target.projects.getNodesForChapter('c1')).single.content, 'texto');
    expect((await target.lore.getAllCharacters()).single.aliases, ['la Cuervo']);

    await source.projects.close();
    await source.lore.close();
    await target.projects.close();
    await target.lore.close();
  });

  test('restaurar sobre datos existentes reemplaza por id y conserva lo demás', () async {
    final app = newApp();
    await seed(app.projects, app.lore);
    final json = await app.service.buildJson();

    await app.projects.saveProject(ProjectModel(
      id: 'p1',
      title: 'Cambiado después',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 2, 1),
    ));
    await app.projects.saveProject(ProjectModel(
      id: 'p2',
      title: 'Nuevo',
      createdAt: DateTime(2026, 2, 1),
      updatedAt: DateTime(2026, 2, 1),
    ));

    await app.service.restoreFromJson(json);

    expect((await app.projects.getProject('p1'))!.title, 'Ceniza');
    expect(await app.projects.getProject('p2'), isNotNull);
    await app.projects.close();
    await app.lore.close();
  });

  test('la copia no incluye la API key ni el endpoint', () async {
    final app = newApp();
    await seed(app.projects, app.lore);
    final json = await app.service.buildJson();

    expect(json.toLowerCase(), isNot(contains('apikey')));
    expect(json.toLowerCase(), isNot(contains('api_key')));
    expect(json.toLowerCase(), isNot(contains('base_url')));
    await app.projects.close();
    await app.lore.close();
  });

  group('archivos inválidos', () {
    late ({ProjectRepository projects, LoreRepository lore, BackupService service}) app;

    setUp(() => app = newApp());
    tearDown(() async {
      await app.projects.close();
      await app.lore.close();
    });

    test('un texto que no es JSON', () {
      expect(app.service.restoreFromJson('hola'), throwsA(isA<BackupFormatException>()));
    });

    test('un JSON de otra cosa', () {
      expect(app.service.restoreFromJson('{"foo": 1}'), throwsA(isA<BackupFormatException>()));
    });

    test('una versión más nueva que la soportada', () {
      final json = jsonEncode({'format': 'aura-novel-backup', 'version': 99});
      expect(app.service.restoreFromJson(json), throwsA(isA<BackupFormatException>()));
    });

    test('una tabla que no es lista no deja nada a medio restaurar', () async {
      final json = jsonEncode({
        'format': 'aura-novel-backup',
        'version': 1,
        'projects': [
          {'id': 'p1', 'title': 'X', 'synopsis': '', 'created_at': '2026-01-01', 'updated_at': '2026-01-01'}
        ],
        'chapters': 'roto',
      });

      await expectLater(app.service.restoreFromJson(json), throwsA(isA<BackupFormatException>()));
      expect(await app.projects.getAllProjects(), isEmpty);
    });
  });
}
