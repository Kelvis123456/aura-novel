import 'models/chat_completion_request.dart';
import 'models/chat_completion_response.dart';

/// What the app needs from a language model, wherever it runs: an OpenAI
/// compatible server ([DynamicOpenAIClient]) or a model inside the phone
/// ([LocalLlmClient]). Services depend on this, not on a concrete client.
abstract class LlmClient {
  Future<ChatCompletionResponse> send(ChatCompletionRequest request);

  Stream<ChatCompletionChunk> stream(ChatCompletionRequest request);

  void dispose();
}
