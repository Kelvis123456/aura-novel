import '../../core/network/models/chat_message.dart';
import 'craft_library.dart';
import 'writing_profile.dart';

/// Builds the system prompts for the three ways the app talks to the model:
/// writing prose, chatting with the author, and running one craft tool.
class PromptComposer {
  final CraftLibrary library;

  /// True when the model in use can't take the long craft prompt (a small local one).
  final Future<bool> Function()? preferShort;

  PromptComposer(this.library, {this.preferShort});

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
    final deep = await preferShort?.call() != true;
    final parts = <String>[
      await library.persona(),
      'PROJECT PROFILE\n${profile.toPromptBlock()}',
      'TOOL: ${CraftLibrary.byId(moduleId)?.label ?? moduleId}\nApply the following module to the author\'s material. Answer in ${profile.languageName}.\n\n${await library.full(moduleId, deep: deep)}',
    ];
    return ChatMessage.system(parts.join('\n\n'));
  }

  /// For the pass that rewrites a finished scene: same events, better sentences.
  Future<ChatMessage> polishSystem(WritingProfile profile) async {
    final parts = <String>[
      await library.persona(),
      'PROJECT PROFILE\n${profile.toPromptBlock()}',
      'POLISH PASS\n'
          'You receive one scene of a draft. Rewrite it applying the craft rules below: remove machine-writing tics, flat or '
          'repetitive sentences, stock phrases and clichés; sharpen dialogue, rhythm and concrete detail. Keep every event, fact, '
          'name, point of view, tense, language and register, and keep about the same length. Add no plot and remove none. '
          'Output only the rewritten scene, with no comments.',
      await _craft(profile),
    ];
    return ChatMessage.system(parts.join('\n\n'));
  }

  Future<String> _craft(WritingProfile profile, {List<String> extra = const []}) async {
    if (profile.craftLevel == CraftLevel.esencial || await preferShort?.call() == true) return library.essentials();
    final ids = [...CraftLibrary.coreIds, ...extra];
    final blocks = <String>[];
    for (final id in ids) {
      final name = CraftLibrary.byId(id)?.label ?? id;
      blocks.add('[$name]\n${await library.rules(id)}');
    }
    return 'CRAFT RULES (apply them silently; never mention them)\n\n${blocks.join('\n\n')}';
  }
}
