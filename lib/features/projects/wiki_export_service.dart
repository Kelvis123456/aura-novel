import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../lore/models/character_model.dart';
import '../lore/models/lore_item_model.dart';
import 'models/project_model.dart';
import 'models/timeline_event_model.dart';

/// Builds a static wiki (plain HTML + one stylesheet) from the lore studio
/// and the timeline. [upToChapter] hides everything a reader who stopped at
/// that chapter shouldn't know yet; null publishes the whole book.
/// Character secrets and the "limits" field are never published.
class WikiExportService {
  /// Pure and synchronous so it can be tested without touching the disk.
  /// Keys are file names, values the file contents.
  static Map<String, String> buildFiles({
    required ProjectModel project,
    required List<ChapterModel> chapters,
    required List<CharacterModel> characters,
    required List<LoreItemModel> loreItems,
    required List<TimelineEvent> events,
    int? upToChapter,
  }) {
    bool shown(int visibleFrom) => upToChapter == null || visibleFrom == 0 || visibleFrom <= upToChapter;

    final chapterNumber = {for (var i = 0; i < chapters.length; i++) chapters[i].id: i + 1};
    final visibleCharacters = characters.where((c) => shown(c.visibleFromChapter)).toList();
    final visibleLore = loreItems.where((l) => shown(l.visibleFromChapter)).toList();
    final visibleEvents = events.where((e) {
      if (upToChapter == null) return true;
      final number = chapterNumber[e.chapterId];
      // An event with no chapter has nothing to say when it becomes public.
      return number != null && number <= upToChapter;
    }).toList();

    final characterFile = {
      for (var i = 0; i < visibleCharacters.length; i++) visibleCharacters[i].id: 'personaje-${i + 1}-${_slug(visibleCharacters[i].name)}.html',
    };
    final loreFile = {
      for (var i = 0; i < visibleLore.length; i++) visibleLore[i].id: 'lore-${i + 1}-${_slug(visibleLore[i].name)}.html',
    };
    final nameById = {for (final c in visibleCharacters) c.id: c.name};

    final files = <String, String>{'style.css': _css};

    for (final c in visibleCharacters) {
      final body = StringBuffer('<h1>${_e(c.name)}</h1>');
      if (c.aliases.isNotEmpty) body.write('<p class="meta">También: ${_e(c.aliases.join(', '))}</p>');
      if (c.appearance.trim().isNotEmpty) body.write('<h2>Apariencia</h2><p>${_para(c.appearance)}</p>');
      if (c.personalityTraits.isNotEmpty) body.write('<h2>Personalidad</h2><p>${_e(c.personalityTraits.join(', '))}</p>');
      if (c.motivation.trim().isNotEmpty) body.write('<h2>Motivación</h2><p>${_para(c.motivation)}</p>');
      final relations = c.relationships.where((r) => nameById.containsKey(r.characterId)).toList();
      if (relations.isNotEmpty) {
        body.write('<h2>Relaciones</h2><ul>');
        for (final r in relations) {
          body.write('<li><a href="${characterFile[r.characterId]}">${_e(nameById[r.characterId]!)}</a>: ${_e(r.description)}</li>');
        }
        body.write('</ul>');
      }
      files[characterFile[c.id]!] = _page(c.name, project.title, body.toString());
    }

    for (final l in visibleLore) {
      final body = StringBuffer('<h1>${_e(l.name)}</h1><p class="meta">${_e(l.category.label)}</p>');
      if (l.shortDescription.trim().isNotEmpty) body.write('<p>${_para(l.shortDescription)}</p>');
      if (l.longDetails.trim().isNotEmpty) body.write('<p>${_para(l.longDetails)}</p>');
      files[loreFile[l.id]!] = _page(l.name, project.title, body.toString());
    }

    if (visibleEvents.isNotEmpty) {
      final body = StringBuffer('<h1>Línea de tiempo</h1><ol class="timeline">');
      for (final e in visibleEvents) {
        body.write('<li><strong>${_e(e.title)}</strong>');
        if (e.worldDate.isNotEmpty) body.write(' <span class="meta">${_e(e.worldDate)}</span>');
        if (e.description.trim().isNotEmpty) body.write('<br>${_para(e.description)}');
        body.write('</li>');
      }
      body.write('</ol>');
      files['linea-de-tiempo.html'] = _page('Línea de tiempo', project.title, body.toString());
    }

    final index = StringBuffer('<h1>${_e(project.title)}</h1>');
    if (project.synopsis.trim().isNotEmpty) index.write('<p>${_para(project.synopsis)}</p>');
    if (visibleCharacters.isNotEmpty) {
      index.write('<h2>Personajes</h2><ul>');
      for (final c in visibleCharacters) {
        index.write('<li><a href="${characterFile[c.id]}">${_e(c.name)}</a></li>');
      }
      index.write('</ul>');
    }
    for (final category in LoreCategory.values) {
      final inCategory = visibleLore.where((l) => l.category == category).toList();
      if (inCategory.isEmpty) continue;
      index.write('<h2>${_e(category.label)}</h2><ul>');
      for (final l in inCategory) {
        index.write('<li><a href="${loreFile[l.id]}">${_e(l.name)}</a></li>');
      }
      index.write('</ul>');
    }
    if (files.containsKey('linea-de-tiempo.html')) {
      index.write('<h2>Cronología</h2><p><a href="linea-de-tiempo.html">Ver la línea de tiempo</a></p>');
    }
    files['index.html'] = _page(project.title, project.title, index.toString());
    return files;
  }

  /// Zips the wiki into the temp directory and opens the share sheet.
  Future<void> exportAndShare(Map<String, String> files, String projectTitle) async {
    final archive = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw StateError('No se pudo generar el zip de la wiki.');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'wiki_${_slug(projectTitle)}.zip'));
    await file.writeAsBytes(zip, flush: true);
    await Share.shareXFiles([XFile(file.path)], subject: 'Wiki de $projectTitle');
  }

  static String _page(String title, String site, String body) => '''<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_e(title)} · ${_e(site)}</title><link rel="stylesheet" href="style.css"></head>
<body><nav><a href="index.html">${_e(site)}</a></nav><main>$body</main></body></html>
''';

  static String _e(String text) => const HtmlEscape(HtmlEscapeMode.element).convert(text).replaceAll('"', '&quot;');

  /// Escapes and keeps the author's line breaks.
  static String _para(String text) => _e(text.trim()).replaceAll('\n', '<br>');

  static String _slug(String text) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      final i = from.indexOf(ch);
      buffer.write(i >= 0 ? to[i] : ch);
    }
    final slug = buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'wiki' : slug;
  }

  static const _css = '''body{font-family:Georgia,serif;max-width:42rem;margin:0 auto;padding:1rem;line-height:1.6;color:#222;background:#fafafa}
nav{margin-bottom:1.5rem;font-family:sans-serif;font-size:.9rem}
a{color:#8b1a2b}
h1{margin-bottom:.2rem}
.meta{color:#777;font-size:.9rem;margin-top:0}
.timeline li{margin-bottom:1rem}
''';
}
