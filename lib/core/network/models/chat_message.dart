/// A single message in an OpenAI-compatible chat completion payload.
class ChatRole {
  static const system = 'system';
  static const user = 'user';
  static const assistant = 'assistant';
}

class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  factory ChatMessage.system(String content) =>
      ChatMessage(role: ChatRole.system, content: content);

  factory ChatMessage.user(String content) =>
      ChatMessage(role: ChatRole.user, content: content);

  factory ChatMessage.assistant(String content) =>
      ChatMessage(role: ChatRole.assistant, content: content);

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}
