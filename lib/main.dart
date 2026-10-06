import 'package:flutter/material.dart';

import 'core/app_scope.dart';
import 'core/network/dynamic_openai_client.dart';
import 'core/storage/secure_config_storage.dart';
import 'features/editor/editor_screen.dart';
import 'features/lore/context_builder_service.dart';
import 'features/lore/lore_repository.dart';
import 'features/projects/project_repository.dart';

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

  @override
  void initState() {
    super.initState();
    _configStorage = SecureConfigStorage();
    _apiClient = DynamicOpenAIClient(configStorage: _configStorage);
    _loreRepository = LoreRepository();
    _contextBuilder = ContextBuilderService(repository: _loreRepository);
    _projectRepository = ProjectRepository();
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
      child: MaterialApp(
        title: 'AURA NOVEL',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF000000),
        ),
        home: const EditorScreen(),
      ),
    );
  }
}
