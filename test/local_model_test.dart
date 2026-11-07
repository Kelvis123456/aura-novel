import 'dart:io';

import 'package:aura_novel/core/network/llm_client.dart';
import 'package:aura_novel/core/network/models/chat_completion_request.dart';
import 'package:aura_novel/core/network/models/chat_completion_response.dart';
import 'package:aura_novel/core/network/models/chat_message.dart';
import 'package:aura_novel/core/network/routing_llm_client.dart';
import 'package:aura_novel/core/storage/secure_config_storage.dart';
import 'package:aura_novel/features/local_model/local_model_catalog.dart';
import 'package:aura_novel/features/local_model/local_model_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _model = LocalModelInfo(
  id: 't',
  name: 'T',
  description: '',
  url: 'https://huggingface.co/x/y/resolve/main/m.gguf',
  fileName: 'm.gguf',
  sizeBytes: 1000,
  ramGb: 1,
);

List<int> _bytes(int n) => List<int>.generate(n, (i) => i % 251);

class _FakeClient implements LlmClient {
  final String label;
  int calls = 0;
  _FakeClient(this.label);

  @override
  Future<ChatCompletionResponse> send(ChatCompletionRequest request) async {
    calls++;
    return ChatCompletionResponse(id: label, model: label, content: label);
  }

  @override
  Stream<ChatCompletionChunk> stream(ChatCompletionRequest request) async* {
    calls++;
    yield ChatCompletionChunk(deltaContent: label);
  }

  @override
  void dispose() {}
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('aura_models_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('LocalModelCatalog', () {
    test('los modelos tienen id único, archivo .gguf y url https', () {
      final ids = LocalModelCatalog.models.map((m) => m.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final m in LocalModelCatalog.models) {
        expect(m.fileName, endsWith('.gguf'));
        expect(m.url, startsWith('https://huggingface.co/'));
        expect(m.url, endsWith(m.fileName));
        expect(m.sizeBytes, greaterThan(100000000));
      }
      expect(LocalModelCatalog.byId('no existe'), isNull);
    });
  });

  group('LocalModelManager', () {
    test('descarga completa: guarda el archivo, informa del progreso y no deja .part', () async {
      final manager = LocalModelManager(
        directory: dir,
        httpClient: MockClient.streaming((request, _) async => http.StreamedResponse(Stream.value(_bytes(1000)), 200, contentLength: 1000)),
      );
      final seen = <int>[];

      await manager.download(_model, onProgress: (received, total) => seen.add(received));

      expect(await manager.isInstalled(_model), isTrue);
      expect((await manager.fileFor(_model)).lengthSync(), 1000);
      expect(File('${(await manager.fileFor(_model)).path}.part').existsSync(), isFalse);
      expect(seen.last, 1000);
    });

    test('una descarga cortada se reanuda con Range y completa el archivo', () async {
      var call = 0;
      String? rangeHeader;
      final manager = LocalModelManager(
        directory: dir,
        httpClient: MockClient.streaming((request, _) async {
          call++;
          if (call == 1) return http.StreamedResponse(Stream.value(_bytes(400)), 200, contentLength: 1000);
          rangeHeader = request.headers['Range'];
          return http.StreamedResponse(Stream.value(_bytes(1000).sublist(400)), 206, contentLength: 600);
        }),
      );

      await expectLater(manager.download(_model), throwsA(isA<ModelDownloadException>()));
      expect(await manager.partialBytes(_model), 400);
      expect(await manager.isInstalled(_model), isFalse);

      await manager.download(_model);

      expect(rangeHeader, 'bytes=400-');
      expect(await manager.isInstalled(_model), isTrue);
      expect((await manager.fileFor(_model)).readAsBytesSync(), _bytes(1000));
    });

    test('si el servidor ignora Range y manda todo otra vez, no duplica los bytes', () async {
      var call = 0;
      final manager = LocalModelManager(
        directory: dir,
        httpClient: MockClient.streaming((request, _) async {
          call++;
          if (call == 1) return http.StreamedResponse(Stream.value(_bytes(300)), 200, contentLength: 1000);
          return http.StreamedResponse(Stream.value(_bytes(1000)), 200, contentLength: 1000);
        }),
      );
      await expectLater(manager.download(_model), throwsA(isA<ModelDownloadException>()));

      await manager.download(_model);

      expect((await manager.fileFor(_model)).lengthSync(), 1000);
    });

    test('un error del servidor lanza ModelDownloadException y no deja archivo', () async {
      final manager = LocalModelManager(directory: dir, httpClient: MockClient.streaming((request, _) async => http.StreamedResponse(const Stream.empty(), 403)));

      await expectLater(manager.download(_model), throwsA(isA<ModelDownloadException>()));
      expect(await manager.isInstalled(_model), isFalse);
    });

    test('cancelar conserva lo descargado para continuar', () async {
      final cancel = DownloadCancel();
      final manager = LocalModelManager(
        directory: dir,
        httpClient: MockClient.streaming((request, _) async => http.StreamedResponse(
              Stream.fromIterable([_bytes(300), _bytes(300), _bytes(400)]),
              200,
              contentLength: 1000,
            )),
      );

      await expectLater(manager.download(_model, cancel: cancel, onProgress: (r, t) => cancel.cancel()), throwsA(isA<ModelDownloadException>()));

      expect(await manager.isInstalled(_model), isFalse);
      expect(await manager.partialBytes(_model), greaterThan(0));
    });

    test('borrar quita el archivo y el parcial', () async {
      final manager = LocalModelManager(
        directory: dir,
        httpClient: MockClient.streaming((request, _) async => http.StreamedResponse(Stream.value(_bytes(1000)), 200, contentLength: 1000)),
      );
      await manager.download(_model);

      await manager.delete(_model);

      expect(await manager.isInstalled(_model), isFalse);
    });
  });

  group('RoutingLlmClient', () {
    test('manda cada petición al proveedor que eligió el usuario, leyéndolo en cada llamada', () async {
      final remote = _FakeClient('remoto');
      final local = _FakeClient('local');
      final storage = SecureConfigStorage();
      final router = RoutingLlmClient(storage: storage, remote: remote, local: local);
      final request = ChatCompletionRequest(model: 'm', messages: [ChatMessage.user('hola')]);

      FlutterSecureStorage.setMockInitialValues({'aura.api.base_url': 'https://a', 'aura.api.key': 'k', 'aura.api.model_id': 'm'});
      expect((await router.send(request)).content, 'remoto');

      await storage.save(const ApiEndpointConfig(baseUrl: '', apiKey: '', modelId: '', provider: 'local', localModelId: 'gemma3-1b-abliterated-q4'));
      expect((await router.send(request)).content, 'local');
      expect((await router.stream(request).first).deltaContent, 'local');
      expect(remote.calls, 1);
      expect(local.calls, 2);
    });
  });

  group('config con proveedor local', () {
    test('una config local no necesita url ni key y se guarda y lee', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SecureConfigStorage();

      await storage.save(const ApiEndpointConfig(baseUrl: '', apiKey: '', modelId: '', provider: 'local', localModelId: 'gemma3-1b-abliterated-q4'));
      final loaded = (await storage.load())!;

      expect(loaded.isLocal, isTrue);
      expect(loaded.isComplete, isTrue);
      expect(loaded.localModelId, 'gemma3-1b-abliterated-q4');
    });

    test('local sin modelo elegido no cuenta como configurado', () async {
      FlutterSecureStorage.setMockInitialValues({'aura.api.provider': 'local'});

      expect(await SecureConfigStorage().load(), isNull);
      expect(const ApiEndpointConfig(baseUrl: '', apiKey: '', modelId: '', provider: 'local').isComplete, isFalse);
    });

    test('un valor de proveedor desconocido vuelve al remoto', () async {
      FlutterSecureStorage.setMockInitialValues({'aura.api.base_url': 'https://a', 'aura.api.key': 'k', 'aura.api.model_id': 'm', 'aura.api.provider': 'raro'});

      expect((await SecureConfigStorage().load())!.provider, 'remote');
    });
  });
}
