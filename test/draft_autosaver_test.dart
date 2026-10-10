import 'dart:io';

import 'package:aura_novel/features/editor/draft_autosaver.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const short = Duration(milliseconds: 20);
  late Directory tempDir;
  late ProjectRepository repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('aura_draft_test');
    repo = ProjectRepository(databasePath: p.join(tempDir.path, 'projects.db'));
  });

  tearDown(() async {
    await repo.close();
    tempDir.deleteSync(recursive: true);
  });

  DraftAutosaver autosaver({String saved = 'base', String nodeId = 'n1'}) => DraftAutosaver(
        repository: repo,
        chapterId: 'c1',
        nodeId: nodeId,
        savedContent: saved,
        delay: short,
      );

  test('guarda el borrador tras la pausa de escritura', () async {
    final a = autosaver();
    a.onTextChanged('base y más');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect((await repo.getDraft('c1'))!.content, 'base y más');
    a.dispose();
  });

  test('escribir seguido reinicia el temporizador y guarda solo lo último', () async {
    final a = autosaver();
    a.onTextChanged('uno');
    a.onTextChanged('uno dos');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect((await repo.getDraft('c1'))!.content, 'uno dos');
    a.dispose();
  });

  test('volver al texto guardado borra el borrador', () async {
    final a = autosaver();
    a.onTextChanged('cambio');
    await a.flush();
    expect(await repo.getDraft('c1'), isNotNull);

    a.onTextChanged('base');
    await a.flush();

    expect(await repo.getDraft('c1'), isNull);
    a.dispose();
  });

  test('recover devuelve el borrador del mismo nodo', () async {
    final first = autosaver();
    first.onTextChanged('sin guardar');
    await first.flush();
    first.dispose();

    expect(await autosaver().recover(), 'sin guardar');
  });

  test('recover descarta un borrador de otro nodo', () async {
    final first = autosaver(nodeId: 'otro');
    first.onTextChanged('de otra versión');
    await first.flush();
    first.dispose();

    expect(await autosaver().recover(), isNull);
    expect(await repo.getDraft('c1'), isNull);
  });

  test('markSaved borra el borrador y fija la nueva base', () async {
    final a = autosaver();
    a.onTextChanged('v2');
    await a.flush();

    await a.markSaved(nodeId: 'n2', content: 'v2');
    expect(await repo.getDraft('c1'), isNull);

    a.onTextChanged('v2');
    await a.flush();
    expect(await repo.getDraft('c1'), isNull);
    a.dispose();
  });

  test('eliminar el capítulo elimina su borrador', () async {
    final a = autosaver();
    a.onTextChanged('algo');
    await a.flush();

    await repo.deleteChapterCascade('c1');

    expect(await repo.getDraft('c1'), isNull);
    a.dispose();
  });
}
