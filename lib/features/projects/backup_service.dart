import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../lore/lore_repository.dart';
import 'project_repository.dart';

class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);

  @override
  String toString() => message;
}

/// What a restore brought in, for the confirmation message.
class BackupSummary {
  final int projects;
  final int chapters;
  final int characters;
  final int loreItems;

  const BackupSummary({
    required this.projects,
    required this.chapters,
    required this.characters,
    required this.loreItems,
  });
}

/// Whole-app backup as one JSON file: projects, chapters, every version and
/// the lore studio. The API key and endpoint are never included.
class BackupService {
  static const _format = 'aura-novel-backup';
  static const _version = 1;

  final ProjectRepository _projects;
  final LoreRepository _lore;

  BackupService({required ProjectRepository projects, required LoreRepository lore})
      : _projects = projects,
        _lore = lore;

  Future<String> buildJson() async {
    final projectData = await _projects.exportAll();
    final loreData = await _lore.exportAll();
    return const JsonEncoder.withIndent(' ').convert({
      'format': _format,
      'version': _version,
      'createdAt': DateTime.now().toIso8601String(),
      ...projectData,
      ...loreData,
    });
  }

  /// Writes the backup to the temp directory and opens the share sheet.
  Future<void> exportAndShare() async {
    final json = await buildJson();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File(p.join(dir.path, 'aura_novel_$stamp.json'));
    await file.writeAsString(json, flush: true);
    await Share.shareXFiles([XFile(file.path)], subject: 'Copia de seguridad de Aura Novel');
  }

  /// Merges a backup into the current data. Throws [BackupFormatException]
  /// before touching anything if the file isn't a usable backup. Each of the
  /// two databases is restored atomically, but not both together.
  Future<BackupSummary> restoreFromJson(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const BackupFormatException('El archivo no es un JSON válido.');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != _format) {
      throw const BackupFormatException('Este archivo no es una copia de seguridad de Aura Novel.');
    }
    final root = decoded;
    final version = root['version'];
    if (version is! int || version > _version) {
      throw const BackupFormatException('La copia es de una versión más nueva de la app. Actualiza e inténtalo de nuevo.');
    }

    List<Map<String, Object?>> table(String name) {
      final raw = root[name];
      if (raw == null) return const [];
      if (raw is! List || raw.any((row) => row is! Map<String, dynamic>)) {
        throw BackupFormatException('La tabla "$name" de la copia está dañada.');
      }
      return raw.cast<Map<String, Object?>>();
    }

    final projects = table('projects');
    final chapters = table('chapters');
    final nodes = table('story_nodes');
    final characters = table('characters');
    final loreItems = table('lore_items');

    await _projects.importAll({'projects': projects, 'chapters': chapters, 'story_nodes': nodes});
    await _lore.importAll({'characters': characters, 'lore_items': loreItems});

    return BackupSummary(
      projects: projects.length,
      chapters: chapters.length,
      characters: characters.length,
      loreItems: loreItems.length,
    );
  }
}
