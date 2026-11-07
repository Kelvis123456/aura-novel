import 'dart:convert';

import 'package:aura_novel/core/network/dynamic_openai_client.dart';
import 'package:aura_novel/core/network/exceptions/api_exceptions.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:aura_novel/features/writer/chapter_writer.dart';
import 'package:aura_novel/features/writer/craft_library.dart';
import 'package:aura_novel/features/writer/prompt_composer.dart';
import 'package:aura_novel/features/writer/writing_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Storage extends SecureConfigStorage {
  final ApiEndpointConfig? config;
  _Storage([this.config = const ApiEndpointConfig(baseUrl: 'https://api.test', apiKey: 'k', modelId: 'm')]);

  @override
  Future<ApiEndpointConfig?> load() async => config;
}

String _sse(String text) => 'data: ${jsonEncode({
      'choices': [
        {'delta': {'content': text}}
      ]
    })}\n\ndata: [DONE]\n\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CraftLibrary', () {
    test('cada módulo existe como asset y tiene sus reglas', () async {
      final lib = CraftLibrary();
      for (final m in CraftLibrary.modules) {
        expect((await lib.rules(m.id)).length, greaterThan(300), reason: m.id);
        expect(await lib.full(m.id), contains('## How to apply'), reason: m.id);
      }
    });

    test('extractSection devuelve solo la sección pedida', () {
      const md = '# x\n## A\nuno\n## Core rules\n- r1\n- r2\n## Diagnose\ndos';
      expect(CraftLibrary.extractSection(md, 'Core rules'), '- r1\n- r2');
      expect(CraftLibrary.extractSection(md, 'Nada'), '');
    });
  });

  group('PromptComposer', () {
    final composer = PromptComposer(CraftLibrary());

    test('el prompt de prosa lleva persona, perfil y las reglas de oficio', () async {
      final text = (await composer.proseSystem(const WritingProfile(genre: 'terror', register: WritingRegister.crudo))).content;
      expect(text, contains('writing engine of Aura Novel'));
      expect(text, contains('Genre: terror'));
      expect(text, contains('Register: raw'));
      expect(text, contains('[Pulir prosa]'));
      expect(text, contains('[Quitar tics de IA]'));
    });

    test('el nivel esencial es mucho más corto', () async {
      final full = (await composer.proseSystem(const WritingProfile())).content;
      final lite = (await composer.proseSystem(const WritingProfile(craftLevel: CraftLevel.esencial))).content;
      expect(lite.length, lessThan(full.length ~/ 2));
      expect(lite, contains('CRAFT ESSENTIALS'));
    });

    test('la forma larga añade las reglas de novela larga', () async {
      final text = (await composer.proseSystem(const WritingProfile(), longForm: true)).content;
      expect(text, contains('[Novela larga]'));
    });

    test('el prompt de herramienta incluye el módulo completo y el idioma', () async {
      final text = (await composer.toolSystem('dialogue', const WritingProfile(language: 'en'))).content;
      expect(text, contains('TOOL: Diálogo'));
      expect(text, contains('Answer in English'));
      expect(text, contains('## Diagnose'));
    });

    test('la persona fija los límites y no moraliza', () async {
      final text = await CraftLibrary().persona();
      expect(text, contains('under 18'));
      expect(text, contains('Do not add disclaimers'));
    });
  });

  group('ChapterWriter', () {
    test('parsePlan lee un arreglo JSON, con vallas de código y con listas', () {
      expect(ChapterWriter.parsePlan('["a uno", "b dos"]'), ['a uno', 'b dos']);
      expect(ChapterWriter.parsePlan('```json\n["x una", "y dos"]\n```'), ['x una', 'y dos']);
      expect(ChapterWriter.parsePlan('1. Primera escena\n2) Segunda escena\n- Tercera escena'), ['Primera escena', 'Segunda escena', 'Tercera escena']);
      expect(ChapterWriter.parsePlan(''), isEmpty);
    });

    test('parsePlan ignora la frase de introducción, las vallas y las comas sueltas', () {
      final plan = ChapterWriter.parsePlan('Aquí tienes el plan:\n1. Primera escena\n2. Segunda escena');
      expect(plan, ['Primera escena', 'Segunda escena']);
      expect(ChapterWriter.parsePlan('```json\n"Una escena larga",\n"Otra escena larga"\n```'), ['Una escena larga', 'Otra escena larga']);
    });

    test('sceneCount reparte las palabras y respeta el tope', () {
      expect(ChapterWriter.sceneCount(500), 1);
      expect(ChapterWriter.sceneCount(1800), 2);
      expect(ChapterWriter.sceneCount(3000), 4);
      expect(ChapterWriter.sceneCount(100000), ChapterWriter.maxScenes);
    });

    test('un capítulo largo hace un plan y una llamada por escena, con el texto previo como contexto', () async {
      final prompts = <String>[];
      var call = 0;
      final mock = MockClient.streaming((request, bodyStream) async {
        final body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        prompts.add((messages.last as Map<String, dynamic>)['content'] as String);
        if (body['stream'] == true) {
          call++;
          return http.StreamedResponse(Stream.value(utf8.encode(_sse('Escena $call. '))), 200);
        }
        const plan = '["Mara llega a la torre.", "Descubre la puerta."]';
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'choices': [{'message': {'content': plan}}]}))),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = DynamicOpenAIClient(configStorage: _Storage(), httpClient: mock, retryDelays: const []);
      final writer = ChapterWriter(client: client, storage: _Storage(), composer: PromptComposer(CraftLibrary()));

      final events = await writer.write(instruction: 'Mara sube a la torre', targetWords: 1800, profile: const WritingProfile()).toList();

      expect(events.whereType<PlanReady>().single.beats, hasLength(2));
      final prose = events.whereType<ProseDelta>().map((e) => e.text).join();
      expect(prose, 'Escena 1. \n\nEscena 2. ');
      expect(events.last, isA<WriterFinished>());
      // plan + 2 scene calls
      expect(prompts, hasLength(3));
      expect(prompts[2], contains('TEXT SO FAR'));
      expect(prompts[2], contains('Escena 1.'));
      expect(prompts[1], isNot(contains('TEXT SO FAR')));
      expect(prompts[2], contains('final part'));
      expect(prompts[1], contains('do not conclude'));
    });

    test('sin configuración lanza MissingConfigException', () async {
      final client = DynamicOpenAIClient(configStorage: _Storage(null), httpClient: MockClient((_) async => http.Response('', 500)), retryDelays: const []);
      final writer = ChapterWriter(client: client, storage: _Storage(null), composer: PromptComposer(CraftLibrary()));

      expect(
        writer.write(instruction: 'x', targetWords: 500, profile: const WritingProfile()).toList(),
        throwsA(isA<MissingConfigException>()),
      );
    });
  });

  group('WritingProfile', () {
    test('ida y vuelta por JSON y valores por defecto ante datos rotos', () {
      const p = WritingProfile(language: 'en', genre: 'noir', pov: Pov.primera, presentTense: true, register: WritingRegister.sucio, craftLevel: CraftLevel.esencial);
      final back = WritingProfile.fromJsonString(p.toJsonString());
      expect(back.language, 'en');
      expect(back.pov, Pov.primera);
      expect(back.presentTense, isTrue);
      expect(back.register, WritingRegister.sucio);
      expect(back.craftLevel, CraftLevel.esencial);
      expect(WritingProfile.fromJsonString('{no json').language, 'es');
      expect(WritingProfile.fromJsonString('').register, WritingRegister.natural);
      expect(WritingProfile.fromJsonString('{"language":"xx","pov":"raro"}').pov, Pov.terceraLimitada);
    });
  });

  group('módulos de oficio completos', () {
    test('removeSection quita solo la sección pedida', () {
      const md = '# x\n## A\nuno\n## Deep notes\ndos\n## Otra\ntres';
      expect(CraftLibrary.removeSection(md, 'Deep notes'), '# x\n## A\nuno\n## Otra\ntres');
    });

    test('los módulos largos traen notas profundas y se pueden quitar', () async {
      final lib = CraftLibrary();
      for (final id in ['prose-style', 'long-form-hooks', 'book-marketing', 'summarization', 'research-workflow']) {
        final full = await lib.full(id);
        expect(full, contains('## Deep notes'), reason: id);
        expect(await lib.full(id, deep: false), isNot(contains('## Deep notes')), reason: id);
      }
    });

    test('el prompt de herramienta lleva las notas profundas salvo con un modelo pequeño', () async {
      final big = await PromptComposer(CraftLibrary()).toolSystem('revision', const WritingProfile());
      final small = await PromptComposer(CraftLibrary(), preferShort: () async => true).toolSystem('revision', const WritingProfile());
      expect(big.content, contains('## Deep notes'));
      expect(small.content, isNot(contains('## Deep notes')));
      expect(small.content.length, lessThan(big.content.length));
    });

    test('el prompt de pulido lleva la orden de conservar los hechos y las reglas de oficio', () async {
      final text = (await PromptComposer(CraftLibrary()).polishSystem(const WritingProfile())).content;
      expect(text, contains('POLISH PASS'));
      expect(text, contains('Keep every event'));
      expect(text, contains('[Quitar tics de IA]'));
    });

    test('hay módulos de publicar, investigar y resumir en el registro', () {
      expect(CraftLibrary.byId('book-marketing')!.group, CraftGroup.publicar);
      expect(CraftLibrary.byId('research-workflow'), isNotNull);
      expect(CraftLibrary.byId('summarization'), isNotNull);
      expect(CraftLibrary.coreIds, contains('long-form-style'));
    });

    test('el perfil guarda pulir al terminar', () {
      final back = WritingProfile.fromJsonString(const WritingProfile(polishAfter: true).toJsonString());
      expect(back.polishAfter, isTrue);
      expect(const WritingProfile().polishAfter, isFalse);
    });
  });

  group('voz del autor', () {
    test('una muestra entra en el prompt y se recorta', () {
      final block = WritingProfile(voiceSample: 'x' * 20000).toPromptBlock();
      expect(block, contains('AUTHOR VOICE SAMPLE'));
      expect(block.length, lessThan(WritingProfile.maxVoiceChars + 600));
    });

    test('sin muestra no hay bloque y el JSON la conserva', () {
      expect(const WritingProfile().toPromptBlock(), isNot(contains('VOICE SAMPLE')));
      final back = WritingProfile.fromJsonString(const WritingProfile(voiceSample: 'Llovía sin ganas.').toJsonString());
      expect(back.voiceSample, 'Llovía sin ganas.');
    });
  });
}

