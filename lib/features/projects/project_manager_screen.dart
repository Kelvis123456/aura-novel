import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/exceptions/api_exceptions.dart';
import '../editor/editor_screen.dart';
import 'backup_service.dart';
import 'branch_tree_viewer.dart';
import 'editor_document_binding.dart';
import 'export_dialog.dart';
import 'map_screen.dart';
import 'models/project_model.dart';
import 'models/story_node_model.dart';
import 'project_cards.dart';
import 'project_controller.dart';
import '../writer/diff_review_sheet.dart';
import 'board_screen.dart';
import 'timeline_screen.dart';
import 'wiki_export_service.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/widgets/aura_mark.dart';
import '../../core/widgets/skeleton.dart';

/// Entry point for project management: list projects → drill into a
/// project's chapters → drill into a chapter's branching history
/// ([BranchTreeViewer]), from where any version can be opened in
/// [EditorScreen] or forked into a new named branch.
class ProjectManagerScreen extends StatefulWidget {
  final Color? accentColor;

  const ProjectManagerScreen(
      {super.key, this.accentColor,});

  @override
  State<ProjectManagerScreen> createState() => _ProjectManagerScreenState();
}

class _ProjectManagerScreenState extends State<ProjectManagerScreen> {
  late final ProjectController _controller;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _controller = ProjectController(repository: scope.projectRepository, lore: scope.loreRepository)
      ..addListener(_onChanged);
    _controller.loadProjects();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _exportBackup() async {
    final service = AppScope.of(context).backupService;
    try {
      await service.exportAndShare();
    } catch (_) {
      _showMessage('No se pudo crear la copia de seguridad.');
    }
  }

  Future<void> _restoreBackup() async {
    final service = AppScope.of(context).backupService;
    final picked =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;

    try {
      final summary = await service.restoreFromJson(utf8.decode(bytes));
      await _controller.loadProjects();
      _showMessage(
        'Restaurado: ${summary.projects} proyectos, ${summary.chapters} capítulos, '
        '${summary.characters} personajes y ${summary.loreItems} entradas de lore.',
      );
    } on BackupFormatException catch (e) {
      _showMessage(e.message);
    } on FormatException {
      _showMessage('El archivo no se pudo leer como texto.');
    } catch (_) {
      _showMessage(
          'No se pudo restaurar la copia. No se cambió nada en los datos dañados.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _createProject() async {
    final result = await _showProjectDialog();
    if (result == null) return;
    await _controller.createProject(title: result.$1, synopsis: result.$2);
  }

  Future<(String, String)?> _showProjectDialog() async {
    final titleController = TextEditingController();
    final synopsisController = TextEditingController();
    final accent = (widget.accentColor ?? context.aura.accent);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.aura.surface,
        title:
            Text('Nuevo proyecto', style: TextStyle(color: context.aura.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              style: TextStyle(color: context.aura.text),
              decoration: InputDecoration(
                  labelText: 'Título',
                  labelStyle: TextStyle(color: context.aura.textDim)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: synopsisController,
              maxLines: 3,
              style: TextStyle(color: context.aura.text),
              decoration: InputDecoration(
                  labelText: 'Sinopsis',
                  labelStyle: TextStyle(color: context.aura.textDim)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text('Cancelar', style: TextStyle(color: context.aura.textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved != true || titleController.text.trim().isEmpty) return null;
    return (titleController.text.trim(), synopsisController.text.trim());
  }

  Future<void> _confirmDeleteProject(ProjectModel project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.aura.surface,
        title: Text('¿Eliminar "${project.title}"?',
            style: TextStyle(color: context.aura.text, fontSize: 16)),
        content: Text(
          'Se eliminarán también todos sus capítulos y versiones guardadas. Esta acción no se puede deshacer.',
          style: TextStyle(color: context.aura.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text('Cancelar', style: TextStyle(color: context.aura.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Eliminar',
                style: TextStyle(color: context.aura.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.deleteProject(project.id);
  }

  @override
  Widget build(BuildContext context) {
    final accent = (widget.accentColor ?? context.aura.accent);

    return Scaffold(
      backgroundColor: context.aura.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Mis Proyectos'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Copia de seguridad',
            color: context.aura.surface,
            onSelected: (value) =>
                value == 'export' ? _exportBackup() : _restoreBackup(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'export', child: Text('Exportar copia de seguridad')),
              PopupMenuItem(
                  value: 'restore',
                  child: Text('Restaurar copia de seguridad')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: context.aura.bg,
        ),
        child: _controller.isLoading
            ? const SkeletonList()
            : _controller.projects.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AuraMark(size: 72),
                          const SizedBox(height: 24),
                          Text(
                            'Tu primera novela empieza aquí',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: AuraFonts.manuscript, fontSize: 24, color: context.aura.text),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Crea un proyecto con "+", añade capítulos y escribe con la IA que prefieras.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.aura.textDim, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: _controller.projects.length,
                    itemBuilder: (context, index) {
                      final project = _controller.projects[index];
                      return ProjectCard(
                        project: project,
                        accent: accent,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _ChapterListScreen(
                                project: project,
                                controller: _controller,
                                accent: accent),
                          ),
                        ),
                        onDelete: () => _confirmDeleteProject(project),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        onPressed: _createProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ChapterListScreen extends StatefulWidget {
  final ProjectModel project;
  final ProjectController controller;
  final Color accent;

  const _ChapterListScreen(
      {required this.project, required this.controller, required this.accent});

  @override
  State<_ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<_ChapterListScreen> {
  List<ChapterModel> _chapters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final chapters = await widget.controller.loadChapters(widget.project.id);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _isLoading = false;
    });
  }

  Future<void> _createChapter() async {
    final titleController = TextEditingController();
    final accent = widget.accent;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.aura.surface,
        title:
            Text('Nuevo capítulo', style: TextStyle(color: context.aura.text)),
        content: TextField(
          controller: titleController,
          autofocus: true,
          style: TextStyle(color: context.aura.text),
          decoration: InputDecoration(
              labelText: 'Título',
              labelStyle: TextStyle(color: context.aura.textDim)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text('Cancelar', style: TextStyle(color: context.aura.textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (saved == true && titleController.text.trim().isNotEmpty) {
      await widget.controller.createChapter(
          projectId: widget.project.id, title: titleController.text.trim());
      await _load();
    }
  }

  Future<void> _summarize(ChapterModel chapter) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = AppScope.of(context).chapterSummaryService;
    messenger.showSnackBar(
      const SnackBar(
          content: Text('Resumiendo capítulo…'),
          behavior: SnackBarBehavior.floating),
    );
    String message;
    try {
      final summary = await service.summarize(chapter);
      message = summary == null
          ? 'El capítulo no tiene texto todavía.'
          : 'Resumen guardado.';
    } on ApiClientException catch (e) {
      message = e.message;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(message), behavior: SnackBarBehavior.floating));
    if (mounted) await _load();
  }

  Future<void> _exportWiki() async {
    final scope = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    int? upTo;
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: context.aura.surface,
          title: Text('Exportar wiki',
              style: TextStyle(color: context.aura.text, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Incluye los personajes y el lore de este proyecto y los del universo compartido.',
                style: TextStyle(color: context.aura.textDim, fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: upTo,
                isExpanded: true,
                dropdownColor: context.aura.surface,
                decoration: const InputDecoration(labelText: 'Mostrar hasta'),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Todo el libro')),
                  for (var i = 0; i < _chapters.length; i++)
                    DropdownMenuItem<int?>(
                        value: i + 1,
                        child: Text('Capítulo ${i + 1}: ${_chapters[i].title}',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setDialogState(() => upTo = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Cancelar',
                  style: TextStyle(color: context.aura.textDim)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: widget.accent),
              child: const Text('Exportar'),
            ),
          ],
        ),
      ),
    );
    if (choice != true) return;

    final files = WikiExportService.buildFiles(
      project: widget.project,
      chapters: _chapters,
      characters: await scope.loreRepository.getAllCharacters(),
      loreItems: await scope.loreRepository.getAllLoreItems(),
      events:
          await scope.projectRepository.getTimelineEvents(widget.project.id),
      upToChapter: upTo,
    );
    try {
      await WikiExportService().exportAndShare(files, widget.project.title);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('No se pudo exportar la wiki: $e'),
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _checkConsistency(ChapterModel chapter) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = AppScope.of(context).consistencyService;
    messenger.showSnackBar(
      const SnackBar(
          content: Text('Revisando coherencia…'),
          behavior: SnackBarBehavior.floating),
    );
    List<String>? issues;
    String? error;
    try {
      issues = await service.check(chapter);
    } on ApiClientException catch (e) {
      error = e.message;
    }
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    if (error != null || issues == null) {
      messenger.showSnackBar(SnackBar(
        content: Text(error ?? 'El capítulo no tiene texto todavía.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final found = issues;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.aura.surface,
        title: Text('Coherencia: ${chapter.title}',
            style: TextStyle(color: context.aura.text, fontSize: 16)),
        content: SingleChildScrollView(
          child: Text(
            found.isEmpty
                ? 'No encontré contradicciones con tus fichas ni con los capítulos anteriores.'
                : found.map((i) => '• $i').join('\n\n'),
            style: TextStyle(color: context.aura.textDim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:
                Text('Cerrar', style: TextStyle(color: context.aura.textDim)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteChapter(ChapterModel chapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.aura.surface,
        title: Text('¿Eliminar "${chapter.title}"?',
            style: TextStyle(color: context.aura.text, fontSize: 16)),
        content: Text(
            'Se eliminarán también todas sus versiones guardadas.',
            style: TextStyle(color: context.aura.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text('Cancelar', style: TextStyle(color: context.aura.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Eliminar',
                style: TextStyle(color: context.aura.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.deleteChapter(chapter.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return Scaffold(
      backgroundColor: context.aura.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.project.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_kanban_outlined),
            tooltip: 'Tablero',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BoardScreen(project: widget.project, accent: widget.accent)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Mapa',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => MapScreen(
                      project: widget.project, accent: widget.accent)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: 'Exportar wiki',
            onPressed: _exportWiki,
          ),
          IconButton(
            icon: const Icon(Icons.timeline),
            tooltip: 'Línea de tiempo',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TimelineScreen(
                    project: widget.project,
                    chapters: _chapters,
                    accent: widget.accent),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exportar proyecto',
            onPressed: _chapters.isEmpty
                ? null
                : () => showExportDialog(
                      context,
                      project: widget.project,
                      chapters: _chapters,
                      repository: widget.controller.repository,
                      accent: accent,
                    ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: context.aura.bg,
        ),
        child: _isLoading
            ? const SkeletonList()
            : _chapters.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Aún no hay capítulos. Pulsa "+" para crear el primero.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.aura.textFaint, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: _chapters.length,
                    itemBuilder: (context, index) {
                      final chapter = _chapters[index];
                      return ChapterCard(
                        chapter: chapter,
                        accent: accent,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _ChapterDetailScreen(
                              project: widget.project,
                              chapter: chapter,
                              controller: widget.controller,
                              accent: accent,
                            ),
                          ),
                        ),
                        onDelete: () => _confirmDeleteChapter(chapter),
                        onSummarize: () => _summarize(chapter),
                        onCheckConsistency: () => _checkConsistency(chapter),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        onPressed: _createChapter,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ChapterDetailScreen extends StatefulWidget {
  final ProjectModel project;
  final ChapterModel chapter;
  final ProjectController controller;
  final Color accent;

  const _ChapterDetailScreen({
    required this.project,
    required this.chapter,
    required this.controller,
    required this.accent,
  });

  @override
  State<_ChapterDetailScreen> createState() => _ChapterDetailScreenState();
}

class _ChapterDetailScreenState extends State<_ChapterDetailScreen> {
  List<StoryNodeModel> _nodes = [];
  bool _isLoading = true;
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final nodes = await widget.controller.loadNodes(widget.chapter.id);
    if (!mounted) return;
    setState(() {
      _nodes = nodes;
      _isLoading = false;
    });
  }

  Future<void> _startFirstVersion() async {
    final node = await widget.controller
        .saveVersion(chapterId: widget.chapter.id, content: '');
    await _load();
    if (mounted) _openInEditor(node);
  }

  void _openInEditor(StoryNodeModel node) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => EditorScreen(
              accentColor: widget.accent,
              initialContent: node.content,
              documentBinding: EditorDocumentBinding(
                projectId: widget.project.id,
                chapterId: widget.chapter.id,
                nodeId: node.id,
              ),
            ),
          ),
        )
        .then((_) => _load());
  }

  Future<void> _handleSelectNode(StoryNodeModel node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.aura.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: widget.accent),
              title: Text('Abrir en el editor',
                  style: TextStyle(color: context.aura.text)),
              onTap: () => Navigator.of(sheetContext).pop('open'),
            ),
            ListTile(
              leading: Icon(Icons.call_split, color: widget.accent),
              title: Text('Crear rama desde aquí',
                  style: TextStyle(color: context.aura.text)),
              onTap: () => Navigator.of(sheetContext).pop('branch'),
            ),
          ],
        ),
      ),
    );

    if (action == 'open') {
      setState(() => _selectedNodeId = node.id);
      _openInEditor(node);
    } else if (action == 'branch') {
      await _createBranchFrom(node);
    }
  }

  Future<void> _compareWithParent(StoryNodeModel node) async {
    final parent = _nodes.where((n) => n.id == node.parentNodeId).firstOrNull;
    if (parent == null) return;
    await showDiffReview(context, original: parent.content, updated: node.content, readOnly: true);
  }

  Future<void> _createBranchFrom(StoryNodeModel node) async {
    final nameController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.aura.surface,
        title: Text('Nueva rama', style: TextStyle(color: context.aura.text)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: TextStyle(color: context.aura.text),
          decoration: InputDecoration(
            labelText: 'Nombre de la rama',
            hintText: 'ej. Ruta A: Aceptar la propuesta',
            labelStyle: TextStyle(color: context.aura.textDim),
            hintStyle: TextStyle(color: context.aura.textFaint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text('Cancelar', style: TextStyle(color: context.aura.textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: widget.accent),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (saved != true || nameController.text.trim().isEmpty) return;

    final branch = await widget.controller
        .createBranch(fromNode: node, branchName: nameController.text.trim());
    await _load();
    if (mounted) _openInEditor(branch);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return Scaffold(
      backgroundColor: context.aura.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.chapter.title, overflow: TextOverflow.ellipsis),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: context.aura.bg,
        ),
        child: _isLoading
            ? const SkeletonList()
            : BranchTreeViewer(
                nodes: _nodes,
                selectedNodeId: _selectedNodeId,
                accent: accent,
                onSelectNode: _handleSelectNode,
                onBranchFromNode: _createBranchFrom,
                onCompare: _compareWithParent,
              ),
      ),
      floatingActionButton: _nodes.isEmpty
          ? FloatingActionButton.extended(
              backgroundColor: accent,
              onPressed: _startFirstVersion,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Empezar a escribir'),
            )
          : null,
    );
  }
}
