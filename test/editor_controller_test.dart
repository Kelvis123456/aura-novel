import 'dart:async';

import 'package:aura_novel/core/network/dynamic_openai_client.dart';
import 'package:aura_novel/core/network/exceptions/api_exceptions.dart';
import 'package:aura_novel/core/network/models/chat_completion_request.dart';
import 'package:aura_novel/core/network/models/chat_completion_response.dart';
import 'package:aura_novel/core/network/models/chat_message.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:aura_novel/features/editor/editor_controller.dart';
import 'package:aura_novel/features/lore/context_builder_service.dart';
import 'package:aura_novel/features/lore/lore_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends SecureConfigStorage {
  final int contextChars;
  _FakeStorage({this.contextChars = ApiEndpointConfig.defaultContextChars});

  @override
  Future<ApiEndpointConfig?> load() async => ApiEndpointConfig(
        baseUrl: 'https://api.test',
        apiKey: 'k',
        modelId: 'm',
        contextChars: contextChars,
      );
}

/// Records the budget the editor asks the lore builder for.
class _RecordingContextBuilder extends ContextBuilderService {
  int? requestedMaxChars;
  _RecordingContextBuilder() : super(repository: LoreRepository());

  @override
  Future<ChatMessage?> buildContextMessage(
    String fullText, {
    int scanWindowWords = 400,
    int maxChars = ContextBuilderService.defaultMaxContextChars,
  }) async {
    requestedMaxChars = maxChars;
    return null;
  }
}

class _FakeClient extends DynamicOpenAIClient {
  final Stream<ChatCompletionChunk> Function() source;
  final void Function(ChatCompletionRequest request)? onRequest;
  _FakeClient(this.source, {this.onRequest});

  @override
  Stream<ChatCompletionChunk> stream(ChatCompletionRequest request) {
    onRequest?.call(request);
    return source();
  }
}

ChatCompletionChunk _chunk(String text) => ChatCompletionChunk(deltaContent: text);

EditorController _controllerWith(Stream<ChatCompletionChunk> Function() source) =>
    EditorController(client: _FakeClient(source), storage: _FakeStorage());

/// Lets the stream listener run its pending events.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('continuar agrega el texto del stream al final del documento', () async {
    final controller = _controllerWith(() => Stream.fromIterable([_chunk('Hola'), _chunk(' mundo')]));
    controller.textController.text = 'Inicio. ';

    await controller.continueStory();
    await _settle();

    expect(controller.textController.text, 'Inicio. Hola mundo');
    expect(controller.status, GenerationStatus.idle);
    controller.dispose();
  });

  test('si el stream falla a la mitad, conserva lo recibido y lo dice', () async {
    final controller = _controllerWith(() async* {
      yield _chunk('Mitad');
      throw const NetworkUnavailableException();
    });

    await controller.continueStory();
    await _settle();

    expect(controller.textController.text, 'Mitad');
    expect(controller.status, GenerationStatus.error);
    expect(controller.errorMessage, contains('Se conservó el texto'));
    controller.dispose();
  });

  test('un error antes de recibir nada no menciona texto conservado', () async {
    final controller = _controllerWith(() => Stream.error(const RequestTimeoutException()));

    await controller.continueStory();
    await _settle();

    expect(controller.errorMessage, isNot(contains('conservó')));
    controller.dispose();
  });

  test('reescribir reemplaza solo la selección', () async {
    final controller = _controllerWith(() => Stream.fromIterable([_chunk('nueva')]));
    controller.textController.value = const TextEditingValue(
      text: 'antes vieja después',
      selection: TextSelection(baseOffset: 6, extentOffset: 11),
    );

    await controller.rewriteSelection();
    await _settle();

    expect(controller.textController.text, 'antes nueva después');
    controller.dispose();
  });

  test('suma tokens estimados de la sesión', () async {
    final controller = _controllerWith(() => Stream.fromIterable([_chunk('x' * 400)]));

    await controller.continueStory();
    await _settle();

    expect(controller.estimatedSessionTokens, greaterThanOrEqualTo(100));
    controller.dispose();
  });

  group('sugerencia pendiente', () {
    test('tras generar queda pendiente y aceptar la limpia sin tocar el texto', () async {
      final controller = _controllerWith(() => Stream.fromIterable([_chunk('IA')]));
      controller.textController.text = 'Hola ';

      await controller.continueStory();
      await _settle();
      expect(controller.pendingSuggestion?.text, 'IA');

      controller.acceptSuggestion();
      expect(controller.pendingSuggestion, isNull);
      expect(controller.textController.text, 'Hola IA');
      controller.dispose();
    });

    test('descartar una continuación quita lo agregado', () async {
      final controller = _controllerWith(() => Stream.fromIterable([_chunk('IA')]));
      controller.textController.text = 'Hola ';

      await controller.continueStory();
      await _settle();
      controller.discardSuggestion();

      expect(controller.textController.text, 'Hola ');
      controller.dispose();
    });

    test('descartar una reescritura devuelve el texto original', () async {
      final controller = _controllerWith(() => Stream.fromIterable([_chunk('nueva')]));
      controller.textController.value = const TextEditingValue(
        text: 'antes vieja después',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );

      await controller.rewriteSelection();
      await _settle();
      controller.discardSuggestion();

      expect(controller.textController.text, 'antes vieja después');
      controller.dispose();
    });

    test('si el autor editó el texto generado, descartar no toca nada', () async {
      final controller = _controllerWith(() => Stream.fromIterable([_chunk('IA')]));
      controller.textController.text = 'Hola ';

      await controller.continueStory();
      await _settle();
      controller.textController.text = 'Hola XY editado a mano';
      controller.discardSuggestion();

      expect(controller.textController.text, 'Hola XY editado a mano');
      expect(controller.pendingSuggestion, isNull);
      controller.dispose();
    });

    test('un stream cortado con texto parcial también queda por revisar', () async {
      final controller = _controllerWith(() async* {
        yield _chunk('Mitad');
        throw const NetworkUnavailableException();
      });

      await controller.continueStory();
      await _settle();

      expect(controller.pendingSuggestion?.text, 'Mitad');
      controller.dispose();
    });
  });

  group('meta de palabras', () {
    test('cuenta solo lo escrito desde startSession', () {
      final controller = _controllerWith(() => const Stream.empty());
      controller.textController.text = 'uno dos tres';
      controller.startSession();
      controller.textController.text = 'uno dos tres cuatro cinco';

      expect(controller.wordsWrittenThisSession, 2);
      controller.dispose();
    });

    test('borrar texto no da un conteo negativo', () {
      final controller = _controllerWith(() => const Stream.empty());
      controller.textController.text = 'uno dos tres';
      controller.startSession();
      controller.textController.text = 'uno';

      expect(controller.wordsWrittenThisSession, 0);
      controller.dispose();
    });

    test('una meta de 0 o negativa la quita', () {
      final controller = _controllerWith(() => const Stream.empty());
      controller.setWordGoal(500);
      expect(controller.wordGoal, 500);
      controller.setWordGoal(0);
      expect(controller.wordGoal, isNull);
      controller.dispose();
    });
  });

  group('tope de contexto configurable', () {
    test('el lore y los resúmenes reciben el tope de la configuración', () async {
      final builder = _RecordingContextBuilder();
      int? storyMaxChars;
      final controller = EditorController(
        client: _FakeClient(() => Stream.fromIterable([_chunk('x')])),
        storage: _FakeStorage(contextChars: 12000),
        contextBuilder: builder,
        storyContext: (maxChars) async {
          storyMaxChars = maxChars;
          return null;
        },
      );

      await controller.continueStory();
      await _settle();

      expect(builder.requestedMaxChars, 12000);
      expect(storyMaxChars, 12000);
      controller.dispose();
    });

    test('los mensajes de contexto van antes de la instrucción del usuario', () async {
      ChatCompletionRequest? sent;
      final controller = EditorController(
        client: _FakeClient(() => const Stream.empty(), onRequest: (r) => sent = r),
        storage: _FakeStorage(),
        storyContext: (_) async => ChatMessage.system('[RESUMEN]'),
      );

      await controller.continueStory();

      final roles = sent!.messages.map((m) => m.role).toList();
      expect(sent!.messages.map((m) => m.content), contains('[RESUMEN]'));
      expect(roles.last, ChatRole.user);
      controller.dispose();
    });
  });
}
