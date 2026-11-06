import 'dart:convert';
import 'dart:io';

import 'package:aura_novel/core/network/dynamic_openai_client.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:aura_novel/features/lore/context_builder_service.dart';
import 'package:aura_novel/features/lore/lore_repository.dart';
import 'package:aura_novel/features/projects/chapter_summary_service.dart';
import 'package:aura_novel/features/projects/consistency_service.dart';
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

  group('parseIssues', () {
    test('marcador de sin contradicciones da lista vacía', () {
      expect(ConsistencyService.parseIssues('SIN_CONTRADICCIONES'), isEmpty);
      expect(ConsistencyService.parseIssues('  '), isEmpty);
    });

    test('extrae viñetas con - y *', () {
      expect(ConsistencyService.parseIssues('- Mara tiene 30\n* Torre al norte\ntexto suelto'),
          ['Mara tiene 30', 'Torre al norte']);
    });

    test('si no hay viñetas conserva la respuesta entera', () {
      expect(ConsistencyService.parseIssues('Mara cambió de edad.'), ['Mara cambió de edad.']);
    });
  });

  group('check', () {
    late Directory tempDir;
    late ProjectRepository repo;
    late LoreRepository lore;
    late List<Map<String, dynamic>> sent;
    late ConsistencyService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('aura_consistency_test');
      repo = ProjectRepository(databasePath: p.join(tempDir.path, 'projects.db'));
      lore = LoreRepository(databasePath: p.join(tempDir.path, 'lore.db'));
      sent = [];
      final client = DynamicOpenAIClient(
        configStorage: _FakeStorage(),
        retryDelays: const [],
        httpClient: MockClient((request) async {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'choices': [
                {'message': {'content': '- Mara tiene 30 años pero su ficha dice 25'}}
              ]
            }),
            200,
          );
        }),
      );
      service = ConsistencyService(
        client: client,
        repository: repo,
        contextBuilder: ContextBuilderService(repository: lore),
        summaries: ChapterSummaryService(client: client, repository: repo, storage: _FakeStorage()),
        storage: _FakeStorage(),
      );
    });

    tearDown(() async {
      await repo.close();
      await lore.close();
      tempDir.deleteSync(recursive: true);
    });

    test('capítulo sin texto devuelve null y no llama a la API', () async {
      await repo.saveChapter(const ChapterModel(id: 'c', projectId: 'p', title: 'Uno', order: 0));
      final chapter = (await repo.getChaptersForProject('p')).single;
      expect(await service.check(chapter), isNull);
      expect(sent, isEmpty);
    });

    test('manda el capítulo y devuelve las contradicciones', () async {
      await repo.saveChapter(const ChapterModel(id: 'c', projectId: 'p', title: 'Uno', order: 0));
      await repo.saveNode(StoryNodeModel(id: 'n', chapterId: 'c', content: 'Mara, de 30 años, entró.', timestamp: DateTime(2026)));
      final chapter = (await repo.getChaptersForProject('p')).single;

      final issues = await service.check(chapter);

      expect(issues, ['Mara tiene 30 años pero su ficha dice 25']);
      final messages = sent.single['messages'] as List<dynamic>;
      expect((messages.last as Map<String, dynamic>)['content'], contains('Mara, de 30 años'));
    });
  });
}
