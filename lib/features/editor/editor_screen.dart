import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/app_scope.dart';
import '../lore/lore_studio_screen.dart';
import '../projects/editor_document_binding.dart';
import '../projects/models/story_node_model.dart';
import '../projects/project_manager_screen.dart';
import '../projects/project_repository.dart';
import '../settings/api_settings_screen.dart';
import 'draft_autosaver.dart';
import 'editor_controller.dart';

/// Full-screen immersive writing canvas for "AURA NOVEL": streams AI
/// continuations directly into the document, offers a floating hot-prompt
/// bar, and exposes rewrite/expand/tone actions on text selection.
class EditorScreen extends StatefulWidget {
  final Color accentColor;
  final TextStyle? canvasTextStyle;

  /// Pre-fills the canvas, typically with a [StoryNodeModel]'s saved content
  /// when opened from [ProjectManagerScreen].
  final String? initialContent;

  /// Which project/chapter/node this canvas is attached to. When null, the
  /// editor behaves as a scratch buffer and "Guardar versión" stays disabled.
  final EditorDocumentBinding? documentBinding;

  const EditorScreen({
    super.key,
    this.accentColor = const Color(0xFFDC143C),
    this.canvasTextStyle,
    this.initialContent,
    this.documentBinding,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  late final EditorController _controller;
  late ProjectRepository _projectRepository;
  EditorDocumentBinding? _binding;
  DraftAutosaver? _autosaver;
  final _undoController = UndoHistoryController();
  final _canvasScrollController = ScrollController();
  final _promptFieldController = TextEditingController();
  final _promptFocusNode = FocusNode();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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
      storyContext: widget.documentBinding == null
          ? null
          : () => scope.chapterSummaryService.buildPriorSummariesMessage(
                widget.documentBinding!.projectId,
                widget.documentBinding!.chapterId,
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
    _showSnack('Recuperé lo que habías escrito sin guardar.');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _autosaver?.flush();
    }
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
    final accent = widget.accentColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF120709),
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'CAMBIAR TONO',
                    style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.2),
                  ),
                ),
                for (final tone in ToneShift.values)
                  ListTile(
                    leading: Icon(Icons.auto_awesome, color: accent, size: 18),
                    title: Text(tone.label, style: const TextStyle(color: Colors.white)),
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
    final accent = widget.accentColor;
    final distractionFree = _controller.distractionFreeMode;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF000000),
      drawer: _buildDrawer(accent),
      body: SafeArea(
        child: Column(
          children: [
            if (!distractionFree) _buildTopBar(accent),
            if (!distractionFree && _controller.wordGoal != null) _buildGoalBar(accent),
            if (!distractionFree && _controller.status == GenerationStatus.error)
              _buildErrorBanner(),
            Expanded(child: _buildCanvas(accent)),
            if (!distractionFree && _controller.pendingSuggestion != null && !_controller.isGenerating)
              _buildSuggestionBar(accent),
            if (!distractionFree) _buildPromptBar(accent),
          ],
        ),
      ),
      floatingActionButton: distractionFree
          ? FloatingActionButton.small(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              elevation: 0,
              onPressed: _controller.toggleDistractionFree,
              child: const Icon(Icons.fullscreen_exit, color: Colors.white70),
            )
          : null,
    );
  }

  Widget _buildTopBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white54, size: 20),
            tooltip: 'Menú',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Icon(Icons.circle, size: 8, color: _controller.isGenerating ? accent : Colors.white24),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: _editWordGoal,
              child: Text(
                '${_controller.wordCount} palabras · ${_controller.estimatedReadingMinutes} min de lectura'
                '${_controller.estimatedSessionTokens > 0 ? ' · ~${_controller.estimatedSessionTokens} tokens IA' : ''}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                  color: Colors.white54,
                  disabledColor: Colors.white12,
                  tooltip: 'Deshacer',
                  onPressed: value.canUndo ? _undoController.undo : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 20),
                  color: Colors.white54,
                  disabledColor: Colors.white12,
                  tooltip: 'Rehacer',
                  onPressed: value.canRedo ? _undoController.redo : null,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white54, size: 20),
            tooltip: _binding == null ? 'Abre este capítulo desde "Mis Proyectos" para guardar versiones' : 'Guardar versión',
            onPressed: _binding == null ? null : _saveVersion,
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white54, size: 20),
            tooltip: 'Modo inmersivo',
            onPressed: _controller.toggleDistractionFree,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white54, size: 20),
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
    final accent = widget.accentColor;
    final goal = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A0B12),
        title: const Text('Meta de palabras', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Palabras para esta sesión',
            labelStyle: TextStyle(color: Colors.white54),
            helperText: 'Cuenta solo lo que escribas desde que abriste el capítulo.',
            helperStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: const Text('Quitar meta', style: TextStyle(color: Colors.white54)),
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
              backgroundColor: Colors.white12,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            written >= goal ? 'Meta cumplida · $written' : '$written / $goal',
            style: TextStyle(color: written >= goal ? accent : Colors.white38, fontSize: 11),
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
          const Expanded(
            child: Text('Texto de la IA agregado', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          TextButton(
            onPressed: _controller.discardSuggestion,
            child: const Text('Descartar', style: TextStyle(color: Colors.white54)),
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

  Drawer _buildDrawer(Color accent) {
    return Drawer(
      backgroundColor: const Color(0xFF0D0508),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'AURA NOVEL',
                style: TextStyle(color: accent, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: Icon(Icons.auto_stories_outlined, color: accent),
              title: const Text('Studio de Personajes y Lore', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => LoreStudioScreen(accentColor: accent)),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.folder_open_outlined, color: accent),
              title: const Text('Mis Proyectos', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProjectManagerScreen(accentColor: accent)),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: accent),
              title: const Text('Ajustes de API', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ApiSettingsScreen(accentColor: accent)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _controller.errorMessage ?? 'Ocurrió un error durante la generación.',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent, size: 16),
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
        const TextStyle(
          fontFamily: 'serif',
          fontSize: 19,
          height: 1.6,
          color: Colors.white,
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
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Empieza a escribir, o pulsa "Continuar" para que la IA abra la escena…',
            hintStyle: TextStyle(color: Colors.white24, fontFamily: 'serif', fontSize: 19),
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
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            if (isGenerating) ...[
              _TypingIndicator(color: accent),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: TextField(
                controller: _promptFieldController,
                focusNode: _promptFocusNode,
                enabled: !isGenerating,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: isGenerating
                      ? 'Generando…'
                      : 'Instrucción rápida (ej. "aumenta la tensión")',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                ),
                onSubmitted: (_) => _handlePrimaryAction(),
              ),
            ),
            const SizedBox(width: 4),
            _PrimaryActionButton(
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

class _PrimaryActionButton extends StatelessWidget {
  final bool isGenerating;
  final Color accent;
  final VoidCallback onPressed;

  const _PrimaryActionButton({
    required this.isGenerating,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isGenerating ? Colors.white.withValues(alpha: 0.12) : accent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            isGenerating ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// Three pulsing dots shown next to the prompt bar while the model streams.
class _TypingIndicator extends StatefulWidget {
  final Color color;
  const _TypingIndicator({required this.color});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 16,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final t = (_animation.value + i * 0.2) % 1.0;
              final scale = 0.5 + 0.5 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
