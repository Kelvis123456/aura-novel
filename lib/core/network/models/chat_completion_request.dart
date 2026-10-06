import 'chat_message.dart';

/// Generation parameters + payload builder for an OpenAI-compatible
/// `/chat/completions` request. Any field left null is omitted from the
/// JSON body so server-side defaults apply.
class ChatCompletionRequest {
  final String model;
  final List<ChatMessage> messages;
  final double? temperature;
  final int? maxTokens;
  final double? frequencyPenalty;
  final double? presencePenalty;
  final double? topP;
  final List<String>? stop;
  final bool stream;

  const ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.temperature,
    this.maxTokens,
    this.frequencyPenalty,
    this.presencePenalty,
    this.topP,
    this.stop,
    this.stream = false,
  });

  ChatCompletionRequest copyWith({
    List<ChatMessage>? messages,
    bool? stream,
  }) {
    return ChatCompletionRequest(
      model: model,
      messages: messages ?? this.messages,
      temperature: temperature,
      maxTokens: maxTokens,
      frequencyPenalty: frequencyPenalty,
      presencePenalty: presencePenalty,
      topP: topP,
      stop: stop,
      stream: stream ?? this.stream,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': stream,
    };
    if (temperature != null) json['temperature'] = temperature;
    if (maxTokens != null) json['max_tokens'] = maxTokens;
    if (frequencyPenalty != null) json['frequency_penalty'] = frequencyPenalty;
    if (presencePenalty != null) json['presence_penalty'] = presencePenalty;
    if (topP != null) json['top_p'] = topP;
    if (stop != null && stop!.isNotEmpty) json['stop'] = stop;
    return json;
  }
}
