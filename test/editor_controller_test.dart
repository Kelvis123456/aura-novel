import 'dart:async';

import 'package:aura_novel/core/network/dynamic_openai_client.dart';
import 'package:aura_novel/core/network/exceptions/api_exceptions.dart';
import 'package:aura_novel/core/network/models/chat_completion_request.dart';
import 'package:aura_novel/core/network/models/chat_completion_response.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:aura_novel/features/editor/editor_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends SecureConfigStorage {
  @override
  Future<ApiEndpointConfig?> load() async =>
      const ApiEndpointConfig(baseUrl: 'https://api.test', apiKey: 'k', modelId: 'm');
}

class _FakeClient extends DynamicOpenAIClient {
  final Stream<ChatCompletionChunk> Function() source;
  _FakeClient(this.source);

  @override
  Stream<ChatCompletionChunk> stream(ChatCompletionRequest request) => source();
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
}
