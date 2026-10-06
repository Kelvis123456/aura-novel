import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models/character_model.dart';
import 'models/lore_item_model.dart';

/// SQLite-backed CRUD store for characters and lore items. A single
/// `Database` instance is opened lazily and reused for the app's lifetime.
class LoreRepository {
  static const _dbFileName = 'aura_lore.db';
  static const _dbVersion = 1;
  static final _random = Random();

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), _dbFileName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE characters (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            aliases TEXT NOT NULL DEFAULT '[]',
            appearance TEXT NOT NULL DEFAULT '',
            personality_traits TEXT NOT NULL DEFAULT '[]',
            motivation TEXT NOT NULL DEFAULT '',
            secrets_limits TEXT NOT NULL DEFAULT '',
            relationships TEXT NOT NULL DEFAULT '[]',
            force_include INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE lore_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            short_description TEXT NOT NULL DEFAULT '',
            long_details TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '[]',
            force_include INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  static String generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  // ---- Characters -----------------------------------------------------

  Future<void> saveCharacter(CharacterModel character) async {
    final db = await _database;
    await db.insert('characters', character.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCharacter(String id) async {
    final db = await _database;
    await db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }

  Future<CharacterModel?> getCharacter(String id) async {
    final db = await _database;
    final rows = await db.query('characters', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : CharacterModel.fromMap(rows.first);
  }

  Future<List<CharacterModel>> getAllCharacters() async {
    final db = await _database;
    final rows = await db.query('characters', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(CharacterModel.fromMap).toList();
  }

  // ---- Lore items -------------------------------------------------------

  Future<void> saveLoreItem(LoreItemModel item) async {
    final db = await _database;
    await db.insert('lore_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteLoreItem(String id) async {
    final db = await _database;
    await db.delete('lore_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<LoreItemModel?> getLoreItem(String id) async {
    final db = await _database;
    final rows = await db.query('lore_items', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LoreItemModel.fromMap(rows.first);
  }

  Future<List<LoreItemModel>> getAllLoreItems() async {
    final db = await _database;
    final rows = await db.query('lore_items', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(LoreItemModel.fromMap).toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
