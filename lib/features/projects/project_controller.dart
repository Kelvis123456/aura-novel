import 'package:flutter/material.dart';

import 'models/project_model.dart';
import 'models/story_node_model.dart';
import 'project_repository.dart';

/// Business logic for [ProjectManagerScreen]: project/chapter CRUD plus the
/// branching-history operations (`saveVersion`, `createBranch`) that back
/// [BranchTreeViewer].
class ProjectController extends ChangeNotifier {
  final ProjectRepository repository;
  final bool _ownsRepository;

  /// [repository] is normally the shared instance from [AppScope] — pass
  /// none to let this controller open (and own) its own database, e.g. in
  /// isolated tests.
  ProjectController({ProjectRepository? repository})
      : repository = repository ?? ProjectRepository(),
        _ownsRepository = repository == null;

  bool isLoading = true;
  List<ProjectModel> projects = [];

  Future<void> loadProjects() async {
    isLoading = true;
    notifyListeners();
    projects = await repository.getAllProjects();
    isLoading = false;
    notifyListeners();
  }

  Future<ProjectModel> createProject({required String title, String synopsis = ''}) async {
    final now = DateTime.now();
    final project = ProjectModel(
      id: ProjectRepository.generateId(),
      title: title,
      synopsis: synopsis,
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveProject(project);
    await loadProjects();
    return project;
  }

  Future<void> renameProject(ProjectModel project, {required String title, required String synopsis}) async {
    await repository.saveProject(project.copyWith(title: title, synopsis: synopsis, updatedAt: DateTime.now()));
    await loadProjects();
  }

  Future<void> deleteProject(String id) async {
    await repository.deleteProjectCascade(id);
    await loadProjects();
  }

  Future<List<ChapterModel>> loadChapters(String projectId) => repository.getChaptersForProject(projectId);

  Future<ChapterModel> createChapter({required String projectId, required String title}) async {
    final existing = await repository.getChaptersForProject(projectId);
    final chapter = ChapterModel(
      id: ProjectRepository.generateId(),
      projectId: projectId,
      title: title,
      order: existing.length,
    );
    await repository.saveChapter(chapter);
    return chapter;
  }

  Future<void> deleteChapter(String id) => repository.deleteChapterCascade(id);

  Future<List<StoryNodeModel>> loadNodes(String chapterId) => repository.getNodesForChapter(chapterId);

  /// Appends a new version under [parentNodeId] (or as the trunk root when
  /// null) with the given [content].
  Future<StoryNodeModel> saveVersion({
    required String chapterId,
    String? parentNodeId,
    required String content,
    String branchName = '',
  }) async {
    final node = StoryNodeModel(
      id: ProjectRepository.generateId(),
      chapterId: chapterId,
      parentNodeId: parentNodeId,
      content: content,
      branchName: branchName,
      timestamp: DateTime.now(),
    );
    await repository.saveNode(node);
    return node;
  }

  /// Forks a new named branch from [fromNode], starting with a copy of its
  /// content — the author then diverges from there in the editor.
  Future<StoryNodeModel> createBranch({required StoryNodeModel fromNode, required String branchName}) {
    return saveVersion(
      chapterId: fromNode.chapterId,
      parentNodeId: fromNode.id,
      content: fromNode.content,
      branchName: branchName,
    );
  }

  @override
  void dispose() {
    if (_ownsRepository) repository.close();
    super.dispose();
  }
}
