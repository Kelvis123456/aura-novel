import 'dart:io';

import 'package:aura_novel/features/lore/lore_repository.dart';
import 'package:aura_novel/features/lore/models/character_model.dart';
import 'package:aura_novel/features/lore/models/lore_item_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('aura_lore_vis_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('guarda y lee visibleFromChapter en personajes y lore', () async {
    final repo = LoreRepository(databasePath: p.join(tempDir.path, 'lore.db'));
    addTearDown(repo.close);

    await repo.saveCharacter(const CharacterModel(id: 'c', name: 'Mara', visibleFromChapter: 3));
    await repo.saveLoreItem(const LoreItemModel(id: 'l', name: 'Torre', category: LoreCategory.location, visibleFromChapter: 5));

    expect((await repo.getCharacter('c'))!.visibleFromChapter, 3);
    expect((await repo.getLoreItem('l'))!.visibleFromChapter, 5);
  });

  test('migra una base v1 conservando datos, con visibilidad 0', () async {
    final path = p.join(tempDir.path, 'old.db');
    final old = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute("CREATE TABLE characters (id TEXT PRIMARY KEY, name TEXT NOT NULL, aliases TEXT NOT NULL DEFAULT '[]', appearance TEXT NOT NULL DEFAULT '', personality_traits TEXT NOT NULL DEFAULT '[]', motivation TEXT NOT NULL DEFAULT '', secrets_limits TEXT NOT NULL DEFAULT '', relationships TEXT NOT NULL DEFAULT '[]', force_include INTEGER NOT NULL DEFAULT 0)");
      await db.execute("CREATE TABLE lore_items (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, short_description TEXT NOT NULL DEFAULT '', long_details TEXT NOT NULL DEFAULT '', tags TEXT NOT NULL DEFAULT '[]', force_include INTEGER NOT NULL DEFAULT 0)");
      await db.insert('characters', {'id': 'c', 'name': 'Vieja'});
      await db.insert('lore_items', {'id': 'l', 'name': 'Vieja torre', 'category': 'location'});
    });
    await old.close();

    final repo = LoreRepository(databasePath: path);
    addTearDown(repo.close);

    final character = await repo.getCharacter('c');
    expect(character!.name, 'Vieja');
    expect(character.visibleFromChapter, 0);
    expect((await repo.getLoreItem('l'))!.visibleFromChapter, 0);
  });
}
