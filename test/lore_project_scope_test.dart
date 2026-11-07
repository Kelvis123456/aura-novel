import 'dart:io';

import 'package:aura_novel/features/lore/context_builder_service.dart';
import 'package:aura_novel/features/lore/lore_repository.dart';
import 'package:aura_novel/features/lore/models/character_model.dart';
import 'package:aura_novel/features/lore/models/lore_item_model.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/wiki_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const shared = CharacterModel(id: 's', name: 'Aldric');
  const inA = CharacterModel(id: 'a', name: 'Brenna', projectId: 'A');
  const inB = CharacterModel(id: 'b', name: 'Cormac', projectId: 'B');

  test('appliesTo: compartido en todos, propio solo en su proyecto', () {
    expect(shared.appliesTo('A'), isTrue);
    expect(shared.appliesTo(null), isTrue);
    expect(inA.appliesTo('A'), isTrue);
    expect(inA.appliesTo('B'), isFalse);
    expect(inA.appliesTo(null), isFalse);
  });

  group('con base de datos', () {
    late Directory tempDir;
    late LoreRepository repo;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('aura_scope_test');
      repo = LoreRepository(databasePath: p.join(tempDir.path, 'lore.db'));
    });

    tearDown(() async {
      await repo.close();
      tempDir.deleteSync(recursive: true);
    });

    test('el contexto de la IA solo trae fichas del proyecto y las compartidas', () async {
      for (final c in [shared, inA, inB]) {
        await repo.saveCharacter(c);
      }
      final builder = ContextBuilderService(repository: repo);
      const text = 'Aldric, Brenna y Cormac llegaron.';

      final forA = (await builder.buildContextMessage(text, projectId: 'A'))!.content;
      expect(forA, allOf(contains('Aldric'), contains('Brenna'), isNot(contains('Cormac'))));

      final scratch = (await builder.buildContextMessage(text))!.content;
      expect(scratch, allOf(contains('Aldric'), isNot(contains('Brenna')), isNot(contains('Cormac'))));
    });

    test('deleteForProject borra las fichas del proyecto y deja las de otros y las compartidas', () async {
      for (final c in [shared, inA, inB]) {
        await repo.saveCharacter(c);
      }
      await repo.saveLoreItem(const LoreItemModel(id: 'la', name: 'Torre A', category: LoreCategory.location, projectId: 'A'));
      await repo.saveLoreItem(const LoreItemModel(id: 'lb', name: 'Torre B', category: LoreCategory.location, projectId: 'B'));

      await repo.deleteForProject('A');

      expect((await repo.getAllCharacters()).map((c) => c.id), unorderedEquals(['s', 'b']));
      expect((await repo.getAllLoreItems()).map((l) => l.id), ['lb']);
    });

    test('projectId se guarda y se lee', () async {
      await repo.saveLoreItem(const LoreItemModel(id: 'l', name: 'Torre', category: LoreCategory.location, projectId: 'A'));
      expect((await repo.getLoreItem('l'))!.projectId, 'A');
    });

    test('migra una base v2: las fichas existentes quedan compartidas', () async {
      final path = p.join(tempDir.path, 'old.db');
      final old = await openDatabase(path, version: 2, onCreate: (db, _) async {
        await db.execute("CREATE TABLE characters (id TEXT PRIMARY KEY, name TEXT NOT NULL, aliases TEXT NOT NULL DEFAULT '[]', appearance TEXT NOT NULL DEFAULT '', personality_traits TEXT NOT NULL DEFAULT '[]', motivation TEXT NOT NULL DEFAULT '', secrets_limits TEXT NOT NULL DEFAULT '', relationships TEXT NOT NULL DEFAULT '[]', force_include INTEGER NOT NULL DEFAULT 0, visible_from_chapter INTEGER NOT NULL DEFAULT 0)");
        await db.execute("CREATE TABLE lore_items (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, short_description TEXT NOT NULL DEFAULT '', long_details TEXT NOT NULL DEFAULT '', tags TEXT NOT NULL DEFAULT '[]', force_include INTEGER NOT NULL DEFAULT 0, visible_from_chapter INTEGER NOT NULL DEFAULT 0)");
        await db.insert('characters', {'id': 'c', 'name': 'Vieja'});
        await db.insert('lore_items', {'id': 'l', 'name': 'Vieja torre', 'category': 'location'});
      });
      await old.close();

      final migrated = LoreRepository(databasePath: path);
      addTearDown(migrated.close);

      expect((await migrated.getCharacter('c'))!.projectId, isNull);
      expect((await migrated.getLoreItem('l'))!.projectId, isNull);
      expect((await migrated.getCharacter('c'))!.appliesTo('cualquiera'), isTrue);
    });
  });

  test('la wiki de un proyecto no publica fichas de otro', () {
    final project = ProjectModel(id: 'A', title: 'Libro A', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    final files = WikiExportService.buildFiles(
      project: project,
      chapters: const [],
      characters: const [shared, inA, inB],
      loreItems: const [
        LoreItemModel(id: 'l1', name: 'Torre de A', category: LoreCategory.location, projectId: 'A'),
        LoreItemModel(id: 'l2', name: 'Torre de B', category: LoreCategory.location, projectId: 'B'),
      ],
      events: const [],
    );
    final all = files.values.join();
    expect(all, allOf(contains('Aldric'), contains('Brenna'), contains('Torre de A')));
    expect(all, allOf(isNot(contains('Cormac')), isNot(contains('Torre de B'))));
  });
}
