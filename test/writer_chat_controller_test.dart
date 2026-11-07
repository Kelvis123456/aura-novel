import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aura_novel/core/network/dynamic_openai_client.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:aura_novel/features/lore/context_builder_service.dart';
import 'package:aura_novel/features/lore/lore_repository.dart';
import 'package:aura_novel/features/lore/models/lore_item_model.dart';
import 'package:aura_novel/features/projects/chapter_summary_service.dart';
import 'package:aura_novel/features/projects/models/project_model.dart';
import 'package:aura_novel/features/projects/project_repository.dart';
import 'package:aura_novel/features/writer/chapter_writer.dart';
import 'package:aura_novel/features/writer/craft_library.dart';
import 'package:aura_novel/features/writer/prompt_composer.dart';
import 'package:aura_novel/features/writer/writer_chat_controller.dart';
import 'package:aura_novel/features/writer/writer_service.dart';
import 'package:aura_novel/features/writer/writing_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Storage extends SecureConfigStorage {
  @override
  Future<ApiEndpointConfig?> load() async => const ApiEndpointConfig(baseUrl: 'https://api.test', apiKey: 'k', modelId: 'm');
}

String _sse(String text) => 'data: ${jsonEncode({
      'choices': [
        {'delta': {'content': text}}
      ]
    })}\n\ndata: [DONE]\n\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late ProjectRepository repo;
  late LoreRepository lore;
  late WriterChatController controller;
  late List<Map<String, dynamic>> requests;
  var failNext = false;
  Completer<void>? holdResearch;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('aura_writer_ctl');
    repo = ProjectRepository(databasePath: p.join(tempDir.path, 'projects.db'));
    lore = LoreRepository(databasePath: p.join(tempDir.path, 'lore.db'));
    requests = [];
    failNext = false;
    holdResearch = null;

    final mock = MockClient.streaming((request, bodyStream) async {
      final body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
      requests.add(body);
      if (failNext) return http.StreamedResponse(Stream.value(utf8.encode('{"error":{"message":"boom"}}')), 500);
      if (body['stream'] == true) {
        return http.StreamedResponse(Stream.value(utf8.encode(_sse('Respuesta ${requests.length}.'))), 200);
      }
      final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
      final system = messages.first['content'] as String;
      final last = messages.last['content'] as String;
      Future<http.StreamedResponse> reply(String content) async => http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'choices': [{'message': {'content': content}}]}))),
            200,
            headers: {'content-type': 'application/json'},
          );
      if (system.contains('POLISH PASS')) return reply(last.replaceAll('Respuesta', 'Escena'));
      if (system.contains('You plan research')) return reply('["Primera pregunta larga", "Segunda pregunta larga"]');
      if (system.contains('turn research answers')) return reply('NOTAS: nota sintetizada sobre la lente Fresnel.');
      if (system.contains('You are a research assistant for a fiction author. Answer factually')) return reply('Respuesta de investigación a: $last');
      if (last.startsWith('Plan a chapter')) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'choices': [{'message': {'content': '["Mara sube.", "Mara encuentra la lámpara."]'}}]}))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      await holdResearch?.future;
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'choices': [{'message': {'content': 'NOTAS: el faro usa una lente Fresnel.'}}]}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final storage = _Storage();
    final client = DynamicOpenAIClient(configStorage: storage, httpClient: mock, retryDelays: const []);
    final composer = PromptComposer(CraftLibrary());
    final summaries = ChapterSummaryService(client: client, repository: repo, storage: storage);
    final service = WriterService(client: client, storage: storage, composer: composer, lore: ContextBuilderService(repository: lore), summaries: summaries);
    controller = WriterChatController(
      repository: repo,
      lore: lore,
      service: service,
      chapterWriter: ChapterWriter(client: client, storage: storage, composer: composer),
      storage: storage,
    );

    await repo.saveProject(ProjectModel(id: 'p', title: 'El faro', createdAt: DateTime(2026), updatedAt: DateTime(2026)));
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await repo.close();
    await lore.close();
    tempDir.deleteSync(recursive: true);
  });

  test('charlar guarda la pregunta y la respuesta, y sobreviven a recargar', () async {
    await controller.send('Dame tres premisas', ChatMode.chat);

    expect(controller.entries.map((e) => e.role), ['user', 'assistant']);
    expect(controller.entries.last.content, 'Respuesta 1.');
    expect(controller.generating, isFalse);

    await controller.load();
    expect(controller.entries, hasLength(2));
  });

  test('el sistema de la petición lleva el perfil del proyecto', () async {
    await controller.saveProfile(const WritingProfile(genre: 'terror gótico', register: WritingRegister.crudo));
    await controller.send('Hola', ChatMode.chat);

    final system = ((requests.single['messages'] as List).first as Map<String, dynamic>)['content'] as String;
    expect(system, contains('Genre: terror gótico'));
    expect(system, contains('Register: raw'));
  });

  test('regenerar reemplaza la última respuesta', () async {
    await controller.send('Hola', ChatMode.chat);
    await controller.regenerate();

    expect(controller.entries, hasLength(2));
    expect(controller.entries.last.content, 'Respuesta 2.');
  });

  test('un error no deja una respuesta vacía en la conversación', () async {
    failNext = true;
    await controller.send('Hola', ChatMode.chat);

    expect(controller.error, isNotNull);
    expect(controller.entries.map((e) => e.role), ['user']);
  });

  test('escribir un capítulo largo junta las escenas en una sola respuesta', () async {
    await controller.send('Mara sube a la torre y descubre la lámpara apagada', ChatMode.chapter, words: 1800);

    expect(controller.entries.last.kind, 'chapter');
    // plan + two scene calls, joined by a blank line
    expect(RegExp('Respuesta').allMatches(controller.entries.last.content), hasLength(2));
    expect(controller.entries.last.content, contains('.\n\nRespuesta'));
    expect(controller.generating, isFalse);
  });

  test('cada turno de charla manda el mensaje una sola vez y la respuesta anterior entera', () async {
    await controller.send('Primera pregunta', ChatMode.chat);
    await controller.send('Segunda pregunta', ChatMode.chat);

    final messages = (requests.last['messages'] as List).cast<Map<String, dynamic>>();
    final users = messages.where((m) => m['role'] == 'user').map((m) => m['content']).toList();
    expect(users, ['Primera pregunta', 'Segunda pregunta']);
    expect(messages.where((m) => m['role'] == 'assistant').single['content'], 'Respuesta 1.');
  });

  test('otra vez repite un capítulo con sus palabras y una herramienta con su módulo', () async {
    await controller.send('Mara sube', ChatMode.chapter, words: 800, continueChapter: false);
    expect(controller.entries.first.meta['words'], 800);
    final before = requests.length;
    await controller.regenerate();
    expect(requests.length, greaterThan(before));
    expect(controller.entries.where((e) => e.role == 'assistant'), hasLength(1));

    await controller.clear();
    await controller.runTool('dialogue', 'Hola, dijo ella.');
    await controller.regenerate();
    final system = ((requests.last['messages'] as List).first as Map<String, dynamic>)['content'] as String;
    expect(system, contains('TOOL: Diálogo'));
    expect(controller.entries.where((e) => e.kind == 'tool' && e.role == 'user'), hasLength(1));
  });

  test('parar una investigación y empezar otra petición no mezcla los estados', () async {
    holdResearch = Completer<void>();
    final research = controller.send('Lentes Fresnel', ChatMode.research, deepResearch: false);
    // The turn is saved to SQLite before it starts, which is slow on a busy CI runner.
    for (var i = 0; i < 100 && !controller.generating; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(controller.generating, isTrue);

    controller.stop();
    expect(controller.generating, isFalse);

    final chat = controller.send('Hola otra vez', ChatMode.chat);
    holdResearch!.complete();
    await research;
    await chat;

    expect(controller.generating, isFalse);
    expect(controller.entries.where((e) => e.kind == 'research' && e.role == 'assistant'), isEmpty);
    expect(controller.entries.last.content, startsWith('Respuesta'));
  });

  test('investigar guarda la nota y se convierte en ficha de Mundo del proyecto', () async {
    await controller.send('Cómo funciona una lente Fresnel', ChatMode.research, deepResearch: false);
    final note = controller.entries.last;
    expect(note.kind, 'research');
    expect(note.content, contains('Fresnel'));

    await controller.saveResearch(note);

    final items = await lore.getAllLoreItems();
    expect(items.single.category, LoreCategory.research);
    expect(items.single.projectId, 'p');
    expect(items.single.longDetails, contains('lente Fresnel'));
  });

  test('añadir al capítulo crea el capítulo y una versión; la siguiente se acumula', () async {
    await controller.send('Escena uno', ChatMode.chat);
    final answer = controller.entries.last;

    final chapter = await controller.insert(answer, newChapterTitle: 'Uno');
    expect((await repo.getLatestNodeForChapter(chapter.id))!.content, 'Respuesta 1.');

    await controller.insert(answer);
    expect((await repo.getLatestNodeForChapter(chapter.id))!.content, 'Respuesta 1.\n\nRespuesta 1.');
  });

  test('sin título no se puede crear un capítulo al insertar', () async {
    await controller.send('x', ChatMode.chat);
    expect(() => controller.insert(controller.entries.last), throwsStateError);
  });

  test('borrar la conversación solo borra la del proyecto actual', () async {
    await controller.send('uno', ChatMode.chat);
    await controller.selectProject(null);
    await controller.send('sin proyecto', ChatMode.chat);

    await controller.clear();
    expect(controller.entries, isEmpty);
    await controller.selectProject('p');
    expect(controller.entries, hasLength(2));
  });

  test('la investigación profunda planea, responde cada pregunta y sintetiza', () async {
    await controller.send('Cómo funciona una lente Fresnel', ChatMode.research);

    // plan + 2 respuestas + síntesis
    expect(requests, hasLength(4));
    expect(controller.entries.last.content, startsWith('NOTAS: nota sintetizada'));
    final synth = ((requests.last['messages'] as List).last as Map<String, dynamic>)['content'] as String;
    expect(synth, contains('Respuesta de investigación a:'));
    expect(synth, contains('Primera pregunta larga'));
  });

  test('pulir al terminar reescribe cada escena y conserva el resto', () async {
    await controller.saveProfile(const WritingProfile(polishAfter: true));

    await controller.send('Mara sube a la torre', ChatMode.chapter, words: 1800);

    // plan + 2 escenas + 2 pulidos
    expect(requests, hasLength(5));
    final text = controller.entries.last.content;
    expect(text, isNot(contains('Respuesta')));
    expect(RegExp('Escena').allMatches(text), hasLength(2));
    expect(text, contains('\n\n'));
    expect(controller.generating, isFalse);
  });

  test('sin pulir al terminar no hay llamadas de pulido', () async {
    await controller.send('Mara sube a la torre', ChatMode.chapter, words: 1800);

    expect(requests, hasLength(3));
    expect(controller.entries.last.content, contains('Respuesta'));
  });
}
