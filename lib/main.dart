import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_scope.dart';
import 'core/theme/aura_theme.dart';
import 'core/widgets/app_shell.dart';
import 'core/network/dynamic_openai_client.dart';
import 'core/storage/secure_config_storage.dart';
import 'features/lore/context_builder_service.dart';
import 'features/lore/lore_repository.dart';
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
  late final DynamicOpenAIClient _apiClient;
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
    _apiClient = DynamicOpenAIClient(configStorage: _configStorage);
    _loreRepository = LoreRepository();
    _contextBuilder = ContextBuilderService(repository: _loreRepository);
    _projectRepository = ProjectRepository();
    _chapterSummaryService = ChapterSummaryService(
      client: _apiClient,
      repository: _projectRepository,
      storage: _configStorage,
    );
    _backupService = BackupService(projects: _projectRepository, lore: _loreRepository);
    _promptComposer = PromptComposer(CraftLibrary());
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
