import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models/project_model.dart';
import 'models/story_node_model.dart';

/// SQLite-backed CRUD store for projects, chapters and their branching
/// story nodes. A single `Database` instance is opened lazily and reused
/// for the app's lifetime.
class ProjectRepository {
  static const _dbFileName = 'aura_projects.db';
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
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            synopsis TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE chapters (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            order_index INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE story_nodes (
            id TEXT PRIMARY KEY,
            chapter_id TEXT NOT NULL,
            parent_node_id TEXT,
            content TEXT NOT NULL DEFAULT '',
            branch_name TEXT NOT NULL DEFAULT '',
            timestamp TEXT NOT NULL
          )
        ''');
      },
    );
  }

  static String generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  // ---- Projects ---------------------------------------------------------

  Future<void> saveProject(ProjectModel project) async {
    final db = await _database;
    await db.insert('projects', project.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ProjectModel>> getAllProjects() async {
    final db = await _database;
    final rows = await db.query('projects', orderBy: 'updated_at DESC');
    return rows.map(ProjectModel.fromMap).toList();
  }

  Future<ProjectModel?> getProject(String id) async {
    final db = await _database;
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProjectModel.fromMap(rows.first);
  }

  /// Deletes the project along with every chapter and story node under it.
  Future<void> deleteProjectCascade(String projectId) async {
    final db = await _database;
    final chapters = await db.query('chapters', columns: ['id'], where: 'project_id = ?', whereArgs: [projectId]);
    final batch = db.batch();
    for (final chapter in chapters) {
      batch.delete('story_nodes', where: 'chapter_id = ?', whereArgs: [chapter['id']]);
    }
    batch.delete('chapters', where: 'project_id = ?', whereArgs: [projectId]);
    batch.delete('projects', where: 'id = ?', whereArgs: [projectId]);
    await batch.commit(noResult: true);
  }

  // ---- Chapters -----------------------------------------------------------

  Future<void> saveChapter(ChapterModel chapter) async {
    final db = await _database;
    await db.insert('chapters', chapter.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChapterModel>> getChaptersForProject(String projectId) async {
    final db = await _database;
    final rows = await db.query('chapters', where: 'project_id = ?', whereArgs: [projectId], orderBy: 'order_index ASC');
    return rows.map(ChapterModel.fromMap).toList();
  }

  /// Deletes the chapter along with every story node under it.
  Future<void> deleteChapterCascade(String chapterId) async {
    final db = await _database;
    final batch = db.batch();
    batch.delete('story_nodes', where: 'chapter_id = ?', whereArgs: [chapterId]);
    batch.delete('chapters', where: 'id = ?', whereArgs: [chapterId]);
    await batch.commit(noResult: true);
  }

  // ---- Story nodes --------------------------------------------------------

  Future<void> saveNode(StoryNodeModel node) async {
    final db = await _database;
    await db.insert('story_nodes', node.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<StoryNodeModel>> getNodesForChapter(String chapterId) async {
    final db = await _database;
    final rows = await db.query('story_nodes', where: 'chapter_id = ?', whereArgs: [chapterId], orderBy: 'timestamp ASC');
    return rows.map(StoryNodeModel.fromMap).toList();
  }

  Future<StoryNodeModel?> getNode(String id) async {
    final db = await _database;
    final rows = await db.query('story_nodes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : StoryNodeModel.fromMap(rows.first);
  }

  /// Most recently saved node for the chapter — used as the default content
  /// source when exporting without picking a specific branch.
  Future<StoryNodeModel?> getLatestNodeForChapter(String chapterId) async {
    final db = await _database;
    final rows = await db.query(
      'story_nodes',
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : StoryNodeModel.fromMap(rows.first);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
