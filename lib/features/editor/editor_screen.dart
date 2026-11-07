import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/app_scope.dart';
import '../lore/lore_studio_screen.dart';
import '../projects/continue_card.dart';
import '../projects/welcome_card.dart';
import '../writer/writing_profile.dart';
import '../projects/editor_document_binding.dart';
import '../projects/models/story_node_model.dart';
import '../projects/project_repository.dart';
import '../settings/api_settings_screen.dart';
import '../projects/writing_stats.dart';
import '../projects/daily_goal_card.dart';
import 'draft_autosaver.dart';
import 'editor_controller.dart';
import 'prompt_bar_widgets.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/widgets/aura_mark.dart';

/// Full-screen immersive writing canvas for "AURA NOVEL": streams AI
/// continuations directly into the document, offers a floating hot-prompt
/// bar, and exposes rewrite/expand/tone actions on text selection.
class EditorScreen extends StatefulWidget {
  final Color? accentColor;
  final TextStyle? canvasTextStyle;

  /// Pre-fills the canvas, typically with a [StoryNodeModel]'s saved content
  /// when opened from [ProjectManagerScreen].
  final String? initialContent;

  /// Which project/chapter/node this canvas is attached to. When null, the
  /// editor behaves as a scratch buffer and "Guardar versión" stays disabled.
  final EditorDocumentBinding? documentBinding;

  /// Ticks when the Escribir tab is shown again; refreshes the continue card.
  final ValueNotifier<int>? visitSignal;

  const EditorScreen({
    super.key,
    this.accentColor,
    this.canvasTextStyle,
    this.initialContent,
    this.documentBinding,
    this.visitSignal,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  late final EditorController _controller;
  late ProjectRepository _projectRepository;
  EditorDocumentBinding? _binding;
  DraftAutosaver? _autosaver;
  int _loggedWords = 0;
  final _undoController = UndoHistoryController();
  final _canvasScrollController = ScrollController();
  final _promptFieldController = TextEditingController();
  final _promptFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _projectRepository = scope.projectRepository;
    _binding = widget.documentBinding;

    _controller = EditorController(
      client: scope.apiClient,
      storage: scope.configStorage,
      contextBuilder: scope.contextBuilder,
      projectId: widget.documentBinding?.projectId,
      proseSystem: () async {
        final project = widget.documentBinding == null ? null : await scope.projectRepository.getProject(widget.documentBinding!.projectId);
        return scope.promptComposer.proseSystem(project?.writingProfile ?? const WritingProfile());
      },
      storyContext: widget.documentBinding == null
          ? null
          : (maxChars) => scope.chapterSummaryService.buildPriorSummariesMessage(
                widget.documentBinding!.projectId,
                widget.documentBinding!.chapterId,
                maxChars: maxChars,
              ),
    )..addListener(_onControllerChanged);

    if (widget.initialContent != null) {
      _controller.textController.text = widget.initialContent!;
    }
    _controller.startSession();

    final binding = _binding;
    if (binding != null) {
      _autosaver = DraftAutosaver(
        repository: _projectRepository,
        chapterId: binding.chapterId,
        nodeId: binding.nodeId,
        savedContent: widget.initialContent ?? '',
      );
      WidgetsBinding.instance.addObserver(this);
      _recoverDraft();
    }
  }

  Future<void> _recoverDraft() async {
    final draft = await _autosaver?.recover();
    if (draft == null || !mounted) return;
    _controller.textController.text = draft;
    _controller.startSession();
    _loggedWords = 0;
    _showSnack('Recuperé lo que habías escrito sin guardar.');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _autosaver?.flush();
      _logProgress();
    }
  }

  /// Adds what was written since the last call to today's count (the daily goal and streak).
  void _logProgress() {
    final delta = _controller.wordsWrittenThisSession - _loggedWords;
    if (delta <= 0) return;
    _loggedWords += delta;
    _projectRepository.addWords(WritingStats.dayKey(DateTime.now()), delta);
  }

  void _onControllerChanged() {
    _autosaver?.onTextChanged(_controller.textController.text);
    setState(() {});
    if (_controller.isGenerating) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_canvasScrollController.hasClients) return;
        _canvasScrollController.jumpTo(_canvasScrollController.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logProgress();
    _autosaver?.flush();
    _autosaver?.dispose();
    _undoController.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _canvasScrollController.dispose();
    _promptFieldController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  void _handlePrimaryAction() {
    if (_controller.isGenerating) {
      _controller.cancelGeneration();
      return;
    }
    final instruction = _promptFieldController.text.trim();
    if (instruction.isEmpty) {
      _controller.continueStory();
    } else {
      _controller.generateCustomPrompt(instruction);
      _promptFieldController.clear();
    }
  }

  Future<void> _saveVersion() async {
    final binding = _binding;
    if (binding == null) return;

    final node = StoryNodeModel(
      id: ProjectRepository.generateId(),
      chapterId: binding.chapterId,
      parentNodeId: binding.nodeId,
      content: _controller.textController.text,
      timestamp: DateTime.now(),
    );
    await _projectRepository.saveNode(node);
    _logProgress();
    await _autosaver?.markSaved(nodeId: node.id, content: node.content);
    if (!mounted) return;
    setState(() => _binding = binding.withNode(node.id));
    _showSnack('Versión guardada.');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showToneMenu() {
    final accent = (widget.accentColor ?? context.aura.accent);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.aura.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'CAMBIAR TONO',
                    style: TextStyle(color: context.aura.textDim, fontSize: 12, letterSpacing: 1.2),
                  ),
                ),
                for (final tone in ToneShift.values)
                  ListTile(
                    leading: Icon(Icons.auto_awesome, color: accent, size: 18),
                    title: Text(tone.label, style: TextStyle(color: context.aura.text)),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _controller.changeSelectionTone(tone);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Injects Reescribir / Expandir / Cambiar Tono ahead of the platform's
  /// default copy/cut/paste items whenever there is an active selection.
  Widget _contextMenuBuilder(BuildContext context, EditableTextState editableTextState) {
    final selection = editableTextState.textEditingValue.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;

    final buttonItems = <ContextMenuButtonItem>[...editableTextState.contextMenuButtonItems];

    if (hasSelection) {
      buttonItems.insertAll(0, [
        ContextMenuButtonItem(
          label: 'Reescribir',
          onPressed: () {
            editableTextState.hideToolbar();
            _controller.rewriteSelection();
          },
        ),
        ContextMenuButtonItem(
          label: 'Expandir',
          onPressed: () {
            editableTextState.hideToolbar();
            _controller.expandSelection();
          },
        ),
        ContextMenuButtonItem(
          label: 'Cambiar tono',
          onPressed: () {
            editableTextState.hideToolbar();
            _showToneMenu();
          },
        ),
      ]);
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = (widget.accentColor ?? context.aura.accent);
    final distractionFree = _controller.distractionFreeMode;

    return Scaffold(
      backgroundColor: context.aura.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (!distractionFree) _buildTopBar(accent),
            if (!distractionFree && _controller.wordGoal != null) _buildGoalBar(accent),
            if (!distractionFree && _controller.status == GenerationStatus.error)
              _buildErrorBanner(),
            if (!distractionFree && _binding == null && widget.visitSignal != null && _controller.textController.text.isEmpty)
              ...[
                WelcomeCard(refresh: widget.visitSignal!),
                ContinueCard(refresh: widget.visitSignal!),
                DailyGoalCard(refresh: widget.visitSignal!),
              ],
            Expanded(child: _buildCanvas(accent)),
            if (!distractionFree && _controller.pendingSuggestion != null && !_controller.isGenerating)
              _buildSuggestionBar(accent),
            if (!distractionFree) _buildPromptBar(accent),
          ],
        ),
      ),
      floatingActionButton: distractionFree
          ? FloatingActionButton.small(
              backgroundColor: context.aura.line,
              elevation: 0,
              onPressed: _controller.toggleDistractionFree,
              child: Icon(Icons.fullscreen_exit, color: context.aura.textDim),
            )
          : null,
    );
  }

  Widget _buildTopBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            IconButton(
              icon: Icon(Icons.arrow_back, color: context.aura.textDim, size: 20),
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          else
            const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 0), child: AuraMark(size: 26)),
          Icon(Icons.circle, size: 8, color: _controller.isGenerating ? accent : context.aura.textFaint),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: _editWordGoal,
              child: Text(
                '${_controller.wordCount} palabras · ${_controller.estimatedReadingMinutes} min de lectura'
                '${_controller.estimatedSessionTokens > 0 ? ' · ~${_controller.estimatedSessionTokens} tokens IA' : ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.aura.textDim, fontSize: 12),
              ),
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _undoController,
            builder: (context, value, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.undo, size: 20),
                  color: context.aura.textDim,
                  disabledColor: context.aura.line,
                  tooltip: 'Deshacer',
                  onPressed: value.canUndo ? _undoController.undo : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 20),
                  color: context.aura.textDim,
                  disabledColor: context.aura.line,
                  tooltip: 'Rehacer',
                  onPressed: value.canRedo ? _undoController.redo : null,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.bookmark_add_outlined, color: context.aura.textDim, size: 20),
            tooltip: _binding == null ? 'Abre este capítulo desde "Mis Proyectos" para guardar versiones' : 'Guardar versión',
            onPressed: _binding == null ? null : _saveVersion,
          ),
          if (_binding != null)
            IconButton(
              icon: Icon(Icons.public_outlined, color: context.aura.textDim, size: 20),
              tooltip: 'Mundo de este proyecto',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => LoreStudioScreen(projectId: _binding?.projectId)),
              ),
            ),
          IconButton(
            icon: Icon(Icons.fullscreen, color: context.aura.textDim, size: 20),
            tooltip: 'Modo inmersivo',
            onPressed: _controller.toggleDistractionFree,
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: context.aura.textDim, size: 20),
            tooltip: 'Ajustes de API',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ApiSettingsScreen(accentColor: accent)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editWordGoal() async {
    final field = TextEditingController(text: _controller.wordGoal?.toString() ?? '');
    final accent = (widget.accentColor ?? context.aura.accent);
    final goal = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.aura.surface,
        title: Text('Meta de palabras', style: TextStyle(color: context.aura.text)),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: TextStyle(color: context.aura.text),
          decoration: InputDecoration(
            labelText: 'Palabras para esta sesión',
            labelStyle: TextStyle(color: context.aura.textDim),
            helperText: 'Cuenta solo lo que escribas desde que abriste el capítulo.',
            helperStyle: TextStyle(color: context.aura.textFaint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: Text('Quitar meta', style: TextStyle(color: context.aura.textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(int.tryParse(field.text.trim()) ?? 0),
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    field.dispose();
    if (goal != null) _controller.setWordGoal(goal);
  }

  Widget _buildGoalBar(Color accent) {
    final goal = _controller.wordGoal!;
    final written = _controller.wordsWrittenThisSession;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: (written / goal).clamp(0.0, 1.0),
              minHeight: 2,
              color: accent,
              backgroundColor: context.aura.line,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            written >= goal ? 'Meta cumplida · $written' : '$written / $goal',
            style: TextStyle(color: written >= goal ? accent : context.aura.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text('Texto de la IA agregado', style: TextStyle(color: context.aura.textDim, fontSize: 12)),
          ),
          TextButton(
            onPressed: _controller.discardSuggestion,
            child: Text('Descartar', style: TextStyle(color: context.aura.textDim)),
          ),
          FilledButton(
            onPressed: _controller.acceptSuggestion,
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.aura.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.aura.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: context.aura.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _controller.errorMessage ?? 'Ocurrió un error durante la generación.',
              style: TextStyle(color: context.aura.danger, fontSize: 12),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: context.aura.danger, size: 16),
            onPressed: () {
              setState(() => _controller.status = GenerationStatus.idle);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(Color accent) {
    final baseStyle = widget.canvasTextStyle ??
        TextStyle(
          fontFamily: AuraFonts.manuscript,
          fontSize: 19,
          height: 1.6,
          color: context.aura.text,
        );

    return GestureDetector(
      onTap: () {
        if (_controller.distractionFreeMode) return;
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _controller.distractionFreeMode ? 24 : 28,
          vertical: 8,
        ),
        child: TextField(
          controller: _controller.textController,
          scrollController: _canvasScrollController,
          undoController: _undoController,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: baseStyle,
          cursorColor: accent,
          contextMenuBuilder: _contextMenuBuilder,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Empieza a escribir, o pulsa "Continuar" para que la IA abra la escena…',
            hintStyle: TextStyle(color: context.aura.textFaint, fontFamily: AuraFonts.manuscript, fontSize: 19),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptBar(Color accent) {
    final isGenerating = _controller.isGenerating;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: context.aura.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.aura.line),
        ),
        child: Row(
          children: [
            if (isGenerating) ...[
              TypingIndicator(color: accent),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: TextField(
                controller: _promptFieldController,
                focusNode: _promptFocusNode,
                enabled: !isGenerating,
                style: TextStyle(color: context.aura.text, fontSize: 14),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: isGenerating
                      ? 'Generando…'
                      : 'Instrucción rápida (ej. "aumenta la tensión")',
                  hintStyle: TextStyle(color: context.aura.textFaint, fontSize: 14),
                ),
                onSubmitted: (_) => _handlePrimaryAction(),
              ),
            ),
            const SizedBox(width: 4),
            PrimaryActionButton(
              isGenerating: isGenerating,
              accent: accent,
              onPressed: _handlePrimaryAction,
            ),
          ],
        ),
      ),
    );
  }
}
