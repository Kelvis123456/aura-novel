import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models/project_model.dart';
import 'models/map_pin_model.dart';
import 'models/story_node_model.dart';
import 'models/timeline_event_model.dart';

/// SQLite-backed CRUD store for projects, chapters and their branching
/// story nodes. A single `Database` instance is opened lazily and reused
/// for the app's lifetime.
class ProjectRepository {
  static const _dbFileName = 'aura_projects.db';
  static const _dbVersion = 6;
  static final _random = Random();

  final String? _databasePath;
  Database? _db;

  /// [databasePath] is only for tests; the app uses the default location.
  ProjectRepository({String? databasePath}) : _databasePath = databasePath;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = _databasePath ?? p.join(await getDatabasesPath(), _dbFileName);
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
            updated_at TEXT NOT NULL,
            calendar TEXT NOT NULL DEFAULT '',
            map_path TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE chapters (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            order_index INTEGER NOT NULL DEFAULT 0,
            summary TEXT NOT NULL DEFAULT ''
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
        await _createDraftsTable(db);
        await _createTimelineTable(db);
        await _createMapPinsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // One block per version, so a DB two versions behind runs both.
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE chapters ADD COLUMN summary TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 3) {
          await _createDraftsTable(db);
        }
        if (oldVersion < 4) {
          await _createTimelineTable(db);
        }
        if (oldVersion < 5) {
          await db.execute("ALTER TABLE projects ADD COLUMN calendar TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 6) {
          await db.execute("ALTER TABLE projects ADD COLUMN map_path TEXT NOT NULL DEFAULT ''");
          await _createMapPinsTable(db);
        }
      },
    );
  }

  Future<void> _createDraftsTable(Database db) => db.execute('''
    CREATE TABLE drafts (
      chapter_id TEXT PRIMARY KEY,
      node_id TEXT NOT NULL,
      content TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  Future<void> _createTimelineTable(Database db) => db.execute('''
    CREATE TABLE timeline_events (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL,
      chapter_id TEXT,
      title TEXT NOT NULL,
      world_date TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0
    )
  ''');

  Future<void> _createMapPinsTable(Database db) => db.execute('''
    CREATE TABLE map_pins (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL,
      x REAL NOT NULL,
      y REAL NOT NULL,
      label TEXT NOT NULL DEFAULT '',
      lore_item_id TEXT
    )
  ''');

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
    for (final chapter in chapters) {
      batch.delete('drafts', where: 'chapter_id = ?', whereArgs: [chapter['id']]);
    }
    batch.delete('timeline_events', where: 'project_id = ?', whereArgs: [projectId]);
    batch.delete('map_pins', where: 'project_id = ?', whereArgs: [projectId]);
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

  Future<void> updateChapterSummary(String chapterId, String summary) async {
    final db = await _database;
    await db.update('chapters', {'summary': summary}, where: 'id = ?', whereArgs: [chapterId]);
  }

  /// Deletes the chapter along with every story node under it.
  Future<void> deleteChapterCascade(String chapterId) async {
    final db = await _database;
    final batch = db.batch();
    batch.delete('story_nodes', where: 'chapter_id = ?', whereArgs: [chapterId]);
    batch.delete('drafts', where: 'chapter_id = ?', whereArgs: [chapterId]);
    batch.update('timeline_events', {'chapter_id': null}, where: 'chapter_id = ?', whereArgs: [chapterId]);
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

  // ---- Timeline -----------------------------------------------------------

  Future<void> saveTimelineEvent(TimelineEvent event) async {
    final db = await _database;
    await db.insert('timeline_events', event.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TimelineEvent>> getTimelineEvents(String projectId) async {
    final db = await _database;
    final rows = await db.query('timeline_events',
        where: 'project_id = ?', whereArgs: [projectId], orderBy: 'position ASC, title ASC');
    return rows.map(TimelineEvent.fromMap).toList();
  }

  Future<void> deleteTimelineEvent(String id) async {
    final db = await _database;
    await db.delete('timeline_events', where: 'id = ?', whereArgs: [id]);
  }

  /// Rewrites `position` to match the order of [ids] (drag-and-drop result).
  Future<void> reorderTimeline(List<String> ids) async {
    final db = await _database;
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update('timeline_events', {'position': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
  }

  // ---- Map pins -----------------------------------------------------------

  Future<void> saveMapPin(MapPin pin) async {
    final db = await _database;
    await db.insert('map_pins', pin.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MapPin>> getMapPins(String projectId) async {
    final db = await _database;
    final rows = await db.query('map_pins', where: 'project_id = ?', whereArgs: [projectId]);
    return rows.map(MapPin.fromMap).toList();
  }

  Future<void> deleteMapPin(String id) async {
    final db = await _database;
    await db.delete('map_pins', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Backup ---------------------------------------------------------------

  /// Raw rows of every table that holds the author's work. Drafts are left
  /// out: they are transient and tied to ids that may not exist elsewhere.
  Future<Map<String, List<Map<String, Object?>>>> exportAll() async {
    final db = await _database;
    return {
      'projects': await db.query('projects'),
      'chapters': await db.query('chapters'),
      'story_nodes': await db.query('story_nodes'),
      'timeline_events': await db.query('timeline_events'),
      'map_pins': await db.query('map_pins'),
    };
  }

  /// Merges [data] into the DB: rows with an existing id are replaced, the
  /// rest are kept. All or nothing, so a bad file can't leave half a restore.
  Future<void> importAll(Map<String, List<Map<String, Object?>>> data) async {
    final db = await _database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final table in const ['projects', 'chapters', 'story_nodes', 'timeline_events', 'map_pins']) {
        for (final row in data[table] ?? const <Map<String, Object?>>[]) {
          batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  // ---- Drafts -------------------------------------------------------------

  /// One unsaved working copy per chapter, written by the editor's autosave
  /// so a crash or a killed app doesn't lose what was typed since the last
  /// "Guardar versión".
  Future<void> saveDraft(ChapterDraft draft) async {
    final db = await _database;
    await db.insert('drafts', draft.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ChapterDraft?> getDraft(String chapterId) async {
    final db = await _database;
    final rows = await db.query('drafts', where: 'chapter_id = ?', whereArgs: [chapterId], limit: 1);
    return rows.isEmpty ? null : ChapterDraft.fromMap(rows.first);
  }

  Future<void> deleteDraft(String chapterId) async {
    final db = await _database;
    await db.delete('drafts', where: 'chapter_id = ?', whereArgs: [chapterId]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// Unsaved text of a chapter, tied to the story node it was edited from.
class ChapterDraft {
  final String chapterId;
  final String nodeId;
  final String content;
  final DateTime updatedAt;

  const ChapterDraft({
    required this.chapterId,
    required this.nodeId,
    required this.content,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'chapter_id': chapterId,
        'node_id': nodeId,
        'content': content,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ChapterDraft.fromMap(Map<String, dynamic> map) => ChapterDraft(
        chapterId: map['chapter_id'] as String,
        nodeId: map['node_id'] as String,
        content: map['content'] as String? ?? '',
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
