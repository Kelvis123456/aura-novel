import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'models/project_model.dart';

enum ExportFormat { txt, pdf, epub, docx }

extension ExportFormatLabel on ExportFormat {
  String get label => switch (this) {
        ExportFormat.txt => 'TXT (texto plano)',
        ExportFormat.pdf => 'PDF (maquetado)',
        ExportFormat.epub => 'EPUB (libro electrónico)',
        ExportFormat.docx => 'DOCX (manuscrito para Word)',
      };

  String get extension => switch (this) {
        ExportFormat.txt => 'txt',
        ExportFormat.pdf => 'pdf',
        ExportFormat.epub => 'epub',
        ExportFormat.docx => 'docx',
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
      case ExportFormat.docx:
        return _writeToTempFile('${_slug(project.title)}.docx', buildDocxBytes(project, chapters, contentByChapterId, author));
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
            pw.Text(chapter.title, style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
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
      archive.addFile(ArchiveFile.bytes(path, bytes)..compression = compress ? CompressionType.deflate : CompressionType.none);
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

    return ZipEncoder().encode(archive);
  }

  /// A manuscript-style .docx: Times New Roman 12, double spaced, indented paragraphs, a title
  /// page and every chapter on a new page (what agents and publishers ask for).
  static List<int> buildDocxBytes(
    ProjectModel project,
    List<ChapterModel> chapters,
    Map<String, String> contentByChapterId,
    String author,
  ) {
    String para(String text, {String style = '', bool pageBreakBefore = false}) {
      final props = [
        if (style.isNotEmpty) '<w:pStyle w:val="$style"/>',
        if (pageBreakBefore) '<w:pageBreakBefore/>',
      ].join();
      return '<w:p>${props.isEmpty ? '' : '<w:pPr>$props</w:pPr>'}<w:r><w:t xml:space="preserve">${_escapeXml(text)}</w:t></w:r></w:p>';
    }

    final body = StringBuffer()
      ..write(para(project.title, style: 'Title'))
      ..write(para(author, style: 'Subtitle'));
    for (final chapter in chapters) {
      body.write(para(chapter.title, style: 'Heading1', pageBreakBefore: true));
      final paragraphs = (contentByChapterId[chapter.id] ?? '').split(RegExp(r'\n\s*\n')).where((t) => t.trim().isNotEmpty);
      for (final paragraph in paragraphs) {
        body.write(para(paragraph.trim().replaceAll(RegExp(r'\s*\n\s*'), ' ')));
      }
    }

    const ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
    final archive = Archive();
    void add(String path, String content) => archive.addFile(ArchiveFile.bytes(path, utf8.encode(content)));

    add('[Content_Types].xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''');
    add('_rels/.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''');
    add('word/_rels/document.xml.rels', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');
    add('word/styles.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles $ns>
  <w:docDefaults>
    <w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/><w:lang w:val="es-ES"/></w:rPr></w:rPrDefault>
    <w:pPrDefault><w:pPr><w:spacing w:line="480" w:lineRule="auto"/><w:ind w:firstLine="720"/></w:pPr></w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:before="4000" w:after="240" w:line="240" w:lineRule="auto"/><w:ind w:firstLine="0"/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/>
    <w:pPr><w:spacing w:line="240" w:lineRule="auto"/><w:ind w:firstLine="0"/><w:jc w:val="center"/></w:pPr><w:rPr><w:sz w:val="28"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>
    <w:pPr><w:keepNext/><w:spacing w:before="2400" w:after="480" w:line="240" w:lineRule="auto"/><w:ind w:firstLine="0"/><w:jc w:val="center"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
</w:styles>''');
    add('word/document.xml', '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document $ns><w:body>$body<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>''');

    return ZipEncoder().encode(archive);
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
