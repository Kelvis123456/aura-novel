import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/exceptions/api_exceptions.dart';
import '../../core/network/models/chat_message.dart';
import '../../core/storage/secure_config_storage.dart';
import '../lore/lore_repository.dart';
import '../lore/models/lore_item_model.dart';
import '../projects/models/project_model.dart';
import '../projects/models/story_node_model.dart';
import '../projects/project_repository.dart';
import 'chapter_writer.dart';
import 'chat_entry.dart';
import 'writer_service.dart';
import 'writing_profile.dart';

enum ChatMode { chat, chapter, research }

/// State and actions of the writing assistant screen: which project and
/// chapter it is working on, the saved conversation, and the three things the
/// author can ask for (talk, write a long piece, research).
class WriterChatController extends ChangeNotifier {
  final ProjectRepository _repo;
  final LoreRepository _lore;
  final WriterService _service;
  final ChapterWriter _chapterWriter;
  final SecureConfigStorage _storage;

  WriterChatController({
    required ProjectRepository repository,
    required LoreRepository lore,
    required WriterService service,
    required ChapterWriter chapterWriter,
    required SecureConfigStorage storage,
  })  : _repo = repository,
        _lore = lore,
        _service = service,
        _chapterWriter = chapterWriter,
        _storage = storage;

  List<ProjectModel> projects = [];
  ProjectModel? project;
  List<ChapterModel> chapters = [];
  ChapterModel? chapter;
  List<ChatEntry> entries = [];

  bool generating = false;
  String? error;

  /// "Escena 2 de 4" while a long piece is being written.
  String? progress;

  StreamSubscription<Object?>? _subscription;
  Completer<void>? _running;

  WritingProfile get profile => project?.writingProfile ?? const WritingProfile();

  Future<void> load({String? projectId}) async {
    projects = await _repo.getAllProjects();
    final wanted = projectId ?? project?.id;
    project = projects.where((p) => p.id == wanted).firstOrNull ?? (projects.isEmpty ? null : projects.first);
    await _loadProject();
  }

  Future<void> selectProject(String? id) async {
    project = projects.where((p) => p.id == id).firstOrNull;
    chapter = null;
    await _loadProject();
  }

  Future<void> selectChapter(String? id) async {
    chapter = chapters.where((c) => c.id == id).firstOrNull;
    notifyListeners();
  }

  Future<void> _loadProject() async {
    chapters = project == null ? [] : await _repo.getChaptersForProject(project!.id);
    if (chapter != null && !chapters.any((c) => c.id == chapter!.id)) chapter = null;
    entries = await _repo.getChat(project?.id);
    error = null;
    notifyListeners();
  }

  Future<void> saveProfile(WritingProfile profile) async {
    final p = project;
    if (p == null) return;
    await _repo.setProjectWritingProfile(p.id, profile);
    project = p.copyWith(writingProfile: profile);
    projects = [for (final x in projects) x.id == p.id ? project! : x];
    notifyListeners();
  }

  // ---- Asking ------------------------------------------------------------

  /// Sends [text] in [mode]. [words] and [continueChapter] only matter for chapters.
  Future<void> send(String text, ChatMode mode, {int words = 1500, bool continueChapter = true}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || generating) return;

    final user = ChatEntry(
      id: ProjectRepository.generateId(),
      projectId: project?.id,
      role: ChatRole.user,
      content: trimmed,
      kind: switch (mode) {
        ChatMode.chat => 'chat',
        ChatMode.chapter => 'chapter',
        ChatMode.research => 'research',
      },
      createdAt: DateTime.now(),
    );
    entries = [...entries, user];
    error = null;
    await _repo.saveChatEntry(user);
    await _respond(user, mode, words: words, continueChapter: continueChapter);
  }

  /// Drops the last assistant answer and asks again.
  Future<void> regenerate() async {
    if (generating || entries.isEmpty) return;
    error = null;
    var lastUser = entries.lastIndexWhere((e) => e.role == ChatRole.user);
    if (lastUser < 0) return;
    for (final e in entries.sublist(lastUser + 1)) {
      await _repo.deleteChatEntry(e.id);
    }
    entries = entries.sublist(0, lastUser + 1);
    final user = entries.last;
    final mode = switch (user.kind) {
      'chapter' => ChatMode.chapter,
      'research' => ChatMode.research,
      _ => ChatMode.chat,
    };
    await _respond(user, mode, words: 1500, continueChapter: true);
  }

  /// Runs one craft module on [material] and shows the answer in the chat.
  Future<void> runTool(String moduleId, String material, {String note = ''}) async {
    if (generating || material.trim().isEmpty) return;
    final user = ChatEntry(
      id: ProjectRepository.generateId(),
      projectId: project?.id,
      role: ChatRole.user,
      content: note.trim().isEmpty ? material.trim() : '${note.trim()}\n\n${material.trim()}',
      kind: 'tool',
      createdAt: DateTime.now(),
    );
    entries = [...entries, user];
    await _repo.saveChatEntry(user);

    final answer = _newAnswer('tool');
    await _stream(answer, _service.runTool(moduleId: moduleId, material: material, profile: profile, note: note, context: await _context(material)).map((t) => t));
  }

  Future<void> _respond(ChatEntry user, ChatMode mode, {required int words, required bool continueChapter}) async {
    switch (mode) {
      case ChatMode.chat:
        final answer = _newAnswer('chat');
        await _stream(answer, _service.reply(history: entries.sublist(0, entries.length - 1) + [user], profile: profile, context: await _context(user.content)));
      case ChatMode.chapter:
        await _writeChapter(user, words, continueChapter);
      case ChatMode.research:
        await _research(user);
    }
  }

  Future<void> _writeChapter(ChatEntry user, int words, bool continueChapter) async {
    final answer = _newAnswer('chapter');
    final existing = continueChapter && chapter != null ? (await _repo.getLatestNodeForChapter(chapter!.id))?.content ?? '' : '';
    final context = await _context('${user.content}\n$existing');
    final events = _chapterWriter.write(
      instruction: user.content,
      targetWords: words,
      profile: profile,
      context: context,
      existingText: existing,
    );
    await _stream(answer, events.map((e) => e), onEvent: (e) {
      if (e is SegmentStarted) {
        progress = 'Escena ${e.index + 1} de ${e.total}';
        notifyListeners();
      }
    });
  }

  Future<void> _research(ChatEntry user) async {
    final answer = _newAnswer('research');
    generating = true;
    progress = 'Investigando…';
    notifyListeners();
    try {
      final text = await _service.research(
        topic: user.content,
        profile: profile,
        storyContext: project == null ? '' : '${project!.title}. ${project!.synopsis}'.trim(),
      );
      _setContent(answer, text);
      await _repo.saveChatEntry(entries.last);
    } on ApiClientException catch (e) {
      error = e.message;
      _dropEmptyAnswer(answer);
    } finally {
      generating = false;
      progress = null;
      notifyListeners();
    }
  }

  /// Saves a research answer as a lore sheet so the assistant can use it later.
  Future<void> saveResearch(ChatEntry answer) async {
    final i = entries.indexWhere((e) => e.id == answer.id);
    final topic = i > 0 ? entries[i - 1].content : 'Investigación';
    final name = topic.length > 60 ? '${topic.substring(0, 57)}…' : topic;
    final tags = topic.split(RegExp(r'[\s,.;:]+')).where((w) => w.length > 4).take(6).toList();
    await _lore.saveLoreItem(LoreItemModel(
      id: LoreRepository.generateId(),
      name: name,
      category: LoreCategory.research,
      shortDescription: 'Notas de investigación',
      longDetails: answer.content,
      tags: tags,
      projectId: project?.id,
    ));
  }

  // ---- Using the output --------------------------------------------------

  /// Adds [entry]'s text to the selected chapter as a new saved version, or
  /// creates a chapter named [newChapterTitle] when none is selected.
  Future<ChapterModel> insert(ChatEntry entry, {String? newChapterTitle}) async {
    final p = project;
    if (p == null) throw StateError('Choose a project first.');
    var target = chapter;
    if (target == null) {
      final title = (newChapterTitle ?? '').trim();
      if (title.isEmpty) throw StateError('A chapter title is needed.');
      target = ChapterModel(id: ProjectRepository.generateId(), projectId: p.id, title: title, order: chapters.length);
      await _repo.saveChapter(target);
      chapters = [...chapters, target];
      chapter = target;
    }
    final latest = await _repo.getLatestNodeForChapter(target.id);
    final base = latest?.content.trimRight() ?? '';
    await _repo.saveNode(StoryNodeModel(
      id: ProjectRepository.generateId(),
      chapterId: target.id,
      parentNodeId: latest?.id,
      content: base.isEmpty ? entry.content.trim() : '$base\n\n${entry.content.trim()}',
      branchName: '',
      timestamp: DateTime.now(),
    ));
    notifyListeners();
    return target;
  }

  Future<void> clear() async {
    await _repo.clearChat(project?.id);
    entries = [];
    error = null;
    notifyListeners();
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    if (generating) {
      generating = false;
      progress = null;
      final last = entries.isEmpty ? null : entries.last;
      if (last != null && last.role == ChatRole.assistant) {
        if (last.content.isEmpty) {
          entries = entries.sublist(0, entries.length - 1);
        } else {
          unawaited(_repo.saveChatEntry(last));
        }
      }
      notifyListeners();
    }
    _running?.complete();
    _running = null;
  }

  // ---- Internals ---------------------------------------------------------

  Future<List<ChatMessage>> _context(String relevantText) async {
    final config = await _storage.load();
    return _service.projectContext(
      project: project,
      chapterId: chapter?.id,
      relevantText: relevantText,
      maxChars: config?.contextChars ?? ApiEndpointConfig.defaultContextChars,
    );
  }

  ChatEntry _newAnswer(String kind) {
    final answer = ChatEntry(
      id: ProjectRepository.generateId(),
      projectId: project?.id,
      role: ChatRole.assistant,
      content: '',
      kind: kind,
      createdAt: DateTime.now(),
    );
    entries = [...entries, answer];
    return answer;
  }

  void _setContent(ChatEntry answer, String content) {
    entries = [for (final e in entries) e.id == answer.id ? e.copyWith(content: content) : e];
  }

  void _dropEmptyAnswer(ChatEntry answer) {
    entries = [for (final e in entries) if (!(e.id == answer.id && e.content.isEmpty)) e];
  }

  /// Consumes a stream of text chunks or [WriterEvent]s into [answer].
  Future<void> _stream(ChatEntry answer, Stream<Object?> source, {void Function(WriterEvent)? onEvent}) async {
    generating = true;
    error = null;
    progress = null;
    notifyListeners();

    final done = Completer<void>();
    _running = done;
    var text = StringBuffer();
    var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

    _subscription = source.listen(
      (item) {
        if (item is String) {
          text.write(item);
        } else if (item is ProseDelta) {
          text.write(item.text);
        } else if (item is WriterEvent) {
          onEvent?.call(item);
        }
        _setContent(answer, text.toString());
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds > 60) {
          lastNotify = now;
          notifyListeners();
        }
      },
      onError: (Object e) {
        error = e is ApiClientException ? e.message : 'Error inesperado: $e';
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    await done.future;
    _subscription = null;
    _running = null;
    generating = false;
    progress = null;
    final current = entries.where((e) => e.id == answer.id).firstOrNull;
    if (current != null) {
      if (current.content.trim().isEmpty) {
        _dropEmptyAnswer(answer);
      } else {
        await _repo.saveChatEntry(current);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
