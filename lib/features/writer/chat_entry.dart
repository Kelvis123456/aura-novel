import 'dart:convert';

/// One message of the writing assistant's conversation, stored per project.
class ChatEntry {
  final String id;

  /// Null for the conversation with no project attached.
  final String? projectId;
  final String role;
  final String content;

  /// What produced it: a plain `chat` turn, a long `chapter`, a `research` note
  /// or a `tool` run (one of the craft modules).
  final String kind;
  final DateTime createdAt;

  /// What it takes to repeat the request: `words` and `continue` for a chapter,
  /// `tool`, `material` and `note` for a craft tool.
  final Map<String, dynamic> meta;

  const ChatEntry({
    required this.id,
    this.projectId,
    required this.role,
    required this.content,
    this.kind = 'chat',
    required this.createdAt,
    this.meta = const {},
  });

  ChatEntry copyWith({String? content}) => ChatEntry(
        id: id,
        projectId: projectId,
        role: role,
        content: content ?? this.content,
        kind: kind,
        createdAt: createdAt,
        meta: meta,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'project_id': projectId,
        'role': role,
        'content': content,
        'kind': kind,
        'created_at': createdAt.toIso8601String(),
        'meta': meta.isEmpty ? '' : jsonEncode(meta),
      };

  factory ChatEntry.fromMap(Map<String, dynamic> map) => ChatEntry(
        id: map['id'] as String,
        projectId: map['project_id'] as String?,
        role: map['role'] as String,
        content: map['content'] as String? ?? '',
        kind: map['kind'] as String? ?? 'chat',
        createdAt: DateTime.parse(map['created_at'] as String),
        meta: _decodeMeta(map['meta'] as String?),
      );

  static Map<String, dynamic> _decodeMeta(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}
