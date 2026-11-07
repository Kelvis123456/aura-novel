import 'package:flutter/material.dart';

import 'storage/secure_config_storage.dart';
import '../features/lore/context_builder_service.dart';
import '../features/lore/lore_repository.dart';
import '../features/projects/backup_service.dart';
import '../features/projects/chapter_summary_service.dart';
import '../features/projects/consistency_service.dart';
import '../features/projects/project_repository.dart';
import '../features/writer/chapter_writer.dart';
import '../features/writer/prompt_composer.dart';
import '../features/writer/writer_service.dart';
import 'network/llm_client.dart';
import 'network/local_llm_client.dart';
import '../features/local_model/local_model_manager.dart';

/// App-wide dependency container. A single instance of each shared resource
/// (network client, secure storage, lore DB, project DB) lives here so
/// EditorScreen, LoreStudioScreen and ProjectManagerScreen all read/write
/// the same underlying data instead of each opening their own connection.
///
/// These instances are stable for the app's lifetime, so [updateShouldNotify]
/// always returns false — `AppScope.of` performs a one-time ancestor lookup
/// rather than subscribing to rebuilds, which makes it safe to call from
/// `initState`.
class AppScope extends InheritedWidget {
  final SecureConfigStorage configStorage;
  final LlmClient apiClient;
  final LoreRepository loreRepository;
  final ContextBuilderService contextBuilder;
  final ProjectRepository projectRepository;
  final ChapterSummaryService chapterSummaryService;
  final BackupService backupService;
  final ConsistencyService consistencyService;
  final PromptComposer promptComposer;
  final WriterService writerService;
  final ChapterWriter chapterWriter;
  final LocalLlmClient localClient;
  final LocalModelManager localModels;

  const AppScope({
    super.key,
    required this.configStorage,
    required this.apiClient,
    required this.loreRepository,
    required this.contextBuilder,
    required this.projectRepository,
    required this.chapterSummaryService,
    required this.backupService,
    required this.consistencyService,
    required this.promptComposer,
    required this.writerService,
    required this.chapterWriter,
    required this.localClient,
    required this.localModels,
    required super.child,
  });

  static AppScope of(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    assert(element != null, 'AppScope not found in context. Wrap the app in AppScope.');
    return element!.widget as AppScope;
  }

  @override
  bool updateShouldNotify(covariant AppScope oldWidget) => false;
}
