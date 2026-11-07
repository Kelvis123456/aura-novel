import '../../core/network/models/chat_message.dart';
import 'craft_library.dart';
import 'writing_profile.dart';

/// Builds the system prompts for the three ways the app talks to the model:
/// writing prose, chatting with the author, and running one craft tool.
class PromptComposer {
  final CraftLibrary library;

  PromptComposer(this.library);

  /// For prose that goes straight into the manuscript.
  Future<ChatMessage> proseSystem(WritingProfile profile, {bool longForm = false}) async {
    final parts = <String>[
      await library.persona(),
      'PROJECT PROFILE\n${profile.toPromptBlock()}',
      await _craft(profile, extra: longForm ? const ['story-long-write'] : const []),
    ];
    return ChatMessage.system(parts.join('\n\n'));
  }

  /// For the conversation with the author.
  Future<ChatMessage> chatSystem(WritingProfile profile) async {
    final parts = <String>[
      await library.persona(),
      await library.chatMode(),
      'PROJECT PROFILE\n${profile.toPromptBlock()}',
      await _craft(profile),
    ];
    return ChatMessage.system(parts.join('\n\n'));
  }

  /// For running one module on a passage or a question. The module's own text
  /// says what to return; the persona keeps the author's freedom intact.
  Future<ChatMessage> toolSystem(String moduleId, WritingProfile profile) async {
    final parts = <String>[
      await library.persona(),
      'PROJECT PROFILE\n${profile.toPromptBlock()}',
      'TOOL: ${CraftLibrary.byId(moduleId)?.label ?? moduleId}\nApply the following module to the author\'s material. Answer in ${profile.languageName}.\n\n${await library.full(moduleId)}',
    ];
    return ChatMessage.system(parts.join('\n\n'));
  }

  Future<String> _craft(WritingProfile profile, {List<String> extra = const []}) async {
    if (profile.craftLevel == CraftLevel.esencial) return library.essentials();
    final ids = [...CraftLibrary.coreIds, ...extra];
    final blocks = <String>[];
    for (final id in ids) {
      final name = CraftLibrary.byId(id)?.label ?? id;
      blocks.add('[$name]\n${await library.rules(id)}');
    }
    return 'CRAFT RULES (apply them silently; never mention them)\n\n${blocks.join('\n\n')}';
  }
}
