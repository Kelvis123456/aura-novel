import 'package:flutter/material.dart';

import 'network/dynamic_openai_client.dart';
import 'storage/secure_config_storage.dart';
import '../features/lore/context_builder_service.dart';
import '../features/lore/lore_repository.dart';
import '../features/projects/project_repository.dart';

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
  final DynamicOpenAIClient apiClient;
  final LoreRepository loreRepository;
  final ContextBuilderService contextBuilder;
  final ProjectRepository projectRepository;

  const AppScope({
    super.key,
    required this.configStorage,
    required this.apiClient,
    required this.loreRepository,
    required this.contextBuilder,
    required this.projectRepository,
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
