import '../storage/secure_config_storage.dart';
import 'llm_client.dart';
import 'models/chat_completion_request.dart';
import 'models/chat_completion_response.dart';

/// Sends each request to the remote server or to the model in the phone,
/// depending on the provider the user chose in the settings. The choice is read
/// on every call, so switching in the settings takes effect immediately.
class RoutingLlmClient implements LlmClient {
  final SecureConfigStorage _storage;
  final LlmClient remote;
  final LlmClient local;

  RoutingLlmClient({required SecureConfigStorage storage, required this.remote, required this.local}) : _storage = storage;

  Future<LlmClient> _pick() async => (await _storage.load())?.isLocal == true ? local : remote;

  @override
  Future<ChatCompletionResponse> send(ChatCompletionRequest request) async => (await _pick()).send(request);

  @override
  Stream<ChatCompletionChunk> stream(ChatCompletionRequest request) async* {
    yield* (await _pick()).stream(request);
  }

  @override
  void dispose() {
    remote.dispose();
    local.dispose();
  }
}
