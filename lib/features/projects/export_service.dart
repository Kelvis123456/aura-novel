import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'models/project_model.dart';

enum ExportFormat { txt, pdf, epub }

extension ExportFormatLabel on ExportFormat {
  String get label => switch (this) {
        ExportFormat.txt => 'TXT (texto plano)',
        ExportFormat.pdf => 'PDF (maquetado)',
        ExportFormat.epub => 'EPUB (libro electrónico)',
      };

  String get extension => switch (this) {
        ExportFormat.txt => 'txt',
        ExportFormat.pdf => 'pdf',
        ExportFormat.epub => 'epub',
      };
}

/// Compiles a project's chapters into a downloadable/shareable file. The
/// caller resolves which text represents each chapter (typically the latest
/// or a specifically chosen [StoryNodeModel]) and passes it in as
/// `contentByChapterId` — this service only cares about the final strings.
class ExportService {
  /// Writes the compiled file to the temp directory and returns it. Call
  /// [shareFile] afterwards to hand it to the OS share sheet via `share_plus`.
  Future<File> exportProject({
    required ProjectModel project,
    required List<ChapterModel> chapters,
    required Map<String, String> contentByChapterId,
    required ExportFormat format,
    String author = 'Autor desconocido',
  }) {
    switch (format) {
      case ExportFormat.txt:
        return _exportTxt(project, chapters, contentByChapterId);
      case ExportFormat.pdf:
        return _exportPdf(project, chapters, contentByChapterId, author);
      case ExportFormat.epub:
        return _exportEpub(project, chapters, contentByChapterId, author);
    }
  }

  Future<void> shareFile(File file, {String? subject}) {
    return Share.shareXFiles([XFile(file.path)], subject: subject ?? p.basenameWithoutExtension(file.path));
  }

  // ---- TXT ----------------------------------------------------------------

  Future<File> _exportTxt(
    ProjectModel project,
    List<ChapterModel> chapters,
    Map<String, String> contentByChapterId,
  ) async {
    final buffer = StringBuffer()
      ..writeln(project.title)
      ..writeln();

    if (project.synopsis.trim().isNotEmpty) {
      buffer
        ..writeln(project.synopsis.trim())
        ..writeln();
    }

    for (final chapter in chapters) {
      buffer
        ..writeln('— ${chapter.title} —')
        ..writeln()
        ..writeln((contentByChapterId[chapter.id] ?? '').trim())
        ..writeln()
        ..writeln();
    }

    return _writeToTempFile('${_slug(project.title)}.txt', utf8.encode(buffer.toString()));
  }

  // ---- PDF ------------------------------------------------------------------

  Future<File> _exportPdf(
    ProjectModel project,
    List<ChapterModel> chapters,
    Map<String, String> contentByChapterId,
    String author,
  ) async {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: pw.Font.times(), bold: pw.Font.timesBold()),
    );

    for (final chapter in chapters) {
      final content = (contentByChapterId[chapter.id] ?? '').trim();
      final paragraphs = content.split(RegExp(r'\n\s*\n')).where((paragraph) => paragraph.trim().isNotEmpty);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 48),
          header: (context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text(
              project.title,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
          footer: (context) => pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 12),
            child: pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
          build: (context) => [
            pw.Text(chapter.title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            for (final paragraph in paragraphs)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Paragraph(
                  text: paragraph.trim(),
                  style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
                ),
              ),
          ],
        ),
      );
    }

    final bytes = await doc.save();
    return _writeToTempFile('${_slug(project.title)}.pdf', bytes);
  }

  // ---- EPUB -----------------------------------------------------------------

  Future<File> _exportEpub(
    ProjectModel project,
    List<ChapterModel> chapters,
    Map<String, String> contentByChapterId,
    String author,
  ) {
    final bytes = buildEpubBytes(project, chapters, contentByChapterId, author);
    return _writeToTempFile('${_slug(project.title)}.epub', bytes);
  }

  /// The EPUB zip as bytes, with no file I/O so it can be tested directly.
  static List<int> buildEpubBytes(
    ProjectModel project,
    List<ChapterModel> chapters,
    Map<String, String> contentByChapterId,
    String author,
  ) {
    final archive = Archive();

    void addText(String path, String content, {bool compress = true}) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes)..compress = compress);
    }

    // The EPUB spec wants `mimetype` first and stored uncompressed.
    addText('mimetype', 'application/epub+zip', compress: false);

    addText('META-INF/container.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

    final manifestItems = StringBuffer();
    final spineItems = StringBuffer();
    final navPoints = StringBuffer();

    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final fileName = 'chapter_${i + 1}.xhtml';
      final content = (contentByChapterId[chapter.id] ?? '')
          .split(RegExp(r'\n\s*\n'))
          .where((paragraph) => paragraph.trim().isNotEmpty)
          .map((paragraph) => '<p>${_escapeXml(paragraph.trim())}</p>')
          .join('\n');

      addText('OEBPS/$fileName', '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>${_escapeXml(chapter.title)}</title></head>
<body>
<h1>${_escapeXml(chapter.title)}</h1>
$content
</body>
</html>''');

      manifestItems.writeln('<item id="chap${i + 1}" href="$fileName" media-type="application/xhtml+xml"/>');
      spineItems.writeln('<itemref idref="chap${i + 1}"/>');
      navPoints.writeln('''
<navPoint id="navPoint-${i + 1}" playOrder="${i + 1}">
  <navLabel><text>${_escapeXml(chapter.title)}</text></navLabel>
  <content src="$fileName"/>
</navPoint>''');
    }

    addText('OEBPS/content.opf', '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>${_escapeXml(project.title)}</dc:title>
    <dc:creator>${_escapeXml(author)}</dc:creator>
    <dc:identifier id="BookId">urn:uuid:${project.id}</dc:identifier>
    <dc:language>es</dc:language>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    $manifestItems
  </manifest>
  <spine toc="ncx">
    $spineItems
  </spine>
</package>''');

    addText('OEBPS/toc.ncx', '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head/>
  <docTitle><text>${_escapeXml(project.title)}</text></docTitle>
  <navMap>
    $navPoints
  </navMap>
</ncx>''');

    return ZipEncoder().encode(archive)!;
  }

  static String _escapeXml(String input) =>
      input.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  Future<File> _writeToTempFile(String fileName, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _slug(String input) {
    final slug = input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return slug.isEmpty ? 'aura_novel' : slug;
  }
}
