import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:aura_novel/features/projects/export_service.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final project = ProjectModel(
    id: 'p1',
    title: 'Ceniza & Sal',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
  const chapters = [
    ChapterModel(id: 'a', projectId: 'p1', title: 'Uno <1>', order: 0),
    ChapterModel(id: 'b', projectId: 'p1', title: 'Dos', order: 1),
  ];
  const content = {'a': 'Primer párrafo.\n\nSegundo & último.', 'b': 'Solo uno.'};

  Archive build() => ZipDecoder().decodeBytes(ExportService.buildEpubBytes(project, chapters, content, 'Kelvis'));

  String text(Archive archive, String path) => utf8.decode(archive.findFile(path)!.content as List<int>);

  test('mimetype es la primera entrada y va sin comprimir', () {
    final bytes = ExportService.buildEpubBytes(project, chapters, content, 'Kelvis');
    // Cabecera local del primer fichero: "mimetype" + el contenido pegado,
    // sin compresión, empiezan en el byte 30.
    expect(utf8.decode(bytes.sublist(30, 30 + 8)), 'mimetype');
    expect(utf8.decode(bytes.sublist(38, 38 + 20)), 'application/epub+zip');
  });

  test('incluye container, opf, ncx y un xhtml por capítulo', () {
    final names = build().files.map((f) => f.name).toList();
    expect(
      names,
      containsAll([
        'META-INF/container.xml',
        'OEBPS/content.opf',
        'OEBPS/toc.ncx',
        'OEBPS/chapter_1.xhtml',
        'OEBPS/chapter_2.xhtml',
      ]),
    );
  });

  test('escapa XML en títulos y texto', () {
    final archive = build();
    expect(text(archive, 'OEBPS/chapter_1.xhtml'), contains('Uno &lt;1&gt;'));
    expect(text(archive, 'OEBPS/chapter_1.xhtml'), contains('Segundo &amp; último.'));
    expect(text(archive, 'OEBPS/content.opf'), contains('Ceniza &amp; Sal'));
  });

  test('cada párrafo separado por línea en blanco va en su propio <p>', () {
    final xhtml = text(build(), 'OEBPS/chapter_1.xhtml');
    expect('<p>'.allMatches(xhtml).length, 2);
  });

  test('docx lleva portada, un encabezado por capítulo y escapa el texto', () {
    final archive = ZipDecoder().decodeBytes(ExportService.buildDocxBytes(project, chapters, content, 'Kelvis'));
    expect(archive.files.map((f) => f.name), containsAll(['[Content_Types].xml', '_rels/.rels', 'word/document.xml', 'word/styles.xml']));
    final doc = text(archive, 'word/document.xml');
    expect(RegExp('w:pStyle w:val="Heading1"').allMatches(doc), hasLength(2));
    expect(doc, contains('Uno &lt;1&gt;'));
    expect(doc, contains('Segundo &amp; último.'));
    expect(RegExp('<w:p>').allMatches(doc).length, 7);
  });

  test('un capítulo sin contenido no rompe el export', () {
    final archive = ZipDecoder().decodeBytes(ExportService.buildEpubBytes(project, chapters, const {}, 'Kelvis'));
    expect(archive.findFile('OEBPS/chapter_2.xhtml'), isNotNull);
  });
}
