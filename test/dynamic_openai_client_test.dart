import 'dart:convert';

import 'package:aura_novel/core/network/dynamic_openai_client.dart';
import 'package:aura_novel/core/network/exceptions/api_exceptions.dart';
import 'package:aura_novel/core/network/models/chat_completion_request.dart';
import 'package:aura_novel/core/network/models/chat_message.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeConfigStorage extends SecureConfigStorage {
  final ApiEndpointConfig? config;
  _FakeConfigStorage(this.config);

  @override
  Future<ApiEndpointConfig?> load() async => config;
}

const _config = ApiEndpointConfig(baseUrl: 'https://api.test/v1/', apiKey: 'sk-test', modelId: 'm');

final _request = ChatCompletionRequest(model: 'm', messages: [ChatMessage.user('hola')]);

String _sse(List<String> lines) => lines.map((l) => 'data: $l\n\n').join();

String _delta(String text) => jsonEncode({
      'choices': [
        {'delta': {'content': text}}
      ]
    });

DynamicOpenAIClient _clientFor(
  http.Client http, {
  ApiEndpointConfig? config = _config,
  List<Duration> retryDelays = const [],
}) =>
    DynamicOpenAIClient(configStorage: _FakeConfigStorage(config), httpClient: http, retryDelays: retryDelays);

http.Client _streaming(int status, String body) => MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
    });

void main() {
  group('stream', () {
    test('emite cada delta y termina en [DONE]', () async {
      final client = _clientFor(_streaming(200, _sse([_delta('Hola'), _delta(' mundo'), '[DONE]'])));
      final chunks = await client.stream(_request).toList();

      expect(chunks.where((c) => !c.isDone).map((c) => c.deltaContent).join(), 'Hola mundo');
      expect(chunks.last.isDone, isTrue);
    });

    test('ignora líneas de comentario y JSON roto sin cortar el stream', () async {
      final body = ': keep-alive\n\ndata: {roto\n\n${_sse([_delta('ok'), '[DONE]'])}';
      final chunks = await _clientFor(_streaming(200, body)).stream(_request).toList();

      expect(chunks.where((c) => !c.isDone).map((c) => c.deltaContent).join(), 'ok');
    });

    test('normaliza la barra final de la URL base', () async {
      Uri? called;
      final mock = MockClient.streaming((request, _) async {
        called = request.url;
        return http.StreamedResponse(Stream.value(utf8.encode(_sse(['[DONE]']))), 200);
      });
      await _clientFor(mock).stream(_request).toList();

      expect(called.toString(), 'https://api.test/v1/chat/completions');
    });

    test('manda la key como Bearer y pide stream: true', () async {
      http.BaseRequest? sent;
      Map<String, dynamic>? payload;
      final mock = MockClient.streaming((request, bodyStream) async {
        sent = request;
        payload = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
        return http.StreamedResponse(Stream.value(utf8.encode(_sse(['[DONE]']))), 200);
      });
      await _clientFor(mock).stream(_request).toList();

      expect(sent!.headers['Authorization'], 'Bearer sk-test');
      expect(payload!['stream'], isTrue);
    });

    test('401 lanza UnauthorizedException con el mensaje del servidor', () async {
      final body = jsonEncode({'error': {'message': 'key inválida'}});
      final client = _clientFor(_streaming(401, body));

      expect(
        client.stream(_request).toList(),
        throwsA(isA<UnauthorizedException>().having((e) => e.message, 'message', contains('key inválida'))),
      );
    });

    test('500 lanza ServerErrorException con el código', () async {
      final client = _clientFor(_streaming(500, 'boom'));

      expect(
        client.stream(_request).toList(),
        throwsA(isA<ServerErrorException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('sin configuración lanza MissingConfigException', () async {
      final client = _clientFor(_streaming(200, ''), config: null);

      expect(client.stream(_request).toList(), throwsA(isA<MissingConfigException>()));
    });
  });

  group('send', () {
    test('parsea contenido y uso de tokens', () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode({
              'id': 'x',
              'model': 'm',
              'choices': [
                {'message': {'content': 'respuesta'}, 'finish_reason': 'stop'}
              ],
              'usage': {'prompt_tokens': 12, 'completion_tokens': 3},
            }),
            200,
          ));
      final response = await _clientFor(mock).send(_request);

      expect(response.content, 'respuesta');
      expect(response.promptTokens, 12);
      expect(response.completionTokens, 3);
    });

    test('un cuerpo que no es JSON lanza MalformedResponseException', () async {
      final mock = MockClient((_) async => http.Response('no es json', 200));

      expect(_clientFor(mock).send(_request), throwsA(isA<MalformedResponseException>()));
    });
  });

  group('reintentos', () {
    const twoRetries = [Duration.zero, Duration.zero];

    /// Answers with [statuses] in order, then repeats the last one.
    http.Client sequence(List<int> statuses, {Map<String, String> headers = const {}, void Function()? onCall}) {
      var calls = 0;
      return MockClient.streaming((request, _) async {
        onCall?.call();
        final status = statuses[calls < statuses.length ? calls : statuses.length - 1];
        calls++;
        final body = status == 200 ? _sse([_delta('ok'), '[DONE]']) : 'error';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), status, headers: headers);
      });
    }

    test('reintenta un 503 y termina bien', () async {
      var calls = 0;
      final client = _clientFor(sequence([503, 200], onCall: () => calls++), retryDelays: twoRetries);
      final chunks = await client.stream(_request).toList();

      expect(calls, 2);
      expect(chunks.first.deltaContent, 'ok');
    });

    test('reintenta un 429', () async {
      var calls = 0;
      await _clientFor(sequence([429, 429, 200], onCall: () => calls++), retryDelays: twoRetries)
          .stream(_request)
          .toList();

      expect(calls, 3);
    });

    test('agota los reintentos y lanza el último error', () async {
      var calls = 0;
      final client = _clientFor(sequence([503], onCall: () => calls++), retryDelays: twoRetries);

      await expectLater(
        client.stream(_request).toList(),
        throwsA(isA<ServerErrorException>().having((e) => e.statusCode, 'statusCode', 503)),
      );
      expect(calls, 3);
    });

    test('un 401 no se reintenta', () async {
      var calls = 0;
      final client = _clientFor(sequence([401], onCall: () => calls++), retryDelays: twoRetries);

      await expectLater(client.stream(_request).toList(), throwsA(isA<UnauthorizedException>()));
      expect(calls, 1);
    });

    test('un error de red se reintenta', () async {
      var calls = 0;
      final mock = MockClient.streaming((request, _) async {
        calls++;
        if (calls == 1) throw http.ClientException('sin conexión');
        return http.StreamedResponse(Stream.value(utf8.encode(_sse(['[DONE]']))), 200);
      });
      await _clientFor(mock, retryDelays: twoRetries).stream(_request).toList();

      expect(calls, 2);
    });

    test('send también reintenta', () async {
      var calls = 0;
      final mock = MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('x', 502);
        return http.Response(jsonEncode({'choices': [{'message': {'content': 'hola'}}]}), 200);
      });
      final response = await _clientFor(mock, retryDelays: twoRetries).send(_request);

      expect(calls, 2);
      expect(response.content, 'hola');
    });

    test('respeta Retry-After del servidor en lugar del backoff', () async {
      final started = DateTime.now();
      final client = _clientFor(
        sequence([429, 200], headers: {'retry-after': '1'}),
        retryDelays: const [Duration(seconds: 30)],
      );
      await client.stream(_request).toList();

      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 5)));
    });
  });
}
