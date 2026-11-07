// Runs the real writing pipeline against a live OpenAI-compatible endpoint.
// Skipped unless AURA_LIVE_KEY is set, so CI never touches the network:
//   AURA_LIVE_KEY=... AURA_LIVE_URL=http://127.0.0.1:20128/api/v1 AURA_LIVE_MODEL=ddgw/gpt-5.4-mini \
//   AURA_LIVE_OUT=out.txt flutter test test/live_model_test.dart
import 'dart:io';

import 'package:aura_novel/core/network/dynamic_openai_client.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:aura_novel/features/writer/chapter_writer.dart';
import 'package:aura_novel/features/writer/craft_library.dart';
import 'package:aura_novel/features/writer/prompt_composer.dart';
import 'package:aura_novel/features/writer/writing_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class _LiveStorage extends SecureConfigStorage {
  final ApiEndpointConfig config;
  _LiveStorage(this.config);

  @override
  Future<ApiEndpointConfig?> load() async => config;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = Platform.environment['AURA_LIVE_KEY'];

  test('escribe un capítulo de verdad con el modelo configurado', () async {
    HttpOverrides.global = null; // flutter_test blocks real HTTP by default
    final storage = _LiveStorage(ApiEndpointConfig(
      baseUrl: Platform.environment['AURA_LIVE_URL'] ?? 'http://127.0.0.1:20128/api/v1',
      apiKey: key!,
      modelId: Platform.environment['AURA_LIVE_MODEL'] ?? 'ddgw/gpt-5.4-mini',
      maxTokens: 4096,
    ));
    final client = DynamicOpenAIClient(configStorage: storage, timeout: const Duration(minutes: 3));
    final writer = ChapterWriter(client: client, storage: storage, composer: PromptComposer(CraftLibrary()));

    final out = StringBuffer();
    await for (final e in writer.write(
      instruction: 'Mara llega de noche al faro abandonado de la isla y descubre que alguien lo ha mantenido encendido. '
          'Hay una taza de té todavía tibia en la mesa.',
      targetWords: int.tryParse(Platform.environment['AURA_LIVE_WORDS'] ?? '') ?? 1800,
      profile: const WritingProfile(genre: 'terror gótico', tone: 'opresivo', register: WritingRegister.crudo, craftLevel: CraftLevel.esencial),
    )) {
      switch (e) {
        case PlanReady(:final beats):
          out.writeln('PLAN: ${beats.join(' | ')}\n');
        case SegmentStarted(:final index, :final total):
          out.writeln('[escena ${index + 1}/$total]');
        case ProseDelta(:final text):
          out.write(text);
        case WriterFinished(:final words):
          out.writeln('\n\n[palabras: $words]');
      }
    }
    final path = Platform.environment['AURA_LIVE_OUT'];
    if (path != null) File(path).writeAsStringSync(out.toString());
    expect(ChapterWriter.countWords(out.toString()), greaterThan(300));
  }, skip: key == null ? 'define AURA_LIVE_KEY para probar contra un modelo real' : false, timeout: const Timeout(Duration(minutes: 8)));
}
