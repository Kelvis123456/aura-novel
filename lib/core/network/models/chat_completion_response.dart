/// Full (non-streaming) response from `/chat/completions`.
class ChatCompletionResponse {
  final String id;
  final String model;
  final String content;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;

  const ChatCompletionResponse({
    required this.id,
    required this.model,
    required this.content,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
  });

  factory ChatCompletionResponse.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>? ?? const [];
    final firstChoice = choices.isNotEmpty
        ? choices.first as Map<String, dynamic>
        : <String, dynamic>{};
    final message = firstChoice['message'] as Map<String, dynamic>? ?? {};
    final usage = json['usage'] as Map<String, dynamic>?;

    return ChatCompletionResponse(
      id: json['id'] as String? ?? '',
      model: json['model'] as String? ?? '',
      content: message['content'] as String? ?? '',
      finishReason: firstChoice['finish_reason'] as String?,
      promptTokens: usage?['prompt_tokens'] as int?,
      completionTokens: usage?['completion_tokens'] as int?,
    );
  }
}

/// A single incremental chunk from an SSE stream
/// (`choices[0].delta.content`).
class ChatCompletionChunk {
  final String deltaContent;
  final String? finishReason;
  final bool isDone;

  const ChatCompletionChunk({
    required this.deltaContent,
    this.finishReason,
    this.isDone = false,
  });

  factory ChatCompletionChunk.done() => const ChatCompletionChunk(
        deltaContent: '',
        isDone: true,
      );

  factory ChatCompletionChunk.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>? ?? const [];
    final firstChoice = choices.isNotEmpty
        ? choices.first as Map<String, dynamic>
        : <String, dynamic>{};
    final delta = firstChoice['delta'] as Map<String, dynamic>? ?? {};

    return ChatCompletionChunk(
      deltaContent: delta['content'] as String? ?? '',
      finishReason: firstChoice['finish_reason'] as String?,
    );
  }
}
