import 'dart:io';

import 'package:aura_novel/features/lore/lore_repository.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:aura_novel/features/projects/sample_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('el proyecto de ejemplo trae capítulo con texto, personajes enlazados y un lugar', () async {
    final dir = Directory.systemTemp.createTempSync('aura_sample');
    final projects = ProjectRepository(databasePath: p.join(dir.path, 'projects.db'));
    final lore = LoreRepository(databasePath: p.join(dir.path, 'lore.db'));

    final project = await SampleProject.create(projects, lore);

    final chapters = await projects.getChaptersForProject(project.id);
    expect(chapters, hasLength(1));
    expect((await projects.getLatestNodeForChapter(chapters.single.id))!.content, SampleProject.chapterText);

    final cast = (await lore.getAllCharacters()).where((c) => c.projectId == project.id).toList();
    expect(cast, hasLength(2));
    final ids = cast.map((c) => c.id).toSet();
    for (final c in cast) {
      expect(c.relationships.single.characterId, isIn(ids.difference({c.id})));
    }
    expect((await lore.getAllLoreItems()).where((l) => l.projectId == project.id), hasLength(1));

    // Deleting it leaves nothing behind (uses the same path as the project list).
    await projects.deleteProjectCascade(project.id);
    await lore.deleteForProject(project.id);
    expect(await projects.getAllProjects(), isEmpty);
    expect(await lore.getAllCharacters(), isEmpty);

    await projects.close();
    await lore.close();
    dir.deleteSync(recursive: true);
  });
}
