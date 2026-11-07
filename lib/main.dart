import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_scope.dart';
import 'core/theme/aura_theme.dart';
import 'core/widgets/app_shell.dart';
import 'core/network/dynamic_openai_client.dart';
import 'core/storage/secure_config_storage.dart';
import 'features/lore/context_builder_service.dart';
import 'features/lore/lore_repository.dart';
import 'core/network/llm_client.dart';
import 'core/network/local_llm_client.dart';
import 'core/network/routing_llm_client.dart';
import 'features/local_model/local_model_manager.dart';
import 'features/projects/backup_service.dart';
import 'features/projects/chapter_summary_service.dart';
import 'features/projects/consistency_service.dart';
import 'features/projects/project_repository.dart';
import 'features/writer/chapter_writer.dart';
import 'features/writer/craft_library.dart';
import 'features/writer/prompt_composer.dart';
import 'features/writer/writer_service.dart';

void main() {
  runApp(const AuraNovelApp());
}

/// Owns every shared, long-lived resource (network client, secure storage,
/// lore DB, project DB) for the app's lifetime and exposes them to the
/// widget tree via [AppScope], so EditorScreen/LoreStudioScreen/
/// ProjectManagerScreen all read and write the same underlying data.
class AuraNovelApp extends StatefulWidget {
  const AuraNovelApp({super.key});

  @override
  State<AuraNovelApp> createState() => _AuraNovelAppState();
}

class _AuraNovelAppState extends State<AuraNovelApp> {
  late final SecureConfigStorage _configStorage;
  late final LlmClient _apiClient;
  late final LocalLlmClient _localClient;
  late final LocalModelManager _localModels;
  late final LoreRepository _loreRepository;
  late final ContextBuilderService _contextBuilder;
  late final ProjectRepository _projectRepository;
  late final ChapterSummaryService _chapterSummaryService;
  late final BackupService _backupService;
  late final ConsistencyService _consistencyService;
  late final PromptComposer _promptComposer;
  late final WriterService _writerService;
  late final ChapterWriter _chapterWriter;

  @override
  void initState() {
    super.initState();
    _configStorage = SecureConfigStorage();
    _localModels = LocalModelManager();
    _localClient = LocalLlmClient(storage: _configStorage, manager: _localModels);
    _apiClient = RoutingLlmClient(
      storage: _configStorage,
      remote: DynamicOpenAIClient(configStorage: _configStorage),
      local: _localClient,
    );
    _loreRepository = LoreRepository();
    _contextBuilder = ContextBuilderService(repository: _loreRepository);
    _projectRepository = ProjectRepository();
    final craft = CraftLibrary();
    _chapterSummaryService = ChapterSummaryService(
      client: _apiClient,
      repository: _projectRepository,
      storage: _configStorage,
      guidance: () async => (await _configStorage.load())?.isLocal == true ? null : craft.rules('summarization'),
    );
    _backupService = BackupService(projects: _projectRepository, lore: _loreRepository);
    // A model in the phone has a small context: it always gets the short craft prompt.
    _promptComposer = PromptComposer(craft, preferShort: () async => (await _configStorage.load())?.isLocal ?? false);
    _writerService = WriterService(
      client: _apiClient,
      storage: _configStorage,
      composer: _promptComposer,
      lore: _contextBuilder,
      summaries: _chapterSummaryService,
    );
    _chapterWriter = ChapterWriter(client: _apiClient, storage: _configStorage, composer: _promptComposer);
    _consistencyService = ConsistencyService(
      client: _apiClient,
      repository: _projectRepository,
      contextBuilder: _contextBuilder,
      summaries: _chapterSummaryService,
      storage: _configStorage,
    );
  }

  @override
  void dispose() {
    _apiClient.dispose();
    _loreRepository.close();
    _projectRepository.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      configStorage: _configStorage,
      apiClient: _apiClient,
      loreRepository: _loreRepository,
      contextBuilder: _contextBuilder,
      projectRepository: _projectRepository,
      chapterSummaryService: _chapterSummaryService,
      backupService: _backupService,
      consistencyService: _consistencyService,
      promptComposer: _promptComposer,
      writerService: _writerService,
      chapterWriter: _chapterWriter,
      localClient: _localClient,
      localModels: _localModels,
      child: MaterialApp(
        title: 'AURA NOVEL',
        debugShowCheckedModeBanner: false,
        theme: AuraTheme.light,
        darkTheme: AuraTheme.dark,
        themeMode: ThemeMode.system,
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
              systemNavigationBarColor: context.aura.bg,
              systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            ),
            child: child!,
          );
        },
        home: const AppShell(),
      ),
    );
  }
}
