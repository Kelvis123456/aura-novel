import 'dart:convert';
import 'dart:io';

import 'package:aura_novel/core/network/dynamic_openai_client.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:aura_novel/features/projects/chapter_summary_service.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/models/story_node_model.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeStorage extends SecureConfigStorage {
  @override
  Future<ApiEndpointConfig?> load() async =>
      const ApiEndpointConfig(baseUrl: 'https://api.test', apiKey: 'k', modelId: 'm');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late ProjectRepository repo;
  late List<String> prompts;
  late ChapterSummaryService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('aura_summary_test');
    repo = ProjectRepository(databasePath: p.join(tempDir.path, 'projects.db'));
    prompts = [];
    final client = DynamicOpenAIClient(
      configStorage: _FakeStorage(),
      retryDelays: const [],
      httpClient: MockClient((request) async {
        final messages = (jsonDecode(request.body) as Map<String, dynamic>)['messages'] as List<dynamic>;
        prompts.add((messages.last as Map<String, dynamic>)['content'] as String);
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '  Resumen corto.  '}}
            ]
          }),
          200,
        );
      }),
    );
    service = ChapterSummaryService(client: client, repository: repo, storage: _FakeStorage());
  });

  tearDown(() async {
    await repo.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> addChapter(String id, int order, {String text = '', String summary = ''}) async {
    await repo.saveChapter(ChapterModel(id: id, projectId: 'p', title: 'Cap $id', order: order, summary: summary));
    if (text.isNotEmpty) {
      await repo.saveNode(StoryNodeModel(id: 'n$id', chapterId: id, content: text, timestamp: DateTime(2026)));
    }
  }

  group('summarize', () {
    test('resume la última versión y guarda el resultado recortado', () async {
      await addChapter('1', 0, text: 'Mara entra en la torre.');

      final chapter = (await repo.getChaptersForProject('p')).single;
      final summary = await service.summarize(chapter);

      expect(summary, 'Resumen corto.');
      expect(prompts.single, contains('Mara entra en la torre.'));
      expect((await repo.getChaptersForProject('p')).single.summary, 'Resumen corto.');
    });

    test('un capítulo sin texto devuelve null y no llama a la API', () async {
      await addChapter('1', 0);

      final chapter = (await repo.getChaptersForProject('p')).single;

      expect(await service.summarize(chapter), isNull);
      expect(prompts, isEmpty);
    });

    test('un capítulo enorme se recorta por el medio', () async {
      final text = 'A' * 20000 + 'B' * 20000;
      await addChapter('1', 0, text: text);

      await service.summarize((await repo.getChaptersForProject('p')).single);

      expect(prompts.single.length, lessThan(ChapterSummaryService.maxInputChars + 200));
      expect(prompts.single, contains('[…]'));
    });
  });

  group('buildPriorSummariesMessage', () {
    test('solo incluye capítulos anteriores con resumen', () async {
      await addChapter('1', 0, summary: 'Uno pasó.');
      await addChapter('2', 1);
      await addChapter('3', 2, summary: 'Tres pasó.');
      await addChapter('4', 3, summary: 'Cuatro pasó.');

      final message = await service.buildPriorSummariesMessage('p', '3');

      expect(message!.content, contains('Uno pasó.'));
      expect(message.content, isNot(contains('Cap 2')));
      expect(message.content, isNot(contains('Tres pasó.')));
      expect(message.content, isNot(contains('Cuatro pasó.')));
    });

    test('el primer capítulo no tiene contexto previo', () async {
      await addChapter('1', 0, summary: 'Uno pasó.');

      expect(await service.buildPriorSummariesMessage('p', '1'), isNull);
    });

    test('si no caben todos, se caen los más antiguos', () async {
      await addChapter('1', 0, summary: 'antiguo ${'x' * 60}');
      await addChapter('2', 1, summary: 'reciente ${'y' * 60}');
      await addChapter('3', 2);

      final message = await service.buildPriorSummariesMessage('p', '3', maxChars: 100);

      expect(message!.content, contains('reciente'));
      expect(message.content, isNot(contains('antiguo')));
    });
  });
}
